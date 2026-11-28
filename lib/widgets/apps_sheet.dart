import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/apple_tv_app.dart';
import '../state/remote_controller.dart';
import '../theme.dart';

/// Bottom sheet for opening apps on the connected Apple TV.
///
/// tvOS 26/27 no longer answers the Companion app-list request (Apple-side
/// regression, verified on tvOS 27.2.1), but LAUNCHING apps still works —
/// and the TV answers differently for installed vs missing bundle IDs. So:
/// 1. try the live list first (older tvOS);
/// 2. otherwise offer "Detect my apps": probe a catalog of known bundle IDs
///    (installed apps briefly open on the TV, missing ones fail silently),
///    remember the hits, and show exactly the user's apps from then on;
/// 3. plus a custom bundle-ID field for anything not in the catalog.
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

class _CatalogApp {
  final String name;
  final String bundleId;
  final IconData icon;
  const _CatalogApp(this.name, this.bundleId, this.icon);

  Map<String, String> toJson() => {'name': name, 'bundleId': bundleId};
}

/// Known tvOS bundle IDs. Wrong guesses are harmless — detection just
/// filters them out (the TV answers "not installed" for those).
const _catalog = [
  _CatalogApp('Apple TV', 'com.apple.TVWatchList', Icons.tv),
  _CatalogApp('Settings', 'com.apple.TVSettings', Icons.settings),
  _CatalogApp('App Store', 'com.apple.TVAppStore', Icons.shop_2),
  _CatalogApp('Music', 'com.apple.Music', Icons.music_note),
  _CatalogApp('Podcasts', 'com.apple.podcasts', Icons.podcasts),
  _CatalogApp('Photos', 'com.apple.TVPhotos', Icons.photo),
  _CatalogApp('Fitness', 'com.apple.TVFitness', Icons.fitness_center),
  _CatalogApp('Netflix', 'com.netflix.Netflix', Icons.movie),
  _CatalogApp('YouTube', 'com.google.ios.youtube', Icons.play_circle),
  _CatalogApp('Disney+', 'com.disney.disneyplus', Icons.auto_awesome),
  _CatalogApp('Prime Video', 'com.amazon.aiv.AIVApp', Icons.video_library),
  _CatalogApp('HBO Max', 'com.hbo.hbonow', Icons.movie_creation),
  _CatalogApp('Max', 'com.wbd.stream', Icons.movie_creation),
  _CatalogApp('Spotify', 'com.spotify.client', Icons.graphic_eq),
  _CatalogApp('Deezer', 'com.deezer.deezer', Icons.queue_music),
  _CatalogApp('Plex', 'com.plexapp.plex', Icons.play_arrow),
  _CatalogApp('VLC', 'org.videolan.vlc-ios', Icons.ondemand_video),
  _CatalogApp('Infuse', 'com.firecore.infuse', Icons.local_movies),
  _CatalogApp('Swiftfin', 'org.jellyfin.swiftfin', Icons.play_circle_filled),
  _CatalogApp('Twitch', 'tv.twitch.tv', Icons.sports_esports),
  _CatalogApp('Crunchyroll', 'com.crunchyroll.crunchyroll', Icons.animation),
  _CatalogApp('Paramount+', 'com.cbsvideo.app', Icons.star),
  _CatalogApp('Hulu', 'com.hulu.plus', Icons.live_tv),
  _CatalogApp('Peacock', 'com.peacocktv.peacock', Icons.emoji_nature),
  _CatalogApp('Molotov', 'tv.molotov', Icons.cast),
  _CatalogApp('DAZN', 'com.dazn.theMobileApp', Icons.sports_soccer),
  _CatalogApp('Apple Arcade', 'com.apple.TVGameCenter', Icons.videogame_asset),
];

const _kDetectedAppsKey = 'detected_tv_apps';

class _AppsSheet extends StatefulWidget {
  final RemoteController controller;

  const _AppsSheet({required this.controller});

