import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/apple_tv_device.dart';

/// Thin typed wrapper around the Kotlin MethodChannel
/// (`com.example.appletv_remote/pyatv`) that talks to `atv_bridge.py`.
class AtvService {
  static const MethodChannel _channel =
      MethodChannel('com.example.appletv_remote/pyatv');

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  AtvService() {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  /// Async events pushed from Python (connected / connection_lost /
  /// reconnecting / pairing_complete) and forwarded by Kotlin.
  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> _handleNativeEvent(MethodCall call) async {
    if (call.method == 'onEvent' && call.arguments is String) {
      try {
        final decoded =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        _events.add(decoded);
      } catch (_) {
        // Malformed event — ignore rather than crash the handler.
      }
    }
  }

  Future<Map<String, dynamic>> _invoke(String method,
      [Map<String, dynamic>? args]) async {
    final raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>(method, args ?? const {});
    return raw?.map((k, v) => MapEntry(k.toString(), v)) ??
        const <String, dynamic>{};
  }

  Future<List<AppleTvDevice>> scan({int timeout = 5}) async {
    final res = await _invoke('scan', {'timeout': timeout});
    if (res['ok'] != true) {
      throw AtvException(res['error']?.toString() ?? 'Scan failed');
    }
    return (res['devices'] as List? ?? const [])
        .map((e) => AppleTvDevice.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Starts pairing; the Apple TV will show a PIN on screen.
  /// Returns the response map: `status` == 'pin_required', `protocol` name.
  Future<Map<String, dynamic>> startPairing(String identifier) =>
      _invoke('startPairing', {'identifier': identifier});

  /// Submits the 4-digit PIN shown on the TV. Response `status` is either
  /// 'done' (pairing finished for all protocols) or 'pin_required' again
  /// (another protocol needs its own PIN).
  Future<Map<String, dynamic>> finishPairing(String pin) =>
      _invoke('finishPairing', {'pin': pin});

  Future<Map<String, dynamic>> cancelPairing() => _invoke('cancelPairing');

  Future<Map<String, dynamic>> connect(String identifier) =>
      _invoke('connect', {'identifier': identifier});

  Future<Map<String, dynamic>> disconnect() => _invoke('disconnect');

  Future<bool> hasCredentials(String identifier) async {
    final res = await _invoke('hasCredentials', {'identifier': identifier});
    return res['paired'] == true;
  }

  Future<Map<String, dynamic>> unpair(String identifier) =>
      _invoke('unpair', {'identifier': identifier});

  /// Called when the app returns to the foreground — asks the bridge to
  /// probe the connection and revive it if the OS killed it while the app
  /// was backgrounded. Fire-and-forget.
  Future<void> onForeground() async {
    try {
      await _invoke('onForeground');
    } catch (_) {
      // Never let a revive attempt crash the UI.
    }
  }

  Future<void> sendCommand(String cmd) async {
    final res = await _invoke('sendCommand', {'cmd': cmd});
    if (res['ok'] != true) {
      throw AtvException(res['error']?.toString() ?? 'Command failed');
    }
  }

  Future<void> sendText(String text) async {
    final res = await _invoke('sendText', {'text': text});
    if (res['ok'] != true) {
      throw AtvException(res['error']?.toString() ?? 'Text input failed');
    }
  }
}

class AtvException implements Exception {
  final String message;
  AtvException(this.message);

  @override
  String toString() => message;
}
