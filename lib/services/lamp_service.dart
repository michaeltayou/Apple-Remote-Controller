/// ESPHome native API client for the bedside lamp controller.
///
/// The board (NodeMCU ESP8266, ESPHome 2026.11.2) is wired to the lamp's
/// button panel: every command physically "presses" a button (150 ms GPIO
/// pulse). This client talks to it DIRECTLY over Wi-Fi — no Home Assistant,
/// no MQTT, no cloud.
///
/// Protocol: ESPHome native API — a small binary protobuf protocol over plain
/// TCP port 6053. Wire format per message (verified against aioesphomeapi):
///
///     [0x00 varint] [payload-length varint] [message-type varint] [payload]
///
/// Handshake (ESPHome 2026.x — the old Connect step was removed in 2026.1.0):
/// open socket (10 s timeout) → HelloRequest(1)/HelloResponse(2) →
/// if entity keys not cached: ListEntitiesRequest(11) → read responses until
/// ListEntitiesDoneResponse(19) → command.
///
/// PERFORMANCE: the session is PERSISTENT — one socket stays open and every
/// press reuses it (a per-press connect/handshake/close cycle costs ~0.5-1 s
/// and made hold-to-repeat lag badly). After >= 20 s idle a PingRequest(7)/
/// PingResponse(8) health-check runs first; any failure drops the session
/// and reconnects transparently.
///
/// Entities are matched by EXACT name (never hardcoded keys):
///   Switch "Lampe"        — power
///   Button "Luminosité +" — brightness +1 step   (note the é)
///   Button "Luminosité -" — brightness −1 step
///   Button "Kelvin +"     — warmer
///   Button "Kelvin -"     — cooler
///   Button "Jumeler"      — pairing (board holds the pin 4 s)
///
/// Rules honored here:
///  - Physical presses are >= 300 ms apart (throttle + coalesce; all calls
///    run through a single serialized queue).
///  - Only `lampOn` (optimistic, last-commanded) exists — the board reports
///    no brightness/kelvin values.
///  - 2 retries on timeout/socket errors; entities auto-discovered on first
///    use and cached in memory.
///  - Clean resource handling: socket always closed (try/finally).
///
/// Usage:
/// ```dart
/// final lamp = LampService('lampe-chambre.local');
/// lamp.status.addListener(() => print(lamp.status.value));
/// lamp.lampOn.addListener(() => print('on: ${lamp.lampOn.value}'));
/// await lamp.turnOn();
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

enum LampConnectionStatus { disconnected, connecting, ready, error }

class LampUnreachableException implements Exception {
  final Object? cause;
  LampUnreachableException([this.cause]);

  @override
  String toString() => 'LampUnreachableException(${cause ?? 'no response'})';
}

class EntityNotFoundException implements Exception {
  final String name;
  EntityNotFoundException(this.name);

  @override
  String toString() => 'EntityNotFoundException: "$name" not found on device';
}

// Message IDs from aioesphomeapi api.proto (verified, do not guess).
const _msgHelloRequest = 1;
const _msgHelloResponse = 2;
const _msgListEntitiesRequest = 11;
const _msgListEntitiesDone = 19;
const _msgListEntitiesSwitch = 17;
const _msgListEntitiesButton = 61;
const _msgSwitchCommand = 33;
const _msgButtonCommand = 62;

const _port = 6053;

/// Entity names on the device — exact match, including the é.
class LampEntities {
  static const power = 'Lampe';
  static const brightnessUp = 'Luminosité +';
  static const brightnessDown = 'Luminosité -';
  static const kelvinUp = 'Kelvin +';
  static const kelvinDown = 'Kelvin -';
  static const pair = 'Jumeler';
}

class LampService {
  String _host;

  LampService([this._host = 'lampe-chambre.local']);

  // ---------------------------------------------------------------- config

  /// Host or IP, e.g. "lampe-chambre.local" or "192.168.1.92".
  void configure({required String host}) {
    final cleaned = host.trim();
    if (cleaned.isNotEmpty) _host = cleaned;
  }

  String get host => _host;

  // -------------------------------------------------------------- observable

