import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/providers/filtered_audio_files_provider.dart';
import 'package:dope/core/services/apple_music_playback_service.dart';
import 'package:dope/core/services/music_metadata_lookup_service.dart';
import 'package:dope/core/services/native_eq_player_service.dart';
import 'package:dope/core/services/widget_sync_service.dart';
import 'package:dope/features/music/jellyfin/providers/jellyfin_connection_provider.dart';
import 'package:dope/features/music/navidrome/providers/navidrome_connection_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sourceHealthProvider = FutureProvider<SourceHealthSnapshot>((ref) async {
  final songsAsync = ref.watch(filteredAudioFilesProvider);
  final songs = songsAsync.when(
    data: (value) => value,
    loading: () => const <MusicMetadata>[],
    error: (_, __) => const <MusicMetadata>[],
  );
  final appleMusicLookup = ref.read(musicMetadataLookupServiceProvider);
  final appleMusicPlayback = ref.read(appleMusicPlaybackServiceProvider);
  final appleStatus = await appleMusicLookup.appleMusicAuthorizationStatus();
  final subscription = await appleMusicLookup.appleMusicSubscriptionStatus();
  final navidrome = ref.watch(navidromeConnectionProvider);
  final jellyfin = ref.watch(jellyfinConnectionProvider);
  final nativeEq = ref.read(nativeEqPlayerServiceProvider);

  int countWhere(bool Function(dynamic metadata) test) {
    var count = 0;
    for (final metadata in songs) {
      if (test(metadata)) count++;
    }
    return count;
  }

  return SourceHealthSnapshot(items: [
    SourceHealthItem(
      name: 'Local Audio',
      status: songs.isEmpty ? 'No songs imported' : '${countWhere((m) => m.isOnDevice)} local songs',
      isHealthy: songs.isNotEmpty,
      detail: 'Imports are stored inside the app library.',
    ),
    SourceHealthItem(
      name: 'Apple Music',
      status: appleStatus.message,
      isHealthy: appleStatus.canSearchCatalog && subscription.canPlayCatalogContent,
      detail: 'Playback supported: ${appleMusicPlayback.isSupported}; subscription playback: ${subscription.playbackMessage}',
    ),
    SourceHealthItem(
      name: 'Navidrome',
      status: navidrome == null ? 'Not connected' : 'Connected as ${navidrome.username}',
      isHealthy: navidrome != null,
      detail: navidrome == null ? 'Connect a Navidrome server from Music.' : navidrome.serverUrl,
    ),
    SourceHealthItem(
      name: 'Jellyfin',
      status: jellyfin == null ? 'Not connected' : 'Connected as ${jellyfin.username}',
      isHealthy: jellyfin != null,
      detail: jellyfin == null ? 'Connect a Jellyfin server from Music.' : jellyfin.serverUrl,
    ),
    SourceHealthItem(
      name: 'Native EQ',
      status: nativeEq.isSupported ? 'Available on this device' : 'Unavailable on ${defaultTargetPlatform.name}',
      isHealthy: nativeEq.isSupported,
      detail: 'Native EQ supports app-controlled local/remote playback, not Apple Music system playback.',
    ),
    SourceHealthItem(
      name: 'Widgets',
      status: widgetSyncAvailable ? 'Sync enabled' : 'Unavailable on this platform',
      isHealthy: widgetSyncAvailable,
      detail: 'Widgets use the iOS App Group snapshot bridge.',
    ),
  ]);
});

class SourceHealthSnapshot {
  final List<SourceHealthItem> items;

  const SourceHealthSnapshot({required this.items});
}

class SourceHealthItem {
  final String name;
  final String status;
  final String detail;
  final bool isHealthy;

  const SourceHealthItem({
    required this.name,
    required this.status,
    required this.detail,
    required this.isHealthy,
  });
}
