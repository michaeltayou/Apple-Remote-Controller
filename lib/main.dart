import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/lamp_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/scanner_screen.dart';
import 'state/lamp_controller.dart';
import 'state/remote_controller.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RemoteController()),
        ChangeNotifierProvider(create: (_) => LampController()),
      ],
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
      home: const HomeShell(),
    );
  }
}

/// Bottom-tab shell: [TV] the Apple TV remote, [Lamp] the living-room lamp.
/// IndexedStack keeps both tabs alive (connections and scroll state persist).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          TvTab(),
          LampScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.accent.withValues(alpha: 0.25),
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, color: AppColors.text),
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.tv_outlined, color: AppColors.textDim),
            selectedIcon: Icon(Icons.tv, color: Colors.white),
            label: 'TV',
          ),
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outline, color: AppColors.textDim),
            selectedIcon: Icon(Icons.lightbulb, color: Colors.white),
            label: 'Lamp',
          ),
        ],
      ),
    );
  }
}

/// The TV tab: scanner (no session) or remote (in a session). A dropped
/// connection does NOT swap screens — the remote shows an in-place
/// reconnect overlay until the link is back.
class TvTab extends StatelessWidget {
  const TvTab({super.key});

  @override
  Widget build(BuildContext context) {
    final hasSession = context.select(
      (RemoteController c) => c.hasSession,
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: hasSession
          ? const RemoteScreen(key: ValueKey('remote'))
          : const ScannerScreen(key: ValueKey('scanner')),
    );
  }
}
