import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/apple_tv_device.dart';
import '../services/atv_service.dart';

enum AtvStatus { initial, scanning, idle, pairing, connecting, connected }

class RemoteController extends ChangeNotifier {
  static const _kLastDeviceKey = 'last_apple_tv_identifier';
  static const _kPowerStateKey = 'apple_tv_power_state';

  final AtvService service;

  AtvStatus status = AtvStatus.initial;
  String? statusMessage;
  List<AppleTvDevice> devices = [];
  AppleTvDevice? selectedDevice;
  AppleTvDevice? connectedDevice;

  /// Tracked power state of the connected Apple TV: 'on' / 'off' / null
  /// (unknown). pyatv cannot poll power state on newer tvOS, so we track the
  /// last known state ourselves (protocol events + our own commands).
  String? powerState;

  StreamSubscription<Map<String, dynamic>>? _eventSub;

  RemoteController({AtvService? service})
      : service = service ?? AtvService() {
    _eventSub = this.service.events.listen(_handleEvent);
    this.service.onVolumeKey = handleVolumeKey;
    _init();
  }

  // ----------------------------------------------------- hardware volume keys

  DateTime _lastVolKey = DateTime.fromMillisecondsSinceEpoch(0);

  /// Hardware volume key pressed while the TV tab is active (routed by the
  /// tab shell). Throttled — key auto-repeat fires very fast.
  void handleVolumeKey(String direction) {
    if (status != AtvStatus.connected) return;
    final now = DateTime.now();
    if (now.difference(_lastVolKey) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastVolKey = now;
    sendCommand(direction == 'up' ? 'volume_up' : 'volume_down');
  }

  // ------------------------------------------------------------------ init

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    powerState = prefs.getString(_kPowerStateKey);
    await _requestPermissions();
    // Scan first: pyatv needs a fresh scan config (services/ports) to
    // connect; the credential storage only supplies the credentials.
    await scan();
    // Automatic reconnect to the last paired Apple TV on app launch.
    final last = prefs.getString(_kLastDeviceKey);
    if (last != null &&
        last.isNotEmpty &&
        devices.any((d) => d.identifier == last)) {
      await connectTo(last);
      return;
    }
    // Only one Apple TV on the network and it's already paired:
    // connect right away, no need to tap.
    if (devices.length == 1 &&
        await hasCredentials(devices.first.identifier)) {
      await connectTo(devices.first.identifier);
    }
  }

  Future<void> _requestPermissions() async {
    try {
      // Runtime permission required on Android 13+ (API 33) for Wi-Fi
      // discovery. Internet/change-multicast-state are install-time grants.
      await Permission.nearbyWifiDevices.request();
    } catch (_) {
      // permission_handler missing a mapping shouldn't block scanning.
    }
  }

  // ------------------------------------------------------------------ scan