  final ValueNotifier<LampConnectionStatus> status =
      ValueNotifier(LampConnectionStatus.disconnected);

  /// LAST COMMANDED state (optimistic, not ground truth).
  final ValueNotifier<bool> lampOn = ValueNotifier(false);

  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  // ----------------------------------------------------------------- state

  final Map<String, int> _entityKeys = {};
  Future<void> _chain = Future.value();
  DateTime _lastPress = DateTime.fromMillisecondsSinceEpoch(0);

  /// Persistent session (reused across commands) + cached mDNS resolution.
  _Session? _session;
  String? _resolvedIp;
  DateTime _lastCommandAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _minPressGap = Duration(milliseconds: 300);
  static const _opTimeout = Duration(seconds: 12);
  static const _idleBeforePing = Duration(seconds: 20);

  /// Serializes ALL operations: physical presses must never overlap and the
  /// 300 ms throttle is enforced globally here.
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final next = _chain.then((_) => task());
    _chain = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _throttle() async {
    final gap = _minPressGap - DateTime.now().difference(_lastPress);
    if (gap > Duration.zero) await Future<void>.delayed(gap);
    _lastPress = DateTime.now();
  }

  // ------------------------------------------------------------- public API

  /// Forces re-fetch of entity keys (call if EntityNotFoundException).
  Future<void> refreshEntities() => _enqueue(() async {
        _entityKeys.clear();
        await _run((session) => _ensureEntities(session));
      });

  Future<void> turnOn() => _enqueue(() => _run((session) async {
        await _ensureEntities(session);
        await _throttle();
        await session.switchSet(_keyFor(LampEntities.power), true);
        lampOn.value = true; // rule: update immediately after the command
      }));

  Future<void> turnOff() => _enqueue(() => _run((session) async {
        await _ensureEntities(session);
        await _throttle();
        await session.switchSet(_keyFor(LampEntities.power), false);
        lampOn.value = false;
      }));

  Future<void> brightnessUp() => _pressButton(LampEntities.brightnessUp);
  Future<void> brightnessDown() => _pressButton(LampEntities.brightnessDown);
  Future<void> kelvinUp() => _pressButton(LampEntities.kelvinUp);
  Future<void> kelvinDown() => _pressButton(LampEntities.kelvinDown);

  /// The 4-second pairing hold — the UI shows its own warning first.
  Future<void> pair() => _pressButton(LampEntities.pair);

  /// Handshake only; true/false, never throws.
  Future<bool> testConnection() => _enqueue(() async {
        try {
          await _run((session) async {});
          return true;
        } catch (_) {
          return false;
        }
      });

  Future<void> _pressButton(String entity) => _enqueue(() => _run((session) async {
        await _ensureEntities(session);
        await _throttle();
        await session.buttonPress(_keyFor(entity));
      }));

  int _keyFor(String name) {
    final key = _entityKeys[name];
    if (key == null) throw EntityNotFoundException(name);
    return key;
  }

  Future<void> _ensureEntities(_Session session) async {
    if (_entityKeys.isNotEmpty) return;
    await session.listEntities((name, key) => _entityKeys[name] = key);
  }

  /// Runs [action] on the persistent session, opening/reconnecting it as
  /// needed — with 2 retries on timeout/socket errors. Entity-name misses
  /// are not retried.
  Future<void> _run(Future<void> Function(_Session session) action) async {
    Object? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        // If the session sat idle for a while it may have been dropped
        // silently — ping first so a dead link is caught BEFORE the real
        // command instead of swallowing it.
        if (_session != null &&
            DateTime.now().difference(_lastCommandAt) > _idleBeforePing) {
          await _session!.ping().timeout(const Duration(seconds: 3));
        }
        final session = await _ensureSession();
        await action(session).timeout(_opTimeout);
        _lastCommandAt = DateTime.now();
        status.value = LampConnectionStatus.ready;
        lastError.value = null;
        return;
      } on EntityNotFoundException catch (e) {
        status.value = LampConnectionStatus.error;
        lastError.value = e.toString();
        rethrow; // nothing retries this
      } catch (e) {
        lastFailure = e;
        await _dropSession();
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    status.value = LampConnectionStatus.error;
    lastError.value =
        'Lamp unreachable (${lastFailure ?? 'no response'})';
    throw LampUnreachableException(lastFailure);
  }

