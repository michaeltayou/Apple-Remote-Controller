import 'package:flutter/material.dart';

import '../models/apple_tv_app.dart';
import '../state/remote_controller.dart';
import '../theme.dart';

/// Bottom sheet for opening apps on the connected Apple TV.
///
/// Tries the live app list first (works on older tvOS). tvOS 26/27 no longer
/// answers the Companion app-list request (Apple-side regression, confirmed
/// on tvOS 27.2.1), so on failure a curated grid of common apps + a custom
/// bundle-ID field is shown — launching via _launchApp still works.
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

class _CuratedApp {
  final String name;
  final String bundleId;
  final IconData icon;
  const _CuratedApp(this.name, this.bundleId, this.icon);
}

const _curatedApps = [
  _CuratedApp('Apple TV', 'com.apple.TVWatchList', Icons.tv),
  _CuratedApp('Settings', 'com.apple.TVSettings', Icons.settings),
  _CuratedApp('App Store', 'com.apple.TVAppStore', Icons.shop_2),
  _CuratedApp('Netflix', 'com.netflix.Netflix', Icons.movie),
  _CuratedApp('YouTube', 'com.google.ios.youtube', Icons.play_circle),
  _CuratedApp('Disney+', 'com.disney.disneyplus', Icons.auto_awesome),
  _CuratedApp('Prime Video', 'com.amazon.aiv.AIVApp', Icons.video_library),
  _CuratedApp('Apple Music', 'com.apple.Music', Icons.music_note),
  _CuratedApp('Spotify', 'com.spotify.client', Icons.graphic_eq),
  _CuratedApp('Plex', 'com.plexapp.plex', Icons.play_arrow),
  _CuratedApp('VLC', 'org.videolan.vlc-ios', Icons.ondemand_video),
  _CuratedApp('Podcasts', 'com.apple.podcasts', Icons.podcasts),
];

class _AppsSheet extends StatefulWidget {
  final RemoteController controller;

  const _AppsSheet({required this.controller});

  @override
  State<_AppsSheet> createState() => _AppsSheetState();
}

class _AppsSheetState extends State<_AppsSheet> {
  late final Future<List<AppleTvApp>> _future = widget.controller.listApps();
  final _bundleController = TextEditingController();
  String? _launching;

  @override
  void dispose() {
    _bundleController.dispose();
    super.dispose();
  }

  Future<void> _launch(String name, String bundleId) async {
    if (_launching != null || bundleId.trim().isEmpty) return;
    setState(() => _launching = bundleId);
    await widget.controller
        .launchApp(AppleTvApp(name: name, bundleId: bundleId.trim()));
    if (!mounted) return;
    final error = widget.controller.statusMessage;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error != null && error.contains('Launch failed')
            ? error
            : 'Launching $name on the Apple TV…'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
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
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return _liveList(snapshot.data!);
                  }
                  // tvOS 26/27: the app-list request is dead — fall back to
                  // curated launchers + custom bundle ID.
                  return _curatedFallback();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveList(List<AppleTvApp> apps) {
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
                : const Icon(Icons.apps, color: AppColors.text, size: 22),
          ),
          title: Text(app.name),
          trailing: const Icon(Icons.play_circle_outline,
              color: AppColors.textDim),
          onTap: launching ? null : () => _launch(app.name, app.bundleId),
        );
      },
    );
  }

  Widget _curatedFallback() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const Text(
          "Your tvOS version no longer shares the installed-app list, "
          "so pick from the common apps below (only installed ones will "
          "open) or enter a bundle ID.",
          style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.1,
          children: [
            for (final app in _curatedApps) _appTile(app),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Custom bundle ID',
          style: TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _bundleController,
                autocorrect: false,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'e.g. com.netflix.Netflix',
                  filled: true,
                  fillColor: AppColors.button,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) => _launch(v.trim(), v),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () =>
                  _launch(_bundleController.text.trim(), _bundleController.text),
              child: const Text('Open'),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _appTile(_CuratedApp app) {
    final launching = _launching == app.bundleId;
    return Material(
      color: AppColors.button,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withValues(alpha: 0.12),
        onTap: launching ? null : () => _launch(app.name, app.bundleId),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (launching)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              )
            else
              Icon(app.icon, color: AppColors.text, size: 28),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                app.name,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
