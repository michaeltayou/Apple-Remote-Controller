import 'package:appletv_remote/main.dart';
import 'package:appletv_remote/models/apple_tv_device.dart';
import 'package:appletv_remote/services/atv_service.dart';
import 'package:appletv_remote/state/remote_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAtvService extends AtvService {
  @override
  Future<List<AppleTvDevice>> scan({int timeout = 5}) async => const [
        AppleTvDevice(
          identifier: '192.168.1.20',
          name: 'Living Room Apple TV',
          address: '192.168.1.20',
          model: 'AppleTV6,2',
          os: 'TvOS',
          version: '17.4',
          services: ['AirPlay', 'Companion'],
        ),
      ];

  @override
  Future<bool> hasCredentials(String identifier) async => false;

  @override
  Future<Map<String, dynamic>> startPairing(String identifier) async =>
      {'ok': true, 'status': 'pin_required', 'protocol': 'AirPlay'};

  @override
  Future<Map<String, dynamic>> finishPairing(String pin) async =>
      {'ok': true, 'status': 'done'};

  @override
  Future<Map<String, dynamic>> cancelPairing() async => {'ok': true};

  @override
  Future<Map<String, dynamic>> connect(String identifier) async =>
      {'ok': true, 'name': 'Living Room Apple TV', 'identifier': identifier};

  @override
  Future<Map<String, dynamic>> disconnect() async => {'ok': true};

  @override
  Future<void> sendCommand(String cmd) async {}

  @override
  Future<void> sendText(String text) async {}
}

Future<void> pumpApp(WidgetTester tester, RemoteController controller) async {
  // Pre-seed the device list so the test doesn't depend on init timing.
  await controller.scan();
  await tester.pumpWidget(
    ChangeNotifierProvider<RemoteController>.value(
      value: controller,
      child: const AtvRemoteApp(),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scanner lists discovered Apple TVs', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = RemoteController(service: FakeAtvService());
    await pumpApp(tester, controller);

    expect(find.text('Apple TV Remote'), findsOneWidget);
    expect(find.text('Living Room Apple TV'), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
      'tapping a device opens the PIN dialog and then shows the remote',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = RemoteController(service: FakeAtvService());
    await pumpApp(tester, controller);

    await tester.tap(find.text('Living Room Apple TV'));
    await tester.pump(const Duration(milliseconds: 300));

    // The TV would show this PIN; the app asks for it.
    expect(find.textContaining('Pair with Living Room Apple TV'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.pump(const Duration(milliseconds: 300)); // submit + pop
    await tester.pump(const Duration(milliseconds: 500)); // connect completes

    expect(controller.status, AtvStatus.connected);
    // Remote screen characteristics: power, play/pause.
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    controller.dispose();
  });
}
