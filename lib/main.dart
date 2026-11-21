import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/remote_screen.dart';
import 'screens/scanner_screen.dart';
import 'state/remote_controller.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    ChangeNotifierProvider(
      create: (_) => RemoteController(),
      child: const AtvRemoteApp(),
    ),
  );
}

class AtvRemoteApp extends StatelessWidget {
  const AtvRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Apple TV Remote',
      debugShowCheckedModeBanner: false,
      theme: AppColors.dark(),
      home: const RootScreen(),
    );
  }
}

/// Swaps between the scanner (disconnected) and the remote (connected).
class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.select(
      (RemoteController c) => c.status,
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: status == AtvStatus.connected
          ? const RemoteScreen(key: ValueKey('remote'))
          : const ScannerScreen(key: ValueKey('scanner')),
    );
  }
}
