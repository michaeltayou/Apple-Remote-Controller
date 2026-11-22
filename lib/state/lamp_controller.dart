import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lamp_service.dart';

enum LampReachability { unknown, online, offline }

/// State for the living-room lamp (FL216 controller box).
///
/// The box tracks no state — brightness/kelvin are relative steps and even
/// on/off is just a button press — so the lamp's power state is tracked
/// locally (persisted) from the user's last action.
class LampController extends ChangeNotifier {
  static const _kBaseUrlKey = 'lamp_base_url';
  static const _kIsOnKey = 'lamp_is_on';
  static const defaultBaseUrl = 'http://lampe.local';

  final LampService service;

  LampReachability reachability = LampReachability.unknown;
  bool isOn = false;
  String? statusMessage;

  LampController({LampService? service})
      : service = service ??
            LampService(defaultBaseUrl,
                fallbackUrl: 'http://192.168.1.92') {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    isOn = prefs.getBool(_kIsOnKey) ?? false;
    service.baseUrl = prefs.getString(_kBaseUrlKey) ?? defaultBaseUrl;
    notifyListeners();
    ping();
  }

  String get baseUrl => service.baseUrl;

  Future<void> setBaseUrl(String url) async {
    var cleaned = url.trim();
    if (cleaned.isEmpty) cleaned = defaultBaseUrl;
    if (!cleaned.startsWith('http')) cleaned = 'http://$cleaned';
    service.baseUrl = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrlKey, cleaned);
    reachability = LampReachability.unknown;
    statusMessage = null;
    notifyListeners();
    ping();
  }

  /// Reachability check against GET /api/status.
  Future<void> ping() async {
    try {
      final s = await service.status();
      reachability = LampReachability.online;
      statusMessage = 'Lamp box online · ${s.ip} · ${s.rssi} dBm';
    } catch (e) {
      reachability = LampReachability.offline;
      statusMessage = 'Lamp box unreachable — same Wi-Fi as the lamp?';
    }
    notifyListeners();
  }

  Future<void> _runCommand(Future<void> Function() command) async {
    try {
      await command();
      // Any successful command implies the box is reachable.
      if (reachability != LampReachability.online) {
        reachability = LampReachability.online;
        statusMessage = null;
        notifyListeners();
      }
    } catch (e) {
      reachability = LampReachability.offline;
      statusMessage = e.toString();
      notifyListeners();
    }
  }

  /// Toggles power from the last known state (default: assume off).
  Future<void> power() async {
    HapticFeedback.lightImpact();
    final turningOn = !isOn;
    await _runCommand(() => turningOn ? service.on() : service.off());
    if (reachability == LampReachability.online) {
      isOn = turningOn;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsOnKey, isOn);
    }
  }

  Future<void> brightnessUp() => _runCommand(service.lumUp);
  Future<void> brightnessDown() => _runCommand(service.lumDown);
  Future<void> warmer() => _runCommand(service.kelvinUp);
  Future<void> cooler() => _runCommand(service.kelvinDown);
}