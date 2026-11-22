import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lamp_service.dart';

enum LampReachability { unknown, online, offline }

/// State wrapper for the bedroom lamp (ESPHome native API, see
/// [LampService]). Adapts the service's ValueListenable-style API to the
/// app's ChangeNotifier pattern — widgets watch this controller.
///
/// The lamp reports nothing back: only the optimistic boolean [isOn] exists,
/// updated by the service immediately after a power command is sent.
class LampController extends ChangeNotifier {
  static const _kHostKey = 'lamp_host';
  static const defaultHost = 'lampe-chambre.local';

  final LampService service;

  LampReachability reachability = LampReachability.unknown;
  String? statusMessage;

  LampController({LampService? service})
      : service = service ?? LampService(defaultHost) {
    this.service.status.addListener(_syncFromService);
    this.service.lampOn.addListener(_syncFromService);
    this.service.lastError.addListener(_syncFromService);
    _init();
  }

  bool get isOn => service.lampOn.value;
  String get host => service.host;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kHostKey);
    if (saved != null && saved.isNotEmpty) service.configure(host: saved);
    notifyListeners();
    ping();
  }

  void _syncFromService() {
    reachability = switch (service.status.value) {
      LampConnectionStatus.ready => LampReachability.online,
      LampConnectionStatus.error => LampReachability.offline,
      LampConnectionStatus.connecting => LampReachability.unknown,
      LampConnectionStatus.disconnected => LampReachability.unknown,
    };
    statusMessage = service.lastError.value;
    notifyListeners();
  }

  Future<void> setHost(String host) async {
    service.configure(host: host);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHostKey, service.host);
    reachability = LampReachability.unknown;
    statusMessage = null;
    notifyListeners();
    ping();
  }

  /// Handshake-only reachability check.
  Future<void> ping() async {
    final ok = await service.testConnection();
    reachability = ok ? LampReachability.online : LampReachability.offline;
    statusMessage = ok ? null : 'Lamp unreachable — same Wi-Fi as the lamp?';
    notifyListeners();
  }

  /// Toggles power from the last known (optimistic) state.
  Future<void> power() async {
    HapticFeedback.lightImpact();
    if (isOn) {
      await service.turnOff();
    } else {
      await service.turnOn();
    }
  }

  Future<void> brightnessUp() => service.brightnessUp();
  Future<void> brightnessDown() => service.brightnessDown();
  Future<void> warmer() => service.kelvinUp();
  Future<void> cooler() => service.kelvinDown();

  @override
  void dispose() {
    service.status.removeListener(_syncFromService);
    service.lampOn.removeListener(_syncFromService);
    service.lastError.removeListener(_syncFromService);
    super.dispose();
  }
}