  Future<_Session> _ensureSession() async {
    final existing = _session;
    if (existing != null) return existing;
    status.value = LampConnectionStatus.connecting;
    final address =
        _resolvedIp ??= await _resolve().timeout(const Duration(seconds: 8));
    final session = await _Session.open(address).timeout(_opTimeout);
    _session = session;
    return session;
  }

  Future<void> _dropSession() async {
    final session = _session;
    _session = null;
    _resolvedIp = null; // re-resolve mDNS next time (DHCP may have moved it)
    await session?.close();
  }

  /// Closes the persistent session (call when the app is done with the lamp).
  Future<void> dispose() => _dropSession();

  Future<String> _resolve() async {
    final h = _host;
    if (InternetAddress.tryParse(h) != null) return h;
    if (h.endsWith('.local')) {
      final ip = await _mdnsResolve(h);
      if (ip != null) return ip;
    }
    return h;
  }

  Future<String?> _mdnsResolve(String name) async {
    final client = MDnsClient();
    try {
      await client.start();
      await for (final record
          in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(name))) {
        return record.address.address;
      }
    } catch (_) {
      // fall through to the system resolver
    } finally {
      client.stop();
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Session: one socket + handshake, closed after each action.
// ---------------------------------------------------------------------------

class _Session {
  final Socket socket;
  final _SocketReader reader;

  _Session(this.socket, this.reader);

  static Future<_Session> open(String address) async {
    final socket = await Socket.connect(
      address,
      _port,
      timeout: const Duration(seconds: 10),
    );
    final session = _Session(socket, _SocketReader(socket));
    session._write(_msgHelloRequest, _helloPayload());
    await session._expect(_msgHelloResponse);
    return session;
  }

  Future<void> listEntities(void Function(String name, int key) onEntity) async {
    _write(_msgListEntitiesRequest, const <int>[]);
    while (true) {
      final (type, payload) = await reader.readFrame();
      if (type == _msgListEntitiesDone) return;
      if (type == _msgListEntitiesSwitch || type == _msgListEntitiesButton) {
        final key = _scanFixed32(payload, field: 2);
        final name = _scanString(payload, field: 3);
        if (key != null && name != null) onEntity(name, key);
      }
    }
  }

  Future<void> switchSet(int key, bool on) async {
    _write(_msgSwitchCommand, _switchPayload(key, on));
    await socket.flush();
  }

  Future<void> buttonPress(int key) async {
    _write(_msgButtonCommand, _buttonPayload(key));
    await socket.flush();
  }

  /// PingRequest(7) -> PingResponse(8): cheap liveness check for the
  /// persistent session.
  Future<void> ping() async {
    _write(7, const <int>[]);
    await socket.flush();
    await _expect(8);
  }

  void _write(int type, List<int> payload) {
    final frame = BytesBuilder(copy: false)
      ..addByte(0x00)
      ..add(_encodeVarint(payload.length))
      ..add(_encodeVarint(type))
      ..add(payload);
    socket.add(frame.toBytes());
  }

  Future<void> _expect(int type) async {
    while (true) {
      final (frameType, _) = await reader.readFrame();
      if (frameType == type) return;
    }
  }

  Future<void> close() async {
    try {
      await socket.flush();
    } catch (_) {}
    try {
      socket.destroy();
    } catch (_) {}
    reader.cancel();
  }
}

// ---------------------------------------------------------------------------
// Minimal protobuf wire helpers (only what these messages use).
// ---------------------------------------------------------------------------

List<int> _encodeVarint(int value) {
  final out = <int>[];
  var v = value;
  do {
    var b = v & 0x7f;
    v = v >> 7;
    if (v != 0) {
      b |= 0x80;
    }
    out.add(b);
  } while (v != 0);
  return out;
}

/// tag = (fieldNumber << 3) | wireType; wireType 0 = varint, 2 = length-
/// delimited, 5 = fixed32 (little-endian).
List<int> _tag(int field, int wire) => _encodeVarint((field << 3) | wire);

List<int> _stringField(int field, String value) {
  final bytes = utf8.encode(value);
  return [..._tag(field, 2), ..._encodeVarint(bytes.length), ...bytes];
}

List<int> _fixed32Field(int field, int value) => [
      ..._tag(field, 5),
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ];

List<int> _helloPayload() => _stringField(1, 'Apple TV Remote app');

List<int> _switchPayload(int key, bool on) => [
      ..._fixed32Field(1, key),
      ..._tag(2, 0),
      if (on) 1 else 0,
    ];

List<int> _buttonPayload(int key) => _fixed32Field(1, key);

int? _scanFixed32(Uint8List data, {required int field}) {
  var pos = 0;
  while (pos < data.length) {
    final tag = _readVarintFrom(data, pos);
    pos = tag.$2;
    final wire = tag.$1 & 7;
    final number = tag.$1 >> 3;
    if (number == field && wire == 5) {
      return data[pos] |
          (data[pos + 1] << 8) |
          (data[pos + 2] << 16) |
          (data[pos + 3] << 24);
    }
    pos = _skipField(data, pos, wire);
  }
  return null;
}

String? _scanString(Uint8List data, {required int field}) {
  var pos = 0;
  while (pos < data.length) {
    final tag = _readVarintFrom(data, pos);
    pos = tag.$2;
    final wire = tag.$1 & 7;
    final number = tag.$1 >> 3;
    if (number == field && wire == 2) {
      final len = _readVarintFrom(data, pos);
      pos = len.$2;
      return utf8.decode(data.sublist(pos, pos + len.$1));
    }
    pos = _skipField(data, pos, wire);
  }
  return null;
}

(int, int) _readVarintFrom(Uint8List data, int pos) {
  var result = 0;
  var shift = 0;
  while (pos < data.length) {
    final b = data[pos++];
    result |= (b & 0x7f) << shift;
    if ((b & 0x80) == 0) return (result, pos);
    shift += 7;
  }
  throw const FormatException('truncated varint');
}

int _skipField(Uint8List data, int pos, int wire) {
  switch (wire) {
    case 0:
      return _readVarintFrom(data, pos).$2;
    case 1:
      return pos + 8;
    case 2:
      final len = _readVarintFrom(data, pos);
      return len.$2 + len.$1;
    case 5:
      return pos + 4;
    default:
      throw FormatException('unsupported wire type $wire');
  }
}

// ---------------------------------------------------------------------------
// Buffered socket reader for the frame protocol.
// ---------------------------------------------------------------------------

class _SocketReader {
  final Socket _socket;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final List<Completer<void>> _waiters = [];
  Object? _error;
  bool _done = false;
  late final StreamSubscription<Uint8List> _sub;

  _SocketReader(this._socket) {
    _sub = _socket.listen(
      (data) {
        _buffer.add(data);
        _notify();
      },
      onError: (Object e) {
        _error = e;
        _notify();
      },
      onDone: () {
        _done = true;
        _notify();
      },
    );
  }

  void _notify() {
    final waiters = List<Completer<void>>.of(_waiters);
    _waiters.clear();
    for (final w in waiters) {
      if (!w.isCompleted) {
        w.complete();
      }
    }
  }

  Future<Uint8List> _take(int n) async {
    while (_buffer.length < n) {
      if (_error != null) {
        Error.throwWithStackTrace(
          StateError('socket error: $_error'),
          StackTrace.current,
        );
      }
      if (_done) {
        throw StateError('connection closed by the lamp');
      }
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }
    final all = _buffer.takeBytes();
    final out = Uint8List.fromList(all.sublist(0, n));
    _buffer.add(all.sublist(n));
    return out;
  }

  Future<int> _varint() async {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = (await _take(1))[0];
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
      if (shift > 28) throw const FormatException('varint too long');
    }
  }

  Future<(int, Uint8List)> readFrame() async {
    final preamble = await _varint();
    if (preamble != 0) {
      throw FormatException('invalid preamble 0x${preamble.toRadixString(16)}');
    }
    final length = await _varint();
    final type = await _varint();
    final payload = length == 0 ? Uint8List(0) : await _take(length);
    return (type, payload);
  }

  void cancel() => _sub.cancel();
}
