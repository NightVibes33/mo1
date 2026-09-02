import 'dart:async';
import 'dart:io';

import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/services/audio_player_service.dart';
import 'package:dopi/core/services/debug_log_service.dart';
import 'package:dopi/core/services/native_eq_player_service.dart';
import 'package:dopi/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dopi/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

class _WidgetSyncController with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('mo1/widgets');

  _WidgetSyncController(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    final player = _ref.read(audioPlayerProvider);
    _positionSubscription = player.positionStream.listen((_) => scheduleSync());
    _playerStateSubscription = player.playerStateStream.listen(
      (_) => scheduleSync(force: true),
    );
    _nativeEqSnapshotSubscription = _ref
        .read(nativeEqPlayerServiceProvider)
        .playbackSnapshots()
        .listen((_) => scheduleSync());
    scheduleSync(force: true);
  }

  static const Duration _minimumSyncInterval = Duration(seconds: 15);

  final Ref _ref;
  Timer? _syncTimer;
  DateTime? _lastSyncAt;
  bool _forcePending = false;
  bool _syncInProgress = false;
  bool _syncAgain = false;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<dynamic>? _playerStateSubscription;
  StreamSubscription<NativeEqPlaybackSnapshot>? _nativeEqSnapshotSubscription;
  String? _lastSignature;
  bool _disposed = false;

  void scheduleSync({bool force = false}) {
    if (_disposed) {
      return;
    }
    _forcePending = _forcePending || force;
    if (_syncInProgress) {
      _syncAgain = true;
      return;
    }

    if (force) {
      _syncTimer?.cancel();
      _syncTimer = null;
    } else if (_syncTimer != null) {
      return;
    }

    final elapsed = _lastSyncAt == null
        ? _minimumSyncInterval
        : DateTime.now().difference(_lastSyncAt!);
    final delay = force || elapsed >= _minimumSyncInterval
        ? Duration.zero
        : _minimumSyncInterval - elapsed;
    _syncTimer = Timer(delay, () {
      _syncTimer = null;
      final runForce = _forcePending;
      _forcePending = false;
      unawaited(_runSync(force: runForce));
    });
  }

  Future<void> _runSync({required bool force}) async {
    if (_disposed || _syncInProgress) {
      return;
    }
    _syncInProgress = true;
    try {
      await _sync(force: force);
      _lastSyncAt = DateTime.now();
    } finally {
      _syncInProgress = false;
      if (_syncAgain || _forcePending) {
        final runForce = _forcePending;
        _syncAgain = false;
        scheduleSync(force: runForce);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      scheduleSync(force: true);
    }
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
      'trackTitle': metadata?.getTrackName ?? 'Open doPi',
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
      'deepLink': 'dopi://now-playing',
      'queuePreview': queuePreview,
    };
    final signature = snapshot.toString();
    if (!force && signature == _lastSignature) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('writeSnapshot', snapshot);
      _lastSignature = signature;
    } catch (error, stackTrace) {
      _ref.read(debugLogServiceProvider).warning(
            'widgets',
            'Widget snapshot sync failed.',
            data: {'error': error, 'stackTrace': stackTrace},
          );
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
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    unawaited(_positionSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_nativeEqSnapshotSubscription?.cancel());
  }
}
