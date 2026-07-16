import 'dart:async';
import 'dart:io';

import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/core/services/native_eq_player_service.dart';
import 'package:dope/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool get widgetSyncAvailable => !kIsWeb && Platform.isIOS;

final widgetSyncProvider = Provider<void>((ref) {
  if (!widgetSyncAvailable) {
    return;
  }
  final controller = _WidgetSyncController(ref);
  ref.listen(nowPlayingDetailsProvider, (_, __) => controller.scheduleSync());
  ref.listen(settingsPreferencesControllerProvider, (_, __) => controller.scheduleSync());
  ref.onDispose(controller.dispose);
});

class _WidgetSyncController {
  static const MethodChannel _channel = MethodChannel('mo1/widgets');

  _WidgetSyncController(this._ref) {
    final player = _ref.read(audioPlayerProvider);
    _positionSubscription = player.positionStream.listen((_) => scheduleSync());
    _playerStateSubscription = player.playerStateStream.listen((_) => scheduleSync(force: true));
    _nativeEqSnapshotSubscription = _ref
        .read(nativeEqPlayerServiceProvider)
        .playbackSnapshots()
        .listen((_) => scheduleSync(force: true));
    scheduleSync(force: true);
  }

  final Ref _ref;
  Timer? _debounce;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<dynamic>? _playerStateSubscription;
  StreamSubscription<NativeEqPlaybackSnapshot>? _nativeEqSnapshotSubscription;
  String? _lastSignature;
  bool _disposed = false;

  void scheduleSync({bool force = false}) {
    if (_disposed) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_sync(force: force));
    });
  }

  Future<void> _sync({required bool force}) async {
    if (_disposed) {
      return;
    }
    final nowPlaying = _ref.read(nowPlayingDetailsProvider);
    final settings = _ref.read(settingsPreferencesControllerProvider);
    final metadata = nowPlaying.currentMetadata;
    final queuePreview = <Map<String, Object?>>[];
    if (nowPlaying.metadataList.isNotEmpty) {
      final start = nowPlaying.currentIndex + 1;
      final end = (start + 3).clamp(0, nowPlaying.metadataList.length).toInt();
      for (var index = start; index < end; index++) {
        final item = nowPlaying.metadataList[index];
        queuePreview.add({
          'title': item.getTrackName,
          'artist': item.getTrackArtistNames ?? item.getAlbumArtistName,
          'sourceType': _sourceTypeName(item),
          'isExplicit': item.isExplicit,
          'artworkPath': item.thumbnailPath,
        });
      }
    }

    final sourceType = metadata == null ? 'none' : _sourceTypeName(metadata);
    final eqSupported = metadata != null && !metadata.isAppleMusicCatalogTrack;
    final nativeEqActive = _ref.read(nativeEqPlaybackActiveProvider);
    final nativeEqSnapshot = nativeEqActive
        ? await _ref.read(nativeEqPlayerServiceProvider).snapshot()
        : null;
    final player = _ref.read(audioPlayerProvider);
    final durationSeconds = nativeEqSnapshot != null &&
            nativeEqSnapshot.duration != Duration.zero
        ? nativeEqSnapshot.duration.inSeconds
        : player.duration?.inSeconds ?? ((metadata?.getTrackDuration ?? 0) ~/ 1000);
    final rawPositionSeconds = nativeEqSnapshot?.position.inSeconds ??
        player.position.inSeconds;
    final positionSeconds = durationSeconds > 0
        ? rawPositionSeconds.clamp(0, durationSeconds).toInt()
        : rawPositionSeconds;
    final snapshot = <String, Object?>{
      'schemaVersion': 2,
      'trackTitle': metadata?.getTrackName ?? 'Open døPe',
      'artistName': metadata == null
          ? 'Choose music to start'
          : metadata.getTrackArtistNames ?? metadata.getAlbumArtistName,
      'albumName': metadata?.albumName ?? '',
      'sourceType': sourceType,
      'isExplicit': metadata?.isExplicit ?? false,
      'isPlaying': nowPlaying.isPlaying,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'queueIndex': metadata == null ? 0 : nowPlaying.currentIndex + 1,
      'queueCount': nowPlaying.metadataList.length,
      'eqName': settings.equalizerDisplayTitle,
      'eqSupported': eqSupported,
      'eqBandGainsDb': settings.activeEqualizerBandGainsDb,
      'eqPreampDb': settings.activeEqualizerPreampDb,
      'artworkPath': metadata?.thumbnailPath,
      'lastUpdatedEpochMs': DateTime.now().millisecondsSinceEpoch,
      'deepLink': 'dope://now-playing',
      'queuePreview': queuePreview,
    };
    final signature = snapshot.toString();
    if (!force && signature == _lastSignature) {
      return;
    }
    _lastSignature = signature;
    try {
      await _channel.invokeMethod<void>('writeSnapshot', snapshot);
    } catch (_) {
      // Widget sync must never interrupt playback or app startup.
    }
  }

  String _sourceTypeName(MusicMetadata metadata) {
    switch (metadata.sourceType) {
      case MusicSourceType.appleMusic:
        return 'appleMusic';
      case MusicSourceType.navidrome:
        return 'navidrome';
      case MusicSourceType.jellyfin:
        return 'jellyfin';
      case MusicSourceType.remote:
        return 'remote';
      case MusicSourceType.local:
        return 'mp3';
    }
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_positionSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_nativeEqSnapshotSubscription?.cancel());
  }
}
