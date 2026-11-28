import 'package:flutter/material.dart';

import '../models/apple_tv_app.dart';
import '../state/remote_controller.dart';
import '../theme.dart';

/// Bottom sheet listing the apps installed on the connected Apple TV;
/// tapping one launches it on the TV.
Future<void> showAppsSheet(
  BuildContext context,
  RemoteController controller,
) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AppsSheet(controller: controller),
  );
}

class _AppsSheet extends StatefulWidget {
  final RemoteController controller;

  const _AppsSheet({required this.controller});

  @override
  State<_AppsSheet> createState() => _AppsSheetState();
}

class _AppsSheetState extends State<_AppsSheet> {
  late Future<List<AppleTvApp>> _future = widget.controller.listApps();
  String? _launching;

  void _retry() {
    setState(() => _future = widget.controller.listApps());
  }

  Future<void> _launch(AppleTvApp app) async {
    if (_launching != null) return;
    setState(() => _launching = app.bundleId);
    await widget.controller.launchApp(app);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Launching ${app.name} on the Apple TV…')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.buttonPressed,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Apple TV Apps',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap an app to open it on the TV',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<AppleTvApp>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Could not load apps:\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textDim, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _retry,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  final apps = snapshot.data ?? const <AppleTvApp>[];
                  if (apps.isEmpty) {
                    return const Center(
                      child: Text(
                        'No launchable apps found.',
                        style: TextStyle(color: AppColors.textDim),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: apps.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: AppColors.button,
                      indent: 72,
                    ),
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      final launching = _launching == app.bundleId;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.button,
                          child: launching
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent,
                                  ),
                                )
                              : const Icon(Icons.apps,
                                  color: AppColors.text, size: 22),
                        ),
                        title: Text(app.name),
                        trailing: const Icon(Icons.play_circle_outline,
                            color: AppColors.textDim),
                        onTap: launching ? null : () => _launch(app),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
