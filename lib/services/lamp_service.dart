import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/lamp_status.dart';

/// Client for the FL216 lamp controller box (NodeMCU ESP8266 bridging
/// HTTP GETs to optocoupler "button presses" on the lamp's RF remote).
///
/// Per the device's API doc:
/// - base URL defaults to `http://lampe.local`, falling back to
///   `http://192.168.1.92` when mDNS doesn't resolve;
/// - requests MUST be serialized (it's a microcontroller, ~150 ms per
///   press) — [_enqueue] chains every call after the previous one;
/// - a short minimum gap between commands keeps us within the ~3-4
///   calls/second the device tolerates.
class LampService {
  String baseUrl;
  final String fallbackUrl;

  /// Whether the fallback IP worked last time (tried first afterwards).
  bool _usedFallback = false;

  Future<void> _tail = Future.value();
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static const _minGap = Duration(milliseconds: 120);
  static const _connectTimeout = Duration(seconds: 3);
  static const _totalTimeout = Duration(seconds: 5);

  LampService(this.baseUrl, {this.fallbackUrl = 'http://192.168.1.92'});

  /// Runs [task] after every previously enqueued task has finished,
  /// keeping a small gap between commands.
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final next = _tail.then((_) async {
      final gap = _minGap - DateTime.now().difference(_lastCall);
      if (gap > Duration.zero) await Future<void>.delayed(gap);
      try {
        return await task();
      } finally {
        _lastCall = DateTime.now();
      }
    });
    // Keep the queue alive even if a task throws.
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<Map<String, dynamic>> _get(String path) => _enqueue(() async {
        final urls = _usedFallback
            ? <String>[fallbackUrl, baseUrl]
            : <String>[baseUrl, fallbackUrl];
        Object? lastError;
        for (final base in urls) {
          HttpClient? client;
          try {
            client = HttpClient()
              ..connectionTimeout = _connectTimeout;
            final request = await client.getUrl(Uri.parse('$base$path'));
            final response =
                await request.close().timeout(_totalTimeout);
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode == 200) {
              _usedFallback = (base == fallbackUrl);
              return jsonDecode(body) as Map<String, dynamic>;
            }
            lastError = 'HTTP ${response.statusCode}: $body';
          } catch (e) {
            lastError = e;
          } finally {
            client?.close();
          }
        }
        throw LampException('Lamp box unreachable ($lastError)');
      });

  Future<void> on() async => _get('/api/on');
  Future<void> off() async => _get('/api/off');
  Future<void> lumUp() async => _get('/api/lumup');
  Future<void> lumDown() async => _get('/api/lumdown');
  Future<void> kelvinUp() async => _get('/api/kup');
  Future<void> kelvinDown() async => _get('/api/kdown');

  Future<LampStatus> status() async =>
      LampStatus.fromMap(await _get('/api/status'));
}

class LampException implements Exception {
  final String message;
  LampException(this.message);

  @override
  String toString() => message;
}