  Future<void> scan() async {
    status = AtvStatus.scanning;
    statusMessage = 'Scanning for Apple TVs on this network…';
    notifyListeners();
    try {
      devices = await service.scan();
      status = AtvStatus.idle;
      statusMessage = devices.isEmpty
          ? 'No Apple TVs found. Make sure your phone and Apple TV are on the same Wi-Fi.'
          : null;
    } catch (e) {
      status = AtvStatus.idle;
      statusMessage = 'Scan failed: $e';
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- pairing

  /// Full pairing flow. The Apple TV shows a 4-digit PIN on the TV screen;
  /// [promptPin] must return the PIN the user typed (or null to cancel).
  /// Handles multi-protocol pairing (AirPlay, then Companion) transparently.
  Future<bool> pairAndConnect(
    AppleTvDevice device,
    Future<String?> Function(String protocol) promptPin,
  ) async {
    selectedDevice = device;
    status = AtvStatus.pairing;
    statusMessage = 'Connecting to ${device.name}…';
    notifyListeners();

    try {
      var result = await service.startPairing(device.identifier);
      while (result['ok'] == true && result['status'] == 'pin_required') {
        final protocol = result['protocol']?.toString() ?? 'AirPlay';
        final pin = await promptPin(protocol);
        if (pin == null) {
          await service.cancelPairing();
          status = AtvStatus.idle;
          statusMessage = 'Pairing cancelled.';
          notifyListeners();
          return false;
        }
        result = await service.finishPairing(pin);
        if (result['ok'] != true) break;
      }

      if (result['ok'] != true) {
        status = AtvStatus.idle;
        statusMessage = 'Pairing failed: ${result['error'] ?? 'unknown error'}';
        notifyListeners();
        return false;
      }

      return connectTo(device.identifier);
    } catch (e) {
      await service.cancelPairing();
      status = AtvStatus.idle;
      statusMessage = 'Pairing failed: $e';
      notifyListeners();
      return false;
    }
  }

  // -------------------------------------------------------------- connect

  Future<bool> connectTo(String identifier) async {
    status = AtvStatus.connecting;
    statusMessage = 'Connecting…';
    notifyListeners();
    try {
      final res = await service.connect(identifier);
      if (res['ok'] != true) {
        throw AtvException(res['error']?.toString() ?? 'Connect failed');
      }
      connectedDevice = devices.firstWhere(
        (d) => d.identifier == identifier,
        orElse: () => AppleTvDevice(
          identifier: identifier,
          name: res['name']?.toString() ?? 'Apple TV',
          address: identifier,
          model: 'Unknown',
          os: 'Unknown',
        ),
      );
      status = AtvStatus.connected;
      statusMessage = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastDeviceKey, identifier);
      // Prefer the state reported by the bridge; keep our tracked value if
      // the bridge couldn't determine it.
      powerState = _normalizePowerState(res['powerState']) ?? powerState;
      await prefs.setString(_kPowerStateKey, powerState ?? 'on');
    } catch (e) {
      status = AtvStatus.idle;
      statusMessage = 'Could not connect: $e';
    }
    notifyListeners();
    return status == AtvStatus.connected;
  }

  Future<bool> hasCredentials(String identifier) =>
      service.hasCredentials(identifier);

  /// App returned to the foreground — nudge the bridge to check/revive the
  /// connection (Android freezes background apps and their sockets).
  Future<void> notifyForeground() async {
    await service.onForeground();
  }

  /// Disconnect and return to the scanner (switch device).
  Future<void> switchDevice() async {
    await service.disconnect();
    connectedDevice = null;
    status = AtvStatus.idle;
    statusMessage = null;
    notifyListeners();
    await scan();
  }

  /// Forget credentials (unpair) and return to the scanner.
  Future<void> unpairCurrent() async {
    final id = connectedDevice?.identifier;
    if (id != null) {
      await service.unpair(id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastDeviceKey);
    await switchDevice();
  }

  // -------------------------------------------------------------- commands

  Future<void> sendCommand(String cmd) async {
    try {
      await service.sendCommand(cmd);
      if (cmd == 'power_off') await _setPowerState('off');
      if (cmd == 'power_on') await _setPowerState('on');
      // A successful command proves the link is fine — clear any stale
      // error that was left showing in the header.
      if (statusMessage != null) {
        statusMessage = null;
        notifyListeners();
      }
    } catch (e) {
      statusMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _setPowerState(String state) async {
    powerState = state;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPowerStateKey, state);
  }

  static String? _normalizePowerState(dynamic raw) {
    if (raw == null) return null;
    switch (raw.toString().toLowerCase()) {
      case 'on':
      case 'idle':
        return 'on';
      case 'off':
        return 'off';
      default:
        return null;
    }
  }

  Future<void> sendText(String text) async {
    try {
      await service.sendText(text);
    } catch (e) {
      statusMessage = e.toString();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- events

  /// Whether the user is in a remote session (connected to a device, or
  /// waiting for it to come back). Drives which screen is shown — the remote
  /// screen stays put through reconnects; only an explicit disconnect or
  /// device switch ends the session.
  bool get hasSession => connectedDevice != null;

  void _handleEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'connected':
        status = AtvStatus.connected;
        statusMessage = null;
        notifyListeners();
        break;
      case 'connection_lost':
        // Stay on the remote screen; show an in-place reconnect overlay.
        status = AtvStatus.connecting;
        statusMessage =
            'Connection lost — reconnecting to ${connectedDevice?.name ?? 'Apple TV'}…';
        notifyListeners();
        break;
      case 'reconnecting':
        status = AtvStatus.connecting;
        statusMessage = 'Reconnecting to ${event['device'] ?? 'Apple TV'}…';
        notifyListeners();
        break;
      case 'disconnected':
        connectedDevice = null;
        status = AtvStatus.idle;
        statusMessage = null;
        notifyListeners();
        break;
      case 'power_state':
        final normalized = _normalizePowerState(event['state']);
        if (normalized != null) _setPowerState(normalized);
        break;
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