  @override
  State<_AppsSheet> createState() => _AppsSheetState();
}

class _AppsSheetState extends State<_AppsSheet> {
  late final Future<List<AppleTvApp>> _future = widget.controller.listApps();
  final _bundleController = TextEditingController();

  List<_CatalogApp> _detected = [];
  bool _detecting = false;
  int _detectProgress = 0;
  String? _launching;

  @override
  void initState() {
    super.initState();
    _loadDetected();
  }

  @override
  void dispose() {
    _bundleController.dispose();
    super.dispose();
  }

  Future<void> _loadDetected() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kDetectedAppsKey) ?? const [];
    final apps = <_CatalogApp>[];
    for (final entry in raw) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final bundleId = map['bundleId']?.toString() ?? '';
        // Detected apps always come from the catalog, so the const icon is
        // recovered by bundle ID (dynamic IconData would break release
        // icon tree-shaking).
        final known = _catalog.where((a) => a.bundleId == bundleId);
        if (known.isNotEmpty) apps.add(known.first);
      } catch (_) {}
    }
    if (mounted) setState(() => _detected = apps);
  }

  Future<void> _saveDetected(List<_CatalogApp> apps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kDetectedAppsKey,
      apps.map((a) => jsonEncode(a.toJson())).toList(),
    );
  }

  /// Probes the catalog: launches each known bundle ID once. The TV answers
  /// differently for installed vs missing apps, so successes = installed.
  /// Installed apps briefly open on the TV during the scan.
  Future<void> _detectApps() async {
    if (_detecting) return;
    setState(() {
      _detecting = true;
      _detectProgress = 0;
    });
    final found = <_CatalogApp>[];
    for (var i = 0; i < _catalog.length; i++) {
      if (!mounted) return;
      setState(() => _detectProgress = i + 1);
      final app = _catalog[i];
      if (await widget.controller.tryLaunch(app.bundleId)) {
        found.add(app);
      }
      // Keep probes spaced: the TV needs a moment per launch attempt.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    await _saveDetected(found);
    if (!mounted) return;
    setState(() {
      _detecting = false;
      _detected = found;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(found.isEmpty
            ? 'No catalog apps detected — use a custom bundle ID below.'
            : 'Found ${found.length} apps. Press Home on the remote to return.'),
      ),
    );
  }

  Future<void> _launch(String name, String bundleId) async {
    if (_launching != null || bundleId.trim().isEmpty) return;
    setState(() => _launching = bundleId.trim());
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
        height: MediaQuery.of(context).size.height * 0.75,
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
                  return _fallback();
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

  Widget _fallback() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const Text(
          "Your tvOS version no longer shares the installed-app list. "
          "Run detection once: the app briefly opens each known app on the "
          "TV and keeps the ones that exist — then this grid shows exactly "
          "your apps.",
          style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        if (_detecting) ...[
          LinearProgressIndicator(
            value: _detectProgress / _catalog.length,
            color: AppColors.accent,
            backgroundColor: AppColors.button,
          ),
          const SizedBox(height: 8),
          Text(
            'Detecting… $_detectProgress/${_catalog.length} — watch your TV hop through installed apps',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
        ] else
          OutlinedButton.icon(
            onPressed: _detectApps,
            icon: const Icon(Icons.radar),
            label: Text(_detected.isEmpty
                ? 'Detect my apps (${_catalog.length} known apps)'
                : 'Re-detect my apps'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
            ),
          ),
        const SizedBox(height: 12),
        if (_detected.isNotEmpty)
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
            children: [
              for (final app in _detected) _appTile(app),
            ],
          )
        else if (!_detecting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No apps detected yet.',
                style: TextStyle(color: AppColors.textDim),
              ),
            ),
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

  Widget _appTile(_CatalogApp app) {
    final launching = _launching == app.bundleId;
    return Material(
      color: AppColors.button,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withValues(alpha: 0.12),
        onTap: (launching || _detecting)
            ? null
            : () => _launch(app.name, app.bundleId),
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
