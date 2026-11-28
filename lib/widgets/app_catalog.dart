import 'package:flutter/material.dart';

/// Catalog of known tvOS bundle IDs used by "Detect my apps".
///
/// tvOS 26/27 removed the Companion app-list command, so detection works by
/// launching each ID once: installed apps open (and answer cleanly), missing
/// apps answer with FBSOpenApplicationErrorDomain — wrong guesses are
/// harmless and fail fast (~0.5 s each).
///
/// Verified against a real tvOS 27.2.1 device where marked ✓.
class TvCatalogApp {
  final String name;
  final String bundleId;
  final IconData icon;
  const TvCatalogApp(this.name, this.bundleId, this.icon);

  Map<String, String> toJson() => {'name': name, 'bundleId': bundleId};
}

const kTvAppCatalog = <TvCatalogApp>[
  // ---- Apple (built-in) ----
  TvCatalogApp('Apple TV', 'com.apple.TVWatchList', Icons.tv), // ✓ verified
  TvCatalogApp('Settings', 'com.apple.TVSettings', Icons.settings), // ✓
  TvCatalogApp('App Store', 'com.apple.TVAppStore', Icons.shop_2),
  TvCatalogApp('Music', 'com.apple.TVMusic', Icons.music_note), // ✓ (tvOS 27 renamed)
  TvCatalogApp('Music (old)', 'com.apple.Music', Icons.music_note),
  TvCatalogApp('Podcasts', 'com.apple.podcasts', Icons.podcasts),
  TvCatalogApp('Podcasts (alt)', 'com.apple.TVPodcasts', Icons.podcasts),
  TvCatalogApp('Photos', 'com.apple.TVPhotos', Icons.photo),
  TvCatalogApp('Fitness', 'com.apple.TVFitness', Icons.fitness_center),
  TvCatalogApp('Arcade', 'com.apple.TVGameCenter', Icons.videogame_asset),

  // ---- Major streaming ----
  TvCatalogApp('Netflix', 'com.netflix.Netflix', Icons.movie),
  TvCatalogApp('YouTube', 'com.google.ios.youtube', Icons.play_circle),
  TvCatalogApp('Disney+', 'com.disney.disneyplus', Icons.auto_awesome),
  TvCatalogApp('Prime Video', 'com.amazon.aiv.AIVApp', Icons.video_library),
  TvCatalogApp('Max', 'com.wbd.stream', Icons.movie_creation), // ✓ verified (HBO)
  TvCatalogApp('HBO Max', 'com.hbo.hbonow', Icons.movie_creation),
  TvCatalogApp('Max (alt)', 'com.wbd.max', Icons.movie_creation),
  TvCatalogApp('HBO (alt)', 'com.hbo.max', Icons.movie_creation),
  TvCatalogApp('Paramount+', 'com.cbsvideo.app', Icons.star),
  TvCatalogApp('Hulu', 'com.hulu.plus', Icons.live_tv),
  TvCatalogApp('Peacock', 'com.peacocktv.peacock', Icons.emoji_nature),
  TvCatalogApp('Apple TV+ (web)', 'com.apple.TVWatchList', Icons.tv),
  TvCatalogApp('Crunchyroll', 'com.crunchyroll.crunchyroll', Icons.animation),
  TvCatalogApp('Twitch', 'tv.twitch.tv', Icons.sports_esports),
  TvCatalogApp('Tubi', 'com.tubitv.tubitv', Icons.theaters),
  TvCatalogApp('Pluto TV', 'tv.pluto.ios', Icons.public),
  TvCatalogApp('Vimeo', 'com.vimeo.tv', Icons.videocam),
  TvCatalogApp('Dailymotion', 'com.dailymotion.dailymotion', Icons.smart_display),
  TvCatalogApp('Shudder', 'com.shudder.tv', Icons.dark_mode),
  TvCatalogApp('MUBI', 'com.mubi.mubi', Icons.festival),
  TvCatalogApp('Plex', 'com.plexapp.plex', Icons.play_arrow),
  TvCatalogApp('VLC', 'org.videolan.vlc-ios', Icons.ondemand_video),
  TvCatalogApp('Infuse', 'com.firecore.infuse', Icons.local_movies),
  TvCatalogApp('Swiftfin (Jellyfin)', 'org.jellyfin.swiftfin', Icons.play_circle_filled),
  TvCatalogApp('Emby', 'com.emby.emby', Icons.video_collection),

  // ---- France / Europe ----
  TvCatalogApp('Molotov', 'tv.molotov', Icons.cast),
  TvCatalogApp('myCanal', 'com.canalplus.CanalPlus', Icons.tv),
  TvCatalogApp('myCanal (alt)', 'com.canal.CanalPlus', Icons.tv),
  TvCatalogApp('france.tv', 'fr.france.tv', Icons.flag),
  TvCatalogApp('france.tv (alt)', 'fr.francetv.france.tv', Icons.flag),
  TvCatalogApp('TF1+', 'com.tf1.tf1plus', Icons.tv),
  TvCatalogApp('TF1 (alt)', 'com.tf1.apps', Icons.tv),
  TvCatalogApp('6play', 'com.groupem6.sixplay', Icons.tv),
  TvCatalogApp('6play (alt)', 'com.m6.6play', Icons.tv),
  TvCatalogApp('Arte', 'com.arte.tv', Icons.museum),
  TvCatalogApp('OCS', 'com.ocs.tv', Icons.movie),
  TvCatalogApp('RMC Sport', 'com.rmcsport.tv', Icons.sports_soccer),
  TvCatalogApp('beIN Sports', 'com.beinsports.tv', Icons.sports_soccer),
  TvCatalogApp('DAZN', 'com.dazn.theMobileApp', Icons.sports_soccer),
  TvCatalogApp('NBA', 'com.nba.NBATV', Icons.sports_basketball),
  TvCatalogApp('Red Bull TV', 'com.redbull.tv', Icons.sports_motorsports),
  TvCatalogApp('Zattoo', 'com.zattoo.tv', Icons.cast),
  TvCatalogApp('Waipu.tv', 'com.waipu.tv', Icons.cast),
  TvCatalogApp('RTL+', 'com.rtl.rtlplus', Icons.tv),
  TvCatalogApp('Joyn', 'de.prosiebensat1.joyn', Icons.tv),
  TvCatalogApp('Rakuten TV', 'com.rakuten.tv', Icons.shopping_cart),
  TvCatalogApp('Sky', 'com.sky.tv', Icons.cloud),
  TvCatalogApp('NOW', 'com.nowtv.tv', Icons.flash_on),

  // ---- Music / audio ----
  TvCatalogApp('Spotify', 'com.spotify.client', Icons.graphic_eq),
  TvCatalogApp('Spotify (alt)', 'com.spotify.tv', Icons.graphic_eq),
  TvCatalogApp('Deezer', 'com.deezer.deezer', Icons.queue_music),
  TvCatalogApp('TIDAL', 'com.tidal.tidal', Icons.waves),
  TvCatalogApp('TIDAL (alt)', 'com.tidal.tv', Icons.waves),
  TvCatalogApp('Amazon Music', 'com.amazon.music', Icons.music_video),
  TvCatalogApp('Pandora', 'com.pandora.radio', Icons.radio),
  TvCatalogApp('SoundCloud', 'com.soundcloud.tv', Icons.cloud_queue),
  TvCatalogApp('TuneIn', 'tunein.com.radio', Icons.radio),
  TvCatalogApp('Qobuz', 'com.qobuz.tv', Icons.audiotrack),

  // ---- Kids / misc ----
  TvCatalogApp('YouTube Kids', 'com.google.ios.youtubekids', Icons.child_care),
  TvCatalogApp('Nickelodeon', 'com.nick.nicktv', Icons.child_friendly),
  TvCatalogApp('Cartoon Network', 'com.cn.cartoonnetwork', Icons.animation),
  TvCatalogApp('PBS Kids', 'org.pbskids.video', Icons.child_care),
  TvCatalogApp('NBA League Pass', 'com.nba.leaguepass', Icons.sports_basketball),
  TvCatalogApp('MLB', 'com.mlb.mlb', Icons.sports_baseball),
  TvCatalogApp('NFL', 'com.nfl.nfl', Icons.sports_football),
  TvCatalogApp('ESPN', 'com.espn.espn', Icons.sports),
  TvCatalogApp('Fubo', 'com.fubo.tv', Icons.sports_soccer),
  TvCatalogApp('Sling', 'com.sling.slingtv', Icons.cast),
  TvCatalogApp('Philo', 'com.philo.philo', Icons.cast),
  TvCatalogApp('DirecTV', 'com.directv.stream', Icons.cast),
  TvCatalogApp('BritBox', 'com.britbox.britbox', Icons.castle),
  TvCatalogApp('Acorn TV', 'com.acorn.tv', Icons.park),
  TvCatalogApp('Discovery+', 'com.discovery.discoveryplus', Icons.travel_explore),
  TvCatalogApp('Hayu', 'com.hayu.hayu', Icons.face),
  TvCatalogApp('Aerial', 'com.jeffreygrossman.aerial', Icons.wallpaper),
  TvCatalogApp('Flipboard', 'com.flipboard.flipboard', Icons.article),
  TvCatalogApp('Weather Channel', 'com.weather.tv', Icons.cloud),
];
