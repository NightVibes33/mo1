import 'dart:async';
import 'dart:math';

import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/providers/filtered_audio_files_provider.dart';
import 'package:dopi/core/services/audio_equalizer_service.dart';
import 'package:dopi/core/services/apple_music_playback_service.dart';
import 'package:dopi/core/services/crash_log_service.dart';
import 'package:dopi/core/services/lyrics_lookup_service.dart';
import 'package:dopi/core/services/native_eq_player_service.dart';
import 'package:dopi/core/services/song_transition_analysis_service.dart';
import 'package:dopi/features/music/album/models/album_model.dart';
import 'package:dopi/features/music/jellyfin/providers/jellyfin_connection_provider.dart';
import 'package:dopi/features/music/jellyfin/providers/jellyfin_service_provider.dart';
import 'package:dopi/features/music/navidrome/providers/navidrome_connection_provider.dart';
import 'package:dopi/features/music/navidrome/providers/navidrome_service_provider.dart';
import 'package:dopi/features/music/playlist/models/playlist_model.dart';
import 'package:dopi/features/now_playing/models/now_playing_model.dart';
import 'package:dopi/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dopi/features/settings/controller/settings_preferences_controller.dart';
import 'package:dopi/features/settings/models/custom_equalizer_preset.dart';
import 'package:dopi/features/settings/models/song_transition_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

final audioPlayerProvider = Provider<AudioPlayer>((_) {
  return AudioPlayer();
});

final audioPlayerServiceProvider =
    AsyncNotifierProvider<AudioPlayerServiceNotifier, void>(
      AudioPlayerServiceNotifier.new,
    );

enum _PlaybackBackend {
  none,
  localDefaultPlayer,
  nativeEqPlayer,
  appleMusicSystem,
}

class AudioPlayerServiceNotifier extends AsyncNotifier<void> {
  AudioPlayerServiceNotifier() : super();

  static const int _appleMusicQueueLookBehind = 10;
  static const int _appleMusicQueueLookAhead = 50;

  AudioPlayer? _transitionPlayer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<ProcessingState>? _processingStateSubscription;
  StreamSubscription<NativeEqPlaybackSnapshot>? _nativeEqSnapshotSubscription;
  StreamSubscription<AppleMusicPlaybackSnapshot>? _appleMusicSnapshotSubscription;
  Timer? _playbackCrashHeartbeatTimer;
  ProcessingState? _lastLoggedProcessingState;
  int? _transitionSourceIndex;
  bool _isPreparingTransition = false;
  bool _isTransitioning = false;
  double _mainVolumeBeforeTransition = 1;
  List<int> _nativeEqSourceIndexes = const [];
  int? _lastNativeEqCompletionSerial;
  String? _lastRemotePlaybackReportKey;
  final Map<String, DateTime> _remotePlaybackStartedAt = {};
  _PlaybackBackend _activeBackend = _PlaybackBackend.none;
  int _playbackSessionId = 0;
  int _playbackOperationId = 0;
  bool _isReconfiguringEqualizerPlayback = false;
  int _equalizerPreviewGeneration = 0;
  Future<void> _equalizerPreviewTail = Future<void>.value();
  DateTime? _suppressCompletionUntil;
  List<String> _activeAppleMusicCatalogIds = const [];

  @override
  Future<void> build() async {
    final player = ref.read(audioPlayerProvider);
    _positionSubscription = player.positionStream.listen((position) {
      unawaited(_maybeStartSongTransition(position));
    });
    _installPlaybackCrashLogging(player);
    _installNativeEqSnapshotSync();
    _installAppleMusicSnapshotSync();
    _processingStateSubscription = player.processingStateStream.listen((
      processingState,
    ) {
      if (processingState == ProcessingState.completed) {
        if (_shouldSuppressCompletionAdvance()) {
          ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
                'Completion ignored during EQ reconfigure',
                data: _playbackCrashData(),
              );
          return;
        }
        unawaited(_advanceUnifiedQueueAfterCompletion());
      }
    });
    ref.listen<NowPlayingModel>(nowPlayingDetailsProvider, (previous, next) {
      final previousMetadata = previous?.currentMetadata;
      final nextMetadata = next.currentMetadata;
      final changedTrack = previousMetadata?.sourceIdentityKey != nextMetadata?.sourceIdentityKey;
      if (previous?.isPlaying == true && (!next.isPlaying || changedTrack)) {
        unawaited(_reportRemotePlaybackStopped(previousMetadata));
      }
      if (!next.isPlaying) {
        _lastRemotePlaybackReportKey = null;
        return;
      }
      final metadata = next.currentMetadata;
      if (metadata == null) {
        return;
      }
      final reportKey = '${metadata.sourceIdentityKey}:${next.currentIndex}:${next.nowPlayingType.name}';
      if (reportKey == _lastRemotePlaybackReportKey) {
        return;
      }
      _lastRemotePlaybackReportKey = reportKey;
      unawaited(_reportRemotePlaybackStart(metadata));
    });

    ref.onDispose(() {
      _playbackCrashHeartbeatTimer?.cancel();
      unawaited(_positionSubscription?.cancel());
      unawaited(_playerStateSubscription?.cancel());
      unawaited(_playbackEventSubscription?.cancel());
      unawaited(_processingStateSubscription?.cancel());
      unawaited(_nativeEqSnapshotSubscription?.cancel());
      unawaited(_appleMusicSnapshotSubscription?.cancel());
      unawaited(_transitionPlayer?.dispose());
    });
    await syncSongTransitionStyle();
  }



  void _installAppleMusicSnapshotSync() {
    _appleMusicSnapshotSubscription = ref
        .read(appleMusicPlaybackServiceProvider)
        .playbackSnapshots()
        .listen((snapshot) {
          if (!snapshot.isSupported ||
              _activeBackend != _PlaybackBackend.appleMusicSystem) {
            return;
          }
          final details = ref.read(nowPlayingDetailsProvider);
          if (!(details.currentMetadata?.isAppleMusicCatalogTrack ?? false)) {
            return;
          }
          final catalogId = snapshot.catalogId;
          if (catalogId != null) {
            final index = details.metadataList.indexWhere(
              (metadata) => metadata.appleMusicCatalogId == catalogId,
            );
            if (index != -1 && index != details.currentIndex) {
              ref.read(nowPlayingDetailsProvider.notifier).setCurrentIndex(index);
            }
          }
          if (details.isPlaying != snapshot.isPlaying) {
            ref
                .read(nowPlayingDetailsProvider.notifier)
                .setPlaybackState(snapshot.isPlaying);
          }
        });
  }

  void _installNativeEqSnapshotSync() {
    _nativeEqSnapshotSubscription = ref
        .read(nativeEqPlayerServiceProvider)
        .playbackSnapshots()
        .listen((snapshot) {
          if (!ref.read(nativeEqPlaybackActiveProvider) ||
              !snapshot.isSupported) {
            return;
          }
          final details = ref.read(nowPlayingDetailsProvider);
          if (details.metadataList.isEmpty ||
              details.currentMetadata?.isAppleMusicCatalogTrack == true) {
            return;
          }
          final completionSerial = snapshot.completionSerial;
          final lastCompletionSerial = _lastNativeEqCompletionSerial;
          if (lastCompletionSerial == null) {
            _lastNativeEqCompletionSerial = completionSerial;
          } else if (completionSerial != lastCompletionSerial &&
              snapshot.completedIndex >= 0) {
            if (_shouldSuppressCompletionAdvance()) {
              _lastNativeEqCompletionSerial = completionSerial;
              ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
                    'Native EQ completion ignored during EQ reconfigure',
                    data: _playbackCrashData(),
                  );
              return;
            }
            _lastNativeEqCompletionSerial = completionSerial;
            unawaited(_advanceNativeEqQueueAfterCompletion(snapshot));
            return;
          }

          if (!snapshot.isLoaded) {
            return;
          }

          final visibleIndex = _nativeEqVisibleIndexForPreparedIndex(
            snapshot.currentIndex,
          );
          if (visibleIndex != details.currentIndex &&
              visibleIndex >= 0 &&
              visibleIndex < details.metadataList.length) {
            ref
                .read(nowPlayingDetailsProvider.notifier)
                .setCurrentIndex(visibleIndex);
          }
          if (details.isPlaying != snapshot.isPlaying) {
            ref
                .read(nowPlayingDetailsProvider.notifier)
                .setPlaybackState(snapshot.isPlaying);
          }
        });
  }

  void _installPlaybackCrashLogging(AudioPlayer player) {
    final crashLogService = ref.read(crashLogServiceProvider);
    _playerStateSubscription = player.playerStateStream.listen(
      (playerState) {
        crashLogService.recordPlaybackBreadcrumb(
          'Player state changed',
          data: _playbackCrashData(
            extra: {
              'playerStatePlaying': playerState.playing,
              'playerStateProcessing': playerState.processingState.name,
            },
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        crashLogService.recordPlaybackError(
          'Player state stream failed',
          error: error,
          stackTrace: stackTrace,
          data: _playbackCrashData(),
        );
      },
    );
    _playbackEventSubscription = player.playbackEventStream.listen(
      (event) {
        if (event.processingState == _lastLoggedProcessingState) {
          return;
        }
        _lastLoggedProcessingState = event.processingState;
        crashLogService.recordPlaybackBreadcrumb(
          'Playback processing state changed',
          data: _playbackCrashData(
            extra: {
              'eventProcessingState': event.processingState.name,
              'eventCurrentIndex': event.currentIndex,
              'eventUpdatePositionSeconds': event.updatePosition.inSeconds,
              'eventBufferedPositionSeconds': event.bufferedPosition.inSeconds,
              'eventDurationSeconds': event.duration?.inSeconds,
            },
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        crashLogService.recordPlaybackError(
          'Playback event stream failed',
          error: error,
          stackTrace: stackTrace,
          data: _playbackCrashData(),
        );
      },
    );
    _playbackCrashHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _recordPlaybackCrashHeartbeat(),
    );
  }

  void _recordPlaybackCrashHeartbeat() {
    try {
      final player = ref.read(audioPlayerProvider);
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      if (!player.playing && nowPlayingDetails.currentMetadata == null) {
        return;
      }
      ref
          .read(crashLogServiceProvider)
          .recordPlaybackBreadcrumb(
            'Playback heartbeat',
            data: _playbackCrashData(),
            appendToCrashLog: false,
          );
    } catch (_) {
      // Crash logging must never be able to crash playback.
    }
  }

  Future<void> _reportRemotePlaybackStopped(MusicMetadata? metadata) async {
    final path = metadata?.filePath;
    if (metadata == null ||
        path == null ||
        path.isEmpty ||
        metadata.isAppleMusicCatalogTrack) {
      return;
    }
    try {
      if (metadata.isNavidromeTrack) {
        final connection = ref.read(navidromeConnectionProvider);
        if (connection != null && _shouldSubmitRemoteScrobble(metadata)) {
          await ref.read(navidromeServiceProvider).scrobble(connection, metadata);
        }
      } else if (metadata.isJellyfinTrack) {
        final connection = ref.read(jellyfinConnectionProvider);
        if (connection != null) {
          await ref
              .read(jellyfinServiceProvider)
              .reportPlaybackStopped(
                connection,
                metadata,
                position: await _currentPlaybackPosition(),
              );
        }
      }
    } catch (_) {
      // Remote listening history must never interrupt playback.
    }
  }

  Future<void> _reportRemotePlaybackStart(MusicMetadata metadata) async {
    final path = metadata.filePath;
    if (path == null || path.isEmpty || metadata.isAppleMusicCatalogTrack) {
      return;
    }
    final uri = Uri.tryParse(path);
    if (uri == null) {
      return;
    }
    try {
      if (metadata.isNavidromeTrack) {
        final connection = ref.read(navidromeConnectionProvider);
        if (connection != null) {
          _remotePlaybackStartedAt[metadata.sourceIdentityKey] = DateTime.now();
          await ref
              .read(navidromeServiceProvider)
              .reportNowPlaying(connection, metadata);
        }
      } else if (metadata.isJellyfinTrack) {
        final connection = ref.read(jellyfinConnectionProvider);
        if (connection != null) {
          _remotePlaybackStartedAt[metadata.sourceIdentityKey] = DateTime.now();
          await ref
              .read(jellyfinServiceProvider)
              .reportPlaybackStart(connection, metadata);
        }
      }
    } catch (_) {
      // Remote listening history must never interrupt playback.
    }
  }

  bool _shouldSubmitRemoteScrobble(MusicMetadata metadata) {
    final startedAt = _remotePlaybackStartedAt.remove(metadata.sourceIdentityKey);
    if (startedAt == null) {
      return false;
    }
    final listened = DateTime.now().difference(startedAt);
    final durationMs = metadata.trackDuration;
    final requiredListen = durationMs == null || durationMs <= 0
        ? const Duration(seconds: 30)
        : Duration(
            milliseconds: (durationMs / 2).clamp(30000, 240000).toInt(),
          );
    return listened >= requiredListen;
  }

  Future<Duration> _currentPlaybackPosition() async {
    if (ref.read(nativeEqPlaybackActiveProvider)) {
      return (await ref.read(nativeEqPlayerServiceProvider).snapshot()).position;
    }
    return ref.read(audioPlayerProvider).position;
  }

  Map<String, Object?> _playbackCrashData({
    Map<String, Object?> extra = const {},
  }) {
    final player = ref.read(audioPlayerProvider);
    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    final metadata = nowPlayingDetails.currentMetadata;
    final settings = ref.read(settingsPreferencesControllerProvider);
    return {
      'playing': player.playing,
      'processingState': player.processingState.name,
      'positionSeconds': player.position.inSeconds,
      'durationSeconds': player.duration?.inSeconds,
      'playerCurrentIndex': player.currentIndex,
      'nowPlayingIndex': nowPlayingDetails.currentIndex,
      'queueLength': nowPlayingDetails.metadataList.length,
      'nowPlayingType': nowPlayingDetails.nowPlayingType.name,
      'trackName': metadata?.trackName,
      'artist': metadata?.getTrackArtistNames,
      'albumName': metadata?.albumName,
      'filePath': metadata?.filePath,
      'isOnDevice': metadata?.isOnDevice,
      'isAppleMusic': metadata?.isAppleMusicCatalogTrack,
      'isNativeEqActive': ref.read(nativeEqPlaybackActiveProvider),
      'equalizerTitle': settings.equalizerDisplayTitle,
      'equalizerPreampDb': settings.activeEqualizerPreampDb,
      'equalizerRequested': !settings.activeEqualizerHasNeutralCurve,
      'transitionStyle': settings.songTransitionStyle.name,
      'crossfadeSeconds': settings.crossfadeDurationSeconds,
      'isPreparingTransition': _isPreparingTransition,
      'isTransitioning': _isTransitioning,
      'transitionSourceIndex': _transitionSourceIndex,
      'activeBackend': _activeBackend.name,
      'playbackSessionId': _playbackSessionId,
      'playbackOperationId': _playbackOperationId,
      'activeAppleMusicQueueSize': _activeAppleMusicCatalogIds.length,
      ...extra,
    };
  }

  int _nextPlaybackOperationId() => ++_playbackOperationId;

  void _setActiveBackend(_PlaybackBackend backend) {
    if (_activeBackend != backend) {
      _activeBackend = backend;
      _playbackSessionId++;
    }
  }

  bool _isLocalPlaybackBackend(_PlaybackBackend backend) {
    return backend == _PlaybackBackend.localDefaultPlayer ||
        backend == _PlaybackBackend.nativeEqPlayer;
  }

  bool _shouldSuppressCompletionAdvance() {
    final suppressUntil = _suppressCompletionUntil;
    return _isReconfiguringEqualizerPlayback ||
        (suppressUntil != null && DateTime.now().isBefore(suppressUntil));
  }

  void _suppressCompletionAdvanceFor(Duration duration) {
    _suppressCompletionUntil = DateTime.now().add(duration);
  }

  Future<void> reconfigureEqualizerPlayback() async {
    if (_isReconfiguringEqualizerPlayback) {
      return;
    }
    _isReconfiguringEqualizerPlayback = true;
    _suppressCompletionAdvanceFor(const Duration(seconds: 2));
    final startingDetails = ref.read(nowPlayingDetailsProvider);
    final startingIndex = startingDetails.currentIndex;
    final startingMetadata = startingDetails.currentMetadata;
    try {
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      final metadataList = nowPlayingDetails.metadataList;
      final currentMetadata = nowPlayingDetails.currentMetadata;
      if (metadataList.isEmpty || currentMetadata?.isAppleMusicCatalogTrack == true) {
        await _syncEqualizerPreset();
        return;
      }

      final settings = ref.read(settingsPreferencesControllerProvider);
    if (ref.read(nativeEqPlaybackActiveProvider)) {
      final snapshot = await ref.read(nativeEqPlayerServiceProvider).snapshot();
      final wasPlaying = snapshot.isPlaying;
      final position = snapshot.position;
      final index = _nativeEqVisibleIndexForPreparedIndex(snapshot.currentIndex);
      if (!settings.activeEqualizerHasNeutralCurve) {
        await ref.read(nativeEqPlayerServiceProvider).setBandGains(
              presetName: settings.activeCustomEqualizerPreset?.id ??
                  settings.equalizerPreset.name,
              displayName: settings.equalizerDisplayTitle,
              bandGainsDb: settings.activeEqualizerBandGainsDb,
              preampDb: settings.activeEqualizerPreampDb,
            );
        return;
      }

      await _stopNativeEqPlayback();
      await setAudioSource(
        nowPlayingType: nowPlayingDetails.nowPlayingType,
        musicMetadataList: metadataList,
        initialIndex: index,
        initialPosition: position,
      );
      await ref.read(audioPlayerProvider).seek(
            position,
            index: _defaultPlayerIndexForVisibleIndex(
              nowPlayingDetails,
              index,
            ),
          );
      if (wasPlaying) {
        await play();
      }
      return;
    }

    if (settings.activeEqualizerHasNeutralCurve) {
      await _syncEqualizerPreset();
      return;
    }

    final player = ref.read(audioPlayerProvider);
    final wasPlaying = player.playing || nowPlayingDetails.isPlaying;
    final position = player.position;
    final index = _isMixedSourceQueue(nowPlayingDetails)
        ? nowPlayingDetails.currentIndex
        : player.currentIndex ?? nowPlayingDetails.currentIndex;
    await setAudioSource(
      nowPlayingType: nowPlayingDetails.nowPlayingType,
      musicMetadataList: metadataList,
      initialIndex: index,
      initialPosition: position,
    );
    if (ref.read(nativeEqPlaybackActiveProvider)) {
      await ref.read(nativeEqPlayerServiceProvider).seekTo(position);
    } else {
      await ref.read(audioPlayerProvider).seek(
            position,
            index: _defaultPlayerIndexForVisibleIndex(
              nowPlayingDetails,
              index,
            ),
          );
    }
    if (wasPlaying) {
      await play();
    }
    } finally {
      _restoreEqualizerReconfigureIdentity(startingIndex, startingMetadata);
      _suppressCompletionAdvanceFor(const Duration(seconds: 2));
      _isReconfiguringEqualizerPlayback = false;
    }
  }

  void _restoreEqualizerReconfigureIdentity(
    int startingIndex,
    MusicMetadata? startingMetadata,
  ) {
    if (startingMetadata == null) {
      return;
    }
    final details = ref.read(nowPlayingDetailsProvider);
    if (details.metadataList.isEmpty ||
        (details.currentMetadata?.hasSameSourceIdentity(startingMetadata) ?? false)) {
      return;
    }
    final matchingIndex = details.metadataList.indexWhere(
      (metadata) => metadata.hasSameSourceIdentity(startingMetadata),
    );
    final restoredIndex = matchingIndex == -1 ? startingIndex : matchingIndex;
    if (restoredIndex >= 0 && restoredIndex < details.metadataList.length) {
      ref.read(nowPlayingDetailsProvider.notifier).setCurrentIndex(restoredIndex);
      ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
            'Restored EQ reconfigure track identity',
            data: _playbackCrashData(
              extra: {
                'startingIndex': startingIndex,
                'restoredIndex': restoredIndex,
                'startingTrack': startingMetadata.trackName,
              },
            ),
          );
    }
  }

  Future<void> syncSongTransitionStyle() async {
    final settings = ref.read(settingsPreferencesControllerProvider);
    await ref
        .read(appleMusicPlaybackServiceProvider)
        .setTransitionStyle(
          settings.songTransitionStyle,
          Duration(seconds: settings.crossfadeDurationSeconds),
        );
  }

  Future<void> play() async {
    final player = ref.read(audioPlayerProvider);
    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    final metadata = nowPlayingDetails.currentMetadata;
    if (metadata?.isAppleMusicCatalogTrack ?? false) {
      if (nowPlayingDetails.isPlaying) {
        return;
      }
      await _resumeAppleMusicCatalogTrack(
        metadata!,
        metadataList: nowPlayingDetails.metadataList,
        currentIndex: nowPlayingDetails.currentIndex,
        nowPlayingType: nowPlayingDetails.nowPlayingType,
      );
      return;
    }

    if (ref.read(nativeEqPlaybackActiveProvider)) {
      await ref.read(nativeEqPlayerServiceProvider).play();
      ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(true);
      return;
    }

    if (player.playing) {
      return;
    }
    ref
        .read(crashLogServiceProvider)
        .recordPlaybackBreadcrumb(
          'Local playback requested',
          data: _playbackCrashData(),
        );
    if (player.currentIndex == null && metadata != null) {
      await playSongFromMetadata(metadata);
      return;
    }
    await _syncEqualizerPreset();
    await player.play();
  }

  Future<void> pause() async {
    final metadata = ref.read(nowPlayingDetailsProvider).currentMetadata;
    if (metadata?.isAppleMusicCatalogTrack ?? false) {
      await ref.read(appleMusicPlaybackServiceProvider).pause();
      ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(false);
      return;
    }

    if (ref.read(nativeEqPlaybackActiveProvider)) {
      await ref.read(nativeEqPlayerServiceProvider).pause();
      ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(false);
      return;
    }

    if (ref.read(audioPlayerProvider).playing) {
      ref
          .read(crashLogServiceProvider)
          .recordPlaybackBreadcrumb(
            'Local playback pause requested',
            data: _playbackCrashData(),
          );
      await _cancelSongTransition();
      await ref.read(audioPlayerProvider).pause();
    }
  }

  Future<void> toggleShuffleMode() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(audioPlayerProvider)
          .setShuffleModeEnabled(
            !ref.read(audioPlayerProvider).shuffleModeEnabled,
          );
    });
  }

  Future<void> setShuffleMode(bool isShuffleModeEnabled) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(audioPlayerProvider)
          .setShuffleModeEnabled(isShuffleModeEnabled);
    });
  }

  Future<void> shuffleAllSongs() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final sourceSongs = ref.read(filteredAudioFilesProvider).requireValue;
      if (sourceSongs.isEmpty) {
        return;
      }
      final shuffledSongs = [...sourceSongs]..shuffle(Random());
      await setShuffleMode(true);
      await playMetadataListAtIndex(
        metadataList: shuffledSongs,
        index: 0,
      );

      await ref
          .read(settingsPreferencesControllerProvider.notifier)
          .setInitialRepeatMode();
    });
  }

  Future<void> setLoopMode(LoopMode loopMode) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(audioPlayerProvider).setLoopMode(loopMode);
    });
  }

  Future<void> stopPlaybackAndClearQueue() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(appleMusicPlaybackServiceProvider).pause();
      await _cancelSongTransition();
      await _stopNativeEqPlayback();
      await ref.read(audioPlayerProvider).stop();
      _activeAppleMusicCatalogIds = const [];
      _setActiveBackend(_PlaybackBackend.none);
      ref
          .read(nowPlayingDetailsProvider.notifier)
          .setNewMetadataList(
            nowPlayingType: NowPlayingType.songs,
            newMetadataList: const [],
            isPlaying: false,
          );
    });
  }

  Future<void> setAudioSource({
    NowPlayingType nowPlayingType = NowPlayingType.songs,
    required List<MusicMetadata> musicMetadataList,
    int initialIndex = 0,
    bool allowNativeEq = true,
    String operationReason = 'set_audio_source',
    Duration initialPosition = Duration.zero,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final operationId = _nextPlaybackOperationId();
      _suppressCompletionAdvanceFor(const Duration(seconds: 1));
      await _pauseAppleMusicPlaybackIfCurrent();
      await _cancelSongTransition();
      ref
          .read(crashLogServiceProvider)
          .recordPlaybackBreadcrumb(
            'Setting local audio source',
            data: {
              'requestedCount': musicMetadataList.length,
              'initialIndex': initialIndex,
              'nowPlayingType': nowPlayingType.name,
              'operationReason': operationReason,
              'operationId': operationId,
              'allowNativeEq': allowNativeEq,
              'initialPositionSeconds': initialPosition.inSeconds,
              'activeBackend': _activeBackend.name,
            },
          );
      final requestedMetadata = musicMetadataList.isEmpty
          ? null
          : musicMetadataList[initialIndex
                .clamp(0, musicMetadataList.length - 1)
                .toInt()];
      final didLoadNativeEq = allowNativeEq &&
          await _trySetNativeEqAudioSource(
            nowPlayingType: nowPlayingType,
            musicMetadataList: musicMetadataList,
            initialIndex: initialIndex,
            operationReason: operationReason,
          );
      if (didLoadNativeEq) {
        _setActiveBackend(_PlaybackBackend.nativeEqPlayer);
        return;
      }
      final containsAppleMusic = musicMetadataList.any(
        (metadata) => metadata.isAppleMusicCatalogTrack,
      );
      final localMetadataList = containsAppleMusic
          ? [
              if (requestedMetadata != null &&
                  !requestedMetadata.isAppleMusicCatalogTrack)
                requestedMetadata,
            ]
          : musicMetadataList
                .where((metadata) => !metadata.isAppleMusicCatalogTrack)
                .toList(growable: false);
      final List<AudioSource> songSourcePlaylist = [];
      final playableLocalMetadataList = <MusicMetadata>[];
      for (final musicMetadata in localMetadataList) {
        try {
          songSourcePlaylist.add(musicMetadata.toAudioSource());
          playableLocalMetadataList.add(musicMetadata);
        } catch (error, stackTrace) {
          ref
              .read(crashLogServiceProvider)
              .recordPlaybackError(
                'Audio source build failed',
                error: error,
                stackTrace: stackTrace,
                data: {
                  'trackName': musicMetadata.trackName,
                  'sourceIdentity': musicMetadata.sourceIdentityKey,
                  'sourceType': musicMetadata.sourceType.name,
                  'filePath': musicMetadata.filePath,
                },
              );
          if (musicMetadata.hasSameSourceIdentity(requestedMetadata ?? musicMetadata)) {
            rethrow;
          }
        }
      }

      if (songSourcePlaylist.isEmpty) {
        ref
            .read(crashLogServiceProvider)
            .recordPlaybackBreadcrumb(
              'Local audio source was empty',
              data: {
                'requestedCount': musicMetadataList.length,
                'localCount': playableLocalMetadataList.length,
                'containsAppleMusic': containsAppleMusic,
              },
            );
        await ref.read(audioPlayerProvider).stop();
        _setActiveBackend(_PlaybackBackend.none);
        ref
            .read(nowPlayingDetailsProvider.notifier)
            .setNewMetadataList(
              nowPlayingType: nowPlayingType,
              newMetadataList: const [],
            );
        return;
      }

      final matchingInitialIndex = requestedMetadata == null
          ? -1
          : playableLocalMetadataList.indexWhere(
              (metadata) => metadata.hasSameSourceIdentity(requestedMetadata),
            );
      final safeInitialIndex = matchingInitialIndex == -1
          ? 0
          : matchingInitialIndex
                .clamp(0, songSourcePlaylist.length - 1)
                .toInt();

      await _stopNativeEqPlayback();
      await ref
          .read(audioPlayerProvider)
          .setAudioSources(
            songSourcePlaylist,
            initialIndex: safeInitialIndex,
            initialPosition: initialPosition,
            shuffleOrder: DefaultShuffleOrder(),
          );
      ref
          .read(crashLogServiceProvider)
          .recordPlaybackBreadcrumb(
            'Local audio source loaded',
            data: {
              'localCount': playableLocalMetadataList.length,
              'safeInitialIndex': safeInitialIndex,
              'containsAppleMusic': containsAppleMusic,
              'requestedTrack': requestedMetadata?.trackName,
              'requestedPath': requestedMetadata?.filePath,
              'operationReason': operationReason,
              'operationId': operationId,
              'allowNativeEq': allowNativeEq,
              'initialPositionSeconds': initialPosition.inSeconds,
            },
          );

      _setActiveBackend(_PlaybackBackend.localDefaultPlayer);
      if (allowNativeEq) {
        await _syncEqualizerPreset();
      }

      ref
          .read(nowPlayingDetailsProvider.notifier)
          .setNewMetadataList(
            nowPlayingType: nowPlayingType,
            newMetadataList: containsAppleMusic
                ? musicMetadataList
                : playableLocalMetadataList,
            currentIndex: containsAppleMusic
                ? initialIndex.clamp(0, musicMetadataList.length - 1).toInt()
                : safeInitialIndex,
          );
    });
  }

  Future<void> nextSong() async {
    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    final nextIndex = nowPlayingDetails.currentIndex + 1;
    if (_shouldUseUnifiedQueueStep(nowPlayingDetails, nextIndex)) {
      await _playUnifiedQueueIndex(nextIndex);
      return;
    }

    if (nowPlayingDetails.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
      if (nextIndex >= nowPlayingDetails.metadataList.length) {
        return;
      }
      final metadata = nowPlayingDetails.metadataList[nextIndex];
      if (!metadata.isAppleMusicCatalogTrack) {
        await _playUnifiedQueueIndex(nextIndex);
        return;
      }

      final targetCatalogId = metadata.appleMusicCatalogId;
      final canReuseQueue = targetCatalogId != null &&
          _activeAppleMusicCatalogIds.contains(targetCatalogId);
      final didSkip = canReuseQueue &&
          await ref
              .read(appleMusicPlaybackServiceProvider)
              .skipToNextInCurrentQueue();
      if (didSkip) {
        _setActiveBackend(_PlaybackBackend.appleMusicSystem);
        ref.read(nowPlayingDetailsProvider.notifier).setCurrentIndex(nextIndex);
        ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(true);
        unawaited(_refreshAppleMusicLyrics(metadata));
        return;
      }

      ref
          .read(crashLogServiceProvider)
          .recordPlaybackBreadcrumb(
            'Apple Music next fell back to queue rebuild',
            data: _playbackCrashData(extra: {'targetIndex': nextIndex}),
          );
      await _playAppleMusicCatalogTrack(
        metadata,
        metadataList: nowPlayingDetails.metadataList,
        currentIndex: nextIndex,
        nowPlayingType: nowPlayingDetails.nowPlayingType,
      );
      return;
    }
    if (ref.read(nativeEqPlaybackActiveProvider)) {
      final didSkip = await ref.read(nativeEqPlayerServiceProvider).next();
      if (didSkip) {
        final snapshot = await ref.read(nativeEqPlayerServiceProvider).snapshot();
        ref
            .read(nowPlayingDetailsProvider.notifier)
            .setCurrentIndex(
              _nativeEqVisibleIndexForPreparedIndex(snapshot.currentIndex),
            );
        ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(true);
        return;
      }
      if (nextIndex < nowPlayingDetails.metadataList.length) {
        await _playUnifiedQueueIndex(nextIndex);
      }
      return;
    }
    await _cancelSongTransition();
    await ref.read(audioPlayerProvider).seekToNext();
  }

  Future<void> seekBackwards() async {
    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    final previousIndex = nowPlayingDetails.currentIndex - 1;
    if (_shouldUseUnifiedQueueStep(nowPlayingDetails, previousIndex)) {
      await _playUnifiedQueueIndex(previousIndex);
      return;
    }

    if (nowPlayingDetails.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
      final snapshot = await ref
          .read(appleMusicPlaybackServiceProvider)
          .playbackSnapshot();
      if (snapshot.position.inSeconds > 3) {
        final didRestart = await ref
            .read(appleMusicPlaybackServiceProvider)
            .restartCurrentItem();
        if (didRestart) {
          ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(true);
          return;
        }
        final currentMetadata = nowPlayingDetails.currentMetadata;
        if (currentMetadata != null) {
          ref
              .read(crashLogServiceProvider)
              .recordPlaybackBreadcrumb(
                'Apple Music restart fell back to queue rebuild',
                data: _playbackCrashData(
                  extra: {'targetIndex': nowPlayingDetails.currentIndex},
                ),
              );
          await _playAppleMusicCatalogTrack(
            currentMetadata,
            metadataList: nowPlayingDetails.metadataList,
            currentIndex: nowPlayingDetails.currentIndex,
            nowPlayingType: nowPlayingDetails.nowPlayingType,
          );
        }
        return;
      }

      if (previousIndex < 0) {
        final didRestart = await ref
            .read(appleMusicPlaybackServiceProvider)
            .restartCurrentItem();
        if (didRestart) {
          ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(true);
        }
        return;
      }
      final metadata = nowPlayingDetails.metadataList[previousIndex];
      if (!metadata.isAppleMusicCatalogTrack) {
        await _playUnifiedQueueIndex(previousIndex);
        return;
      }

      final targetCatalogId = metadata.appleMusicCatalogId;
      final canReuseQueue = targetCatalogId != null &&
          _activeAppleMusicCatalogIds.contains(targetCatalogId);
      final didSkip = canReuseQueue &&
          await ref
              .read(appleMusicPlaybackServiceProvider)
              .skipToPreviousInCurrentQueue();
      if (didSkip) {
        _setActiveBackend(_PlaybackBackend.appleMusicSystem);
        ref
            .read(nowPlayingDetailsProvider.notifier)
            .setCurrentIndex(previousIndex);
        ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(true);
        unawaited(_refreshAppleMusicLyrics(metadata));
        return;
      }

      ref
          .read(crashLogServiceProvider)
          .recordPlaybackBreadcrumb(
            'Apple Music previous fell back to queue rebuild',
            data: _playbackCrashData(extra: {'targetIndex': previousIndex}),
          );
      await _playAppleMusicCatalogTrack(
        metadata,
        metadataList: nowPlayingDetails.metadataList,
        currentIndex: previousIndex,
        nowPlayingType: nowPlayingDetails.nowPlayingType,
      );
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (ref.read(nativeEqPlaybackActiveProvider)) {
        final snapshot = await ref.read(nativeEqPlayerServiceProvider).snapshot();
        if (snapshot.position.inSeconds > 3 || previousIndex < 0) {
          await ref.read(nativeEqPlayerServiceProvider).seekTo(Duration.zero);
          ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(true);
          return;
        }
        await _playUnifiedQueueIndex(previousIndex);
        return;
      }
      if (ref.read(audioPlayerProvider).position.inSeconds > 3) {
        await _cancelSongTransition();
        await ref.read(audioPlayerProvider).seek(Duration.zero);
      } else {
        await _cancelSongTransition();
        await ref.read(audioPlayerProvider).seekToPrevious();
      }
    });
  }

  Future<void> playAlbum({
    required AlbumModel albumDetail,
    required int songIndex,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (albumDetail.albumSongs.isEmpty ||
          songIndex >= albumDetail.albumSongs.length) {
        return;
      }

      final didStart = await playMetadataListAtIndex(
        metadataList: albumDetail.albumSongs,
        index: songIndex,
        nowPlayingType: NowPlayingType.album,
      );
      if (didStart) {
        await setShuffleMode(false);
      }
    });
  }

  Future<void> playPlaylist({
    required PlaylistModel playlistDetail,
    required int songIndex,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (playlistDetail.songs.isEmpty ||
          songIndex >= playlistDetail.songs.length) {
        return;
      }

      final didStart = await playMetadataListAtIndex(
        metadataList: playlistDetail.songs,
        index: songIndex,
        nowPlayingType: NowPlayingType.playlist,
      );
      if (didStart) {
        await setShuffleMode(false);
      }
    });
  }

  Future<void> playSongAtIndex(int index) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      if (index >= 0 && index < nowPlayingDetails.metadataList.length) {
        final metadata = nowPlayingDetails.metadataList[index];
        if (metadata.isAppleMusicCatalogTrack) {
          await _playAppleMusicCatalogTrack(
            metadata,
            metadataList: nowPlayingDetails.metadataList,
            currentIndex: index,
            nowPlayingType: nowPlayingDetails.nowPlayingType,
          );
          return;
        }
      }

      if (_shouldUseUnifiedQueueStep(nowPlayingDetails, index)) {
        await _playUnifiedQueueIndex(index);
        return;
      }

      if (ref.read(nativeEqPlaybackActiveProvider)) {
        if (nowPlayingDetails.currentIndex == index) {
          await ref.read(nativeEqPlayerServiceProvider).play();
        } else {
          final preparedIndex = _nativeEqPreparedIndexForVisibleIndex(index);
          if (preparedIndex == -1) {
            await _playUnifiedQueueIndex(index);
            return;
          }
          await ref
              .read(nativeEqPlayerServiceProvider)
              .seekToIndex(preparedIndex, position: Duration.zero);
          await ref.read(nativeEqPlayerServiceProvider).play();
          ref.read(nowPlayingDetailsProvider.notifier).setCurrentIndex(index);
        }
        ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(true);
        return;
      }

      //In case the same song is already playing
      if (nowPlayingDetails.currentIndex == index) {
        await play();
        return;
      } else {
        await _cancelSongTransition();
        await ref.read(audioPlayerProvider).seek(Duration.zero, index: index);
        await play();
      }
    });
  }

  Future<void> playSongFromOriginalList(int originalIndex) async {
    final originalList = ref.read(filteredAudioFilesProvider).requireValue;
    final metadata = originalList.cast<MusicMetadata?>().firstWhere(
          (element) => element?.originalSongIndex == originalIndex,
          orElse: () => null,
        );
    if (metadata != null) {
      await playSongFromMetadata(metadata);
    }
  }

  Future<void> playSongFromMetadata(MusicMetadata selectedMetadata) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final player = ref.read(audioPlayerProvider);
      var nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      final externalIndex = nowPlayingDetails.metadataList.indexWhere(
        (element) => element.hasSameSourceIdentity(selectedMetadata),
      );
      if (externalIndex != -1) {
        await _playUnifiedQueueIndex(externalIndex);
        return;
      }

      final hasLoadedSources = player.currentIndex != null;
      final shouldUseOriginalList =
          !hasLoadedSources ||
          nowPlayingDetails.nowPlayingType != NowPlayingType.songs ||
          nowPlayingDetails.metadataList.isEmpty ||
          !nowPlayingDetails.metadataList.any(
            (element) => element.hasSameSourceIdentity(selectedMetadata),
          );

      if (shouldUseOriginalList) {
        final originalList = ref.read(filteredAudioFilesProvider).requireValue;
        final initialIndex = originalList.indexWhere(
          (element) => element.hasSameSourceIdentity(selectedMetadata),
        );
        if (initialIndex == -1) {
          return;
        }
        await setAudioSource(
          musicMetadataList: originalList,
          initialIndex: initialIndex,
        );
        nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      }

      if (nowPlayingDetails.currentMetadata?.hasSameSourceIdentity(selectedMetadata) ?? false) {
        await _syncEqualizerPreset();
        await player.play();
        return;
      }

      final int index = nowPlayingDetails.metadataList.indexWhere(
        (element) => element.hasSameSourceIdentity(selectedMetadata),
      );
      if (index == -1) {
        return;
      }

      await _playUnifiedQueueIndex(index);
    });
  }

  bool _isMixedSourceQueue(NowPlayingModel details) {
    if (details.metadataList.length < 2) {
      return false;
    }
    return details.metadataList.map((metadata) => metadata.sourceType).toSet().length > 1;
  }

  bool _shouldUseUnifiedQueueStep(NowPlayingModel details, int targetIndex) {
    return targetIndex >= 0 &&
        targetIndex < details.metadataList.length &&
        _isMixedSourceQueue(details);
  }

  Future<void> _advanceUnifiedQueueAfterCompletion() async {
    final details = ref.read(nowPlayingDetailsProvider);
    if (!_isMixedSourceQueue(details)) {
      return;
    }
    final nextIndex = _nextCompletionIndex(details);
    if (nextIndex != null) {
      await _playUnifiedQueueIndex(nextIndex);
    }
  }

  Future<void> _advanceNativeEqQueueAfterCompletion(
    NativeEqPlaybackSnapshot snapshot,
  ) async {
    final details = ref.read(nowPlayingDetailsProvider);
    if (details.metadataList.isEmpty) {
      return;
    }
    final completedVisibleIndex = _nativeEqVisibleIndexForPreparedIndex(
      snapshot.completedIndex,
    );
    if (completedVisibleIndex >= 0 &&
        completedVisibleIndex < details.metadataList.length &&
        completedVisibleIndex != details.currentIndex) {
      ref
          .read(nowPlayingDetailsProvider.notifier)
          .setCurrentIndex(completedVisibleIndex);
    }
    final updatedDetails = ref.read(nowPlayingDetailsProvider);
    final nextIndex = _nextCompletionIndex(updatedDetails);
    if (nextIndex == null) {
      ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(false);
      return;
    }
    await _playUnifiedQueueIndex(nextIndex);
  }

  int? _nextCompletionIndex(NowPlayingModel details) {
    if (details.metadataList.isEmpty) {
      return null;
    }
    final nextIndex = details.currentIndex + 1;
    if (nextIndex < details.metadataList.length) {
      return nextIndex;
    }
    if (details.loopMode == LoopMode.all && details.metadataList.length > 1) {
      return 0;
    }
    return null;
  }

  Future<bool> _playUnifiedQueueIndex(int index) async {
    final details = ref.read(nowPlayingDetailsProvider);
    if (index < 0 || index >= details.metadataList.length) {
      return false;
    }

    final metadata = details.metadataList[index];
    ref
        .read(crashLogServiceProvider)
        .recordPlaybackBreadcrumb(
          'Unified mixed-source queue step',
          data: _playbackCrashData(
            extra: {
              'targetIndex': index,
              'targetTrack': metadata.trackName,
              'targetPath': metadata.filePath,
              'targetIsAppleMusic': metadata.isAppleMusicCatalogTrack,
            },
          ),
        );

    if (metadata.isAppleMusicCatalogTrack) {
      return _playAppleMusicCatalogTrack(
        metadata,
        metadataList: details.metadataList,
        currentIndex: index,
        nowPlayingType: details.nowPlayingType,
      );
    }

    await setAudioSource(
      nowPlayingType: details.nowPlayingType,
      musicMetadataList: details.metadataList,
      initialIndex: index,
      allowNativeEq: true,
      operationReason: _isLocalPlaybackBackend(_activeBackend)
          ? 'mixed_source_same_backend_step'
          : 'mixed_source_backend_switch',
    );
    await play();
    return true;
  }

  Future<bool> playMetadataListAtIndex({
    required List<MusicMetadata> metadataList,
    required int index,
    NowPlayingType nowPlayingType = NowPlayingType.songs,
  }) async {
    if (index < 0 || index >= metadataList.length) {
      return false;
    }

    final selectedMetadata = metadataList[index];
    if (selectedMetadata.isAppleMusicCatalogTrack) {
      return _playAppleMusicCatalogTrack(
        selectedMetadata,
        metadataList: metadataList,
        currentIndex: index,
        nowPlayingType: nowPlayingType,
      );
    }

    await setAudioSource(
      nowPlayingType: nowPlayingType,
      musicMetadataList: metadataList,
      initialIndex: index,
    );
    await play();
    return true;
  }

  Future<bool> playAppleMusicMetadata(
    MusicMetadata metadata, {
    List<MusicMetadata>? metadataList,
    int currentIndex = 0,
  }) async {
    var didStart = false;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      didStart = await _playAppleMusicCatalogTrack(
        metadata,
        metadataList: metadataList ?? [metadata],
        currentIndex: currentIndex,
      );
    });
    return didStart;
  }

  Future<bool> _resumeAppleMusicCatalogTrack(
    MusicMetadata metadata, {
    List<MusicMetadata>? metadataList,
    int currentIndex = 0,
    NowPlayingType nowPlayingType = NowPlayingType.songs,
  }) async {
    final didResume = await ref
        .read(appleMusicPlaybackServiceProvider)
        .resume();
    if (didResume) {
      ref
          .read(nowPlayingDetailsProvider.notifier)
          .setNewMetadataList(
            nowPlayingType: nowPlayingType,
            newMetadataList: metadataList ?? [metadata],
            currentIndex: currentIndex,
            isPlaying: true,
          );
      return true;
    }

    return _playAppleMusicCatalogTrack(
      metadata,
      metadataList: metadataList,
      currentIndex: currentIndex,
      nowPlayingType: nowPlayingType,
    );
  }

  Future<bool> _playAppleMusicCatalogTrack(
    MusicMetadata metadata, {
    List<MusicMetadata>? metadataList,
    int currentIndex = 0,
    NowPlayingType nowPlayingType = NowPlayingType.songs,
  }) async {
    final catalogId = metadata.appleMusicCatalogId;
    if (catalogId == null) {
      return false;
    }

    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    final previousMetadata = nowPlayingDetails.currentMetadata;
    final isSameAppleMusicTrack =
        previousMetadata?.appleMusicCatalogId == catalogId;
    if (isSameAppleMusicTrack) {
      ref
          .read(crashLogServiceProvider)
          .recordPlaybackBreadcrumb(
            'Apple Music same track selected',
            data: _playbackCrashData(
              extra: {
                'targetCatalogId': catalogId,
                'targetTrackName': metadata.trackName,
                'wasPlaying': nowPlayingDetails.isPlaying,
              },
            ),
          );
      if (nowPlayingDetails.isPlaying) {
        return true;
      }
      final didResume = await ref
          .read(appleMusicPlaybackServiceProvider)
          .resume();
      if (didResume) {
        _setActiveBackend(_PlaybackBackend.appleMusicSystem);
        ref
            .read(nowPlayingDetailsProvider.notifier)
            .setNewMetadataList(
              nowPlayingType: nowPlayingType,
              newMetadataList: metadataList ?? nowPlayingDetails.metadataList,
              currentIndex: currentIndex,
              isPlaying: true,
            );
        return true;
      }
    }

    final localPlayer = ref.read(audioPlayerProvider);
    await _cancelSongTransition();
    await _stopNativeEqPlayback();
    if (localPlayer.playing) {
      await localPlayer.pause();
    }
    if (localPlayer.currentIndex != null ||
        localPlayer.processingState != ProcessingState.idle) {
      await localPlayer.stop();
    }
    ref
        .read(crashLogServiceProvider)
        .recordPlaybackBreadcrumb(
          'Apple Music manual selection requested',
          data: _playbackCrashData(
            extra: {
              'targetCatalogId': catalogId,
              'targetTrackName': metadata.trackName,
              'wasAppleMusicPlaying':
                  previousMetadata?.isAppleMusicCatalogTrack ?? false,
              'wasLocalPlayerPlaying': localPlayer.playing,
            },
          ),
        );

    final requestedPlaybackList = metadataList ?? [metadata];
    final containsMixedSources = requestedPlaybackList.any(
          (entry) => entry.isAppleMusicCatalogTrack,
        ) &&
        requestedPlaybackList.any((entry) => !entry.isAppleMusicCatalogTrack);
    final queuePlaybackList = containsMixedSources
        ? requestedPlaybackList
        : _boundedAppleMusicPlaybackList(
            playbackList: requestedPlaybackList,
            currentIndex: currentIndex,
          );
    final catalogIds = queuePlaybackList
        .map((entry) => entry.appleMusicCatalogId)
        .whereType<String>()
        .toList(growable: false);
    final settings = ref.read(settingsPreferencesControllerProvider);
    final operationId = _nextPlaybackOperationId();
    final startedAt = DateTime.now();
    final wasAppleBackend = _activeBackend == _PlaybackBackend.appleMusicSystem;
    final wasKnownQueue = catalogIds.isNotEmpty &&
        _activeAppleMusicCatalogIds.isNotEmpty &&
        catalogIds.every((id) => _activeAppleMusicCatalogIds.contains(id));
    final didStart = await ref
        .read(appleMusicPlaybackServiceProvider)
        .playCatalogQueue(
          catalogIds: catalogIds.isEmpty ? [catalogId] : catalogIds,
          startCatalogId: catalogId,
          transitionStyle: settings.songTransitionStyle,
          transitionDuration: Duration(
            seconds: settings.crossfadeDurationSeconds,
          ),
        );
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    ref
        .read(crashLogServiceProvider)
        .recordPlaybackBreadcrumb(
          'Apple Music catalog queue selection completed',
          data: _playbackCrashData(
            extra: {
              'targetCatalogId': catalogId,
              'targetTrackName': metadata.trackName,
              'didStart': didStart,
              'elapsedMs': elapsedMs,
              'queueSize': catalogIds.isEmpty ? 1 : catalogIds.length,
              'operationId': operationId,
              'wasAppleBackend': wasAppleBackend,
              'wasKnownQueue': wasKnownQueue,
              'selectionMode': wasAppleBackend && wasKnownQueue
                  ? 'apple_music_rebuild_existing_queue'
                  : 'apple_music_rebuild_bounded_queue',
            },
          ),
        );
    if (didStart) {
      _activeAppleMusicCatalogIds = catalogIds.isEmpty
          ? [catalogId]
          : catalogIds;
      _setActiveBackend(_PlaybackBackend.appleMusicSystem);
    }
    ref
        .read(nowPlayingDetailsProvider.notifier)
        .setNewMetadataList(
          nowPlayingType: nowPlayingType,
          newMetadataList: requestedPlaybackList,
          currentIndex: currentIndex.clamp(
            0,
            requestedPlaybackList.length - 1,
          ).toInt(),
          isPlaying: didStart,
        );
    if (didStart) {
      unawaited(_refreshAppleMusicLyrics(metadata));
    }
    return didStart;
  }

  List<MusicMetadata> _boundedAppleMusicPlaybackList({
    required List<MusicMetadata> playbackList,
    required int currentIndex,
  }) {
    if (playbackList.length <=
        _appleMusicQueueLookBehind + _appleMusicQueueLookAhead + 1) {
      return playbackList;
    }
    if (currentIndex < 0 || currentIndex >= playbackList.length) {
      return playbackList;
    }

    final start = (currentIndex - _appleMusicQueueLookBehind)
        .clamp(0, playbackList.length - 1)
        .toInt();
    final end = (currentIndex + _appleMusicQueueLookAhead + 1)
        .clamp(start + 1, playbackList.length)
        .toInt();
    return playbackList.sublist(start, end);
  }



  Future<bool> _trySetNativeEqAudioSource({
    required NowPlayingType nowPlayingType,
    required List<MusicMetadata> musicMetadataList,
    required int initialIndex,
    List<double>? previewBandGainsDb,
    double? previewPreampDb,
    String operationReason = 'set_audio_source',
  }) async {
    final settings = ref.read(settingsPreferencesControllerProvider);
    final bandGainsDb = previewBandGainsDb ?? settings.activeEqualizerBandGainsDb;
    final preampDb = previewPreampDb ?? settings.activeEqualizerPreampDb;
    final hasNeutralCurve = bandGainsDb.every((gain) => gain == 0);
    if (hasNeutralCurve || musicMetadataList.isEmpty) {
      ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
            'Native EQ bypassed',
            data: _playbackCrashData(
              extra: {
                'reason': hasNeutralCurve ? 'neutral_curve' : 'empty_queue',
                'operationReason': operationReason,
              },
            ),
          );
      await _stopNativeEqPlayback();
      return false;
    }
    final safeInitialIndex = initialIndex
        .clamp(0, musicMetadataList.length - 1)
        .toInt();
    final selectedMetadata = musicMetadataList[safeInitialIndex];
    if (!ref.read(nativeEqPlayerServiceProvider).isSupported ||
        selectedMetadata.isAppleMusicCatalogTrack) {
      ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
            'Native EQ bypassed',
            data: _playbackCrashData(
              extra: {
                'reason': selectedMetadata.isAppleMusicCatalogTrack
                    ? 'apple_music_system_playback'
                    : 'unsupported_platform',
                'selectedSourceType': selectedMetadata.sourceType.name,
                'selectedTrack': selectedMetadata.trackName,
                'operationReason': operationReason,
              },
            ),
          );
      await _stopNativeEqPlayback();
      return false;
    }

    ref
        .read(crashLogServiceProvider)
        .recordPlaybackBreadcrumb(
          'Preparing native EQ playback',
          data: _playbackCrashData(
            extra: {
              'requestedCount': musicMetadataList.length,
              'initialIndex': initialIndex,
              'preset': settings.activeCustomEqualizerPreset?.id ??
                  settings.equalizerPreset.name,
              'presetTitle': settings.equalizerDisplayTitle,
              'operationReason': operationReason,
            },
          ),
        );

    final preparedQueue = await ref
        .read(nativeEqPlayerServiceProvider)
        .prepareQueue(
          metadataList: musicMetadataList,
          startIndex: safeInitialIndex,
        );
    if (preparedQueue == null) {
      ref
          .read(crashLogServiceProvider)
          .recordPlaybackBreadcrumb(
            'Native EQ preparation failed; using default player',
            data: _playbackCrashData(
              extra: {
                'reason': 'prepare_queue_failed',
                'selectedSourceType': selectedMetadata.sourceType.name,
                'selectedTrack': selectedMetadata.trackName,
                'operationReason': operationReason,
              },
            ),
          );
      await _stopNativeEqPlayback();
      return false;
    }

    await _pauseAppleMusicPlaybackIfCurrent();
    await ref.read(audioPlayerProvider).stop();
    final didLoad = await ref
        .read(nativeEqPlayerServiceProvider)
        .loadQueue(
          queue: preparedQueue,
          bandGainsDb: bandGainsDb,
          preampDb: preampDb,
        );
    if (!didLoad) {
      ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
            'Native EQ load failed; using default player',
            data: _playbackCrashData(
              extra: {
                'reason': 'native_load_failed',
                'selectedSourceType': selectedMetadata.sourceType.name,
                'selectedTrack': selectedMetadata.trackName,
                'operationReason': operationReason,
              },
            ),
          );
      await _stopNativeEqPlayback();
      return false;
    }

    _nativeEqSourceIndexes = preparedQueue.sourceIndexes;
    final snapshot = await ref.read(nativeEqPlayerServiceProvider).snapshot();
    _lastNativeEqCompletionSerial = snapshot.completionSerial;
    ref.read(nativeEqPlaybackActiveProvider.notifier).state = true;
    ref
        .read(nowPlayingDetailsProvider.notifier)
        .setNewMetadataList(
          nowPlayingType: nowPlayingType,
          newMetadataList: musicMetadataList,
          currentIndex: safeInitialIndex,
          isPlaying: false,
        );
    if (previewBandGainsDb == null) {
      await _syncEqualizerPreset();
    }
    return true;
  }

  int _defaultPlayerIndexForVisibleIndex(
    NowPlayingModel details,
    int visibleIndex,
  ) {
    if (!_isMixedSourceQueue(details)) {
      return visibleIndex;
    }
    final containsAppleMusic = details.metadataList.any(
      (metadata) => metadata.isAppleMusicCatalogTrack,
    );
    return containsAppleMusic ? 0 : visibleIndex;
  }

  int _nativeEqVisibleIndexForPreparedIndex(int preparedIndex) {
    if (preparedIndex >= 0 && preparedIndex < _nativeEqSourceIndexes.length) {
      return _nativeEqSourceIndexes[preparedIndex];
    }
    return preparedIndex;
  }

  int _nativeEqPreparedIndexForVisibleIndex(int visibleIndex) {
    if (_nativeEqSourceIndexes.isEmpty) {
      return visibleIndex;
    }
    return _nativeEqSourceIndexes.indexOf(visibleIndex);
  }

  Future<void> _stopNativeEqPlayback() async {
    if (!ref.read(nativeEqPlaybackActiveProvider)) {
      return;
    }
    await ref.read(nativeEqPlayerServiceProvider).stop();
    _nativeEqSourceIndexes = const [];
    _lastNativeEqCompletionSerial = null;
    ref.read(nativeEqPlaybackActiveProvider.notifier).state = false;
  }

  Future<void> _refreshAppleMusicLyrics(MusicMetadata metadata) async {
    if (metadata.originalSongIndex < 0 ||
        _hasSyncedLyricTiming(metadata.lyrics)) {
      return;
    }

    try {
      final lyrics = await ref
          .read(lyricsLookupServiceProvider)
          .findBestFor(metadata);
      if (lyrics == null || lyrics.trim().isEmpty) {
        return;
      }
      final enrichedMetadata = metadata.copyWith(lyrics: lyrics);
      await ref
          .read(nowPlayingDetailsProvider.notifier)
          .updateMetadata(enrichedMetadata);
    } catch (_) {
      // Lyrics are best-effort metadata; playback should never depend on them.
    }
  }

  Future<void> _pauseAppleMusicPlaybackIfCurrent() async {
    final isAppleMusicCurrent = ref
            .read(nowPlayingDetailsProvider)
            .currentMetadata
            ?.isAppleMusicCatalogTrack ??
        false;
    if (!isAppleMusicCurrent &&
        _activeBackend != _PlaybackBackend.appleMusicSystem) {
      return;
    }
    await ref.read(appleMusicPlaybackServiceProvider).pause();
    if (isAppleMusicCurrent) {
      ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(false);
    }
    _activeAppleMusicCatalogIds = const [];
    if (_activeBackend == _PlaybackBackend.appleMusicSystem) {
      _setActiveBackend(_PlaybackBackend.none);
    }
  }

  Future<void> _maybeStartSongTransition(Duration position) async {
    if (_isPreparingTransition || _isTransitioning) {
      return;
    }

    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    final currentMetadata = nowPlayingDetails.currentMetadata;
    if (currentMetadata == null ||
        currentMetadata.isAppleMusicCatalogTrack ||
        _isMixedSourceQueue(nowPlayingDetails) ||
        !nowPlayingDetails.isPlaying ||
        nowPlayingDetails.metadataList.isEmpty) {
      return;
    }

    final settings = ref.read(settingsPreferencesControllerProvider);
    final style = settings.songTransitionStyle;
    if (style == SongTransitionStyle.off) {
      return;
    }

    final player = ref.read(audioPlayerProvider);
    final duration = player.duration;
    final currentIndex = _isMixedSourceQueue(nowPlayingDetails)
        ? nowPlayingDetails.currentIndex
        : player.currentIndex ?? nowPlayingDetails.currentIndex;
    if (!player.playing ||
        player.shuffleModeEnabled ||
        nowPlayingDetails.loopMode == LoopMode.one ||
        duration == null ||
        duration <= const Duration(seconds: 4) ||
        currentIndex < 0 ||
        currentIndex >= nowPlayingDetails.metadataList.length) {
      return;
    }

    final nextIndex = _nextTransitionIndex(nowPlayingDetails, currentIndex);
    if (nextIndex == null || _transitionSourceIndex == currentIndex) {
      return;
    }

    final nextMetadata = nowPlayingDetails.metadataList[nextIndex];
    if (nextMetadata.isAppleMusicCatalogTrack) {
      return;
    }

    final analysisService = ref.read(songTransitionAnalysisServiceProvider);
    final currentProfile = analysisService.cachedProfileFor(currentMetadata);
    final nextProfile = analysisService.cachedProfileFor(nextMetadata);

    final transitionDuration = _safeTransitionDuration(
      duration,
      style.transitionDuration(
        nowPlayingType: nowPlayingDetails.nowPlayingType,
        currentMetadata: currentMetadata,
        crossfadeDurationSeconds: settings.crossfadeDurationSeconds,
        nextMetadata: nextMetadata,
        currentProfile: currentProfile,
        nextProfile: nextProfile,
      ),
    );
    if (transitionDuration == Duration.zero) {
      return;
    }

    final startPosition = style == SongTransitionStyle.autoMix
        ? autoMixStartPosition(
            duration: duration,
            transitionDuration: transitionDuration,
            profile: currentProfile,
          )
        : duration - transitionDuration;
    if (position < startPosition) {
      return;
    }

    _transitionSourceIndex = currentIndex;
    ref
        .read(crashLogServiceProvider)
        .recordPlaybackBreadcrumb(
          'Starting local song transition',
          data: _playbackCrashData(
            extra: {
              'nextIndex': nextIndex,
              'nextTrackName': nextMetadata.trackName,
              'transitionDurationMs': transitionDuration.inMilliseconds,
              'transitionStartSeconds': startPosition.inSeconds,
            },
          ),
        );
    await _performLocalSongTransition(
      nextIndex: nextIndex,
      nextMetadata: nextMetadata,
      transitionDuration: transitionDuration,
    );
  }

  int? _nextTransitionIndex(
    NowPlayingModel nowPlayingDetails,
    int currentIndex,
  ) {
    final nextIndex = currentIndex + 1;
    if (nextIndex < nowPlayingDetails.metadataList.length) {
      return nextIndex;
    }
    if (nowPlayingDetails.loopMode == LoopMode.all &&
        nowPlayingDetails.metadataList.length > 1) {
      return 0;
    }
    return null;
  }

  Duration _safeTransitionDuration(Duration duration, Duration transition) {
    if (transition <= Duration.zero) {
      return Duration.zero;
    }
    final maxTransitionMs = ((duration.inMilliseconds - 3000) / 2).floor();
    if (maxTransitionMs <= 0) {
      return Duration.zero;
    }
    return Duration(
      milliseconds: transition.inMilliseconds
          .clamp(1000, maxTransitionMs)
          .toInt(),
    );
  }

  Future<void> _performLocalSongTransition({
    required int nextIndex,
    required MusicMetadata nextMetadata,
    required Duration transitionDuration,
  }) async {
    if (_isTransitioning) {
      return;
    }

    final mainPlayer = ref.read(audioPlayerProvider);
    final transitionPlayer = AudioPlayer();
    _transitionPlayer = transitionPlayer;
    _mainVolumeBeforeTransition = mainPlayer.volume.clamp(0, 1).toDouble();
    _isTransitioning = true;

    try {
      await transitionPlayer.setAudioSource(nextMetadata.toAudioSource());
      await transitionPlayer.setVolume(0);
      await transitionPlayer.play();
      await _blendPlayers(
        mainPlayer: mainPlayer,
        transitionPlayer: transitionPlayer,
        targetVolume: _mainVolumeBeforeTransition,
        transitionDuration: transitionDuration,
      );
      if (!_isTransitioning) {
        return;
      }
      await mainPlayer.seek(transitionDuration, index: nextIndex);
      await mainPlayer.setVolume(_mainVolumeBeforeTransition);
      if (!mainPlayer.playing) {
        await mainPlayer.play();
      }
      ref.read(nowPlayingDetailsProvider.notifier).setCurrentIndex(nextIndex);
      ref
          .read(crashLogServiceProvider)
          .recordPlaybackBreadcrumb(
            'Local song transition complete',
            data: _playbackCrashData(
              extra: {
                'nextIndex': nextIndex,
                'nextTrackName': nextMetadata.trackName,
                'transitionDurationMs': transitionDuration.inMilliseconds,
              },
            ),
          );
    } catch (error, stackTrace) {
      ref
          .read(crashLogServiceProvider)
          .recordPlaybackError(
            'Local song transition failed',
            error: error,
            stackTrace: stackTrace,
            data: _playbackCrashData(
              extra: {
                'nextIndex': nextIndex,
                'nextTrackName': nextMetadata.trackName,
                'transitionDurationMs': transitionDuration.inMilliseconds,
              },
            ),
          );
      await mainPlayer.setVolume(_mainVolumeBeforeTransition);
    } finally {
      if (identical(_transitionPlayer, transitionPlayer)) {
        _transitionPlayer = null;
        await transitionPlayer.stop();
        await transitionPlayer.dispose();
      }
      _isTransitioning = false;
    }
  }

  Future<void> _blendPlayers({
    required AudioPlayer mainPlayer,
    required AudioPlayer transitionPlayer,
    required double targetVolume,
    required Duration transitionDuration,
  }) async {
    final steps = (transitionDuration.inMilliseconds / 120)
        .ceil()
        .clamp(8, 80)
        .toInt();
    final stepDelay = Duration(
      milliseconds: (transitionDuration.inMilliseconds / steps).round(),
    );
    for (var step = 0; step <= steps; step++) {
      if (!_isTransitioning) {
        return;
      }
      final progress = step / steps;
      await mainPlayer.setVolume(targetVolume * (1 - progress));
      await transitionPlayer.setVolume(targetVolume * progress);
      if (step < steps) {
        await Future<void>.delayed(stepDelay);
      }
    }
  }

  Future<void> _cancelSongTransition() async {
    if (!_isTransitioning && _transitionPlayer == null) {
      return;
    }
    _isTransitioning = false;
    final transitionPlayer = _transitionPlayer;
    _transitionPlayer = null;
    if (transitionPlayer != null) {
      await transitionPlayer.stop();
      await transitionPlayer.dispose();
    }
    _transitionSourceIndex = null;
    await ref.read(audioPlayerProvider).setVolume(_mainVolumeBeforeTransition);
  }

  Future<void> _syncEqualizerPreset() async {
    final settings = ref.read(settingsPreferencesControllerProvider);
    final presetName = settings.activeCustomEqualizerPreset?.id ??
        settings.equalizerPreset.name;
    final displayName = settings.equalizerDisplayTitle;
    final bandGainsDb = settings.activeEqualizerBandGainsDb;
    if (ref.read(nativeEqPlaybackActiveProvider)) {
      await ref.read(nativeEqPlayerServiceProvider).setBandGains(
            presetName: presetName,
            displayName: displayName,
            bandGainsDb: bandGainsDb,
            preampDb: settings.activeEqualizerPreampDb,
          );
      return;
    }
    await ref.read(audioEqualizerServiceProvider).applyBandGains(
          presetName: presetName,
          displayName: displayName,
          bandGainsDb: bandGainsDb,
          preampDb: settings.activeEqualizerPreampDb,
        );
  }

  Future<void> previewEqualizerBandGains(List<double> bandGainsDb) {
    final generation = ++_equalizerPreviewGeneration;
    final requestedGains = List<double>.of(bandGainsDb);
    final task = _equalizerPreviewTail.then((_) async {
      if (generation != _equalizerPreviewGeneration) {
        return;
      }
      await _applyEqualizerPreview(requestedGains, generation);
    });
    _equalizerPreviewTail = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        ref.read(crashLogServiceProvider).recordPlaybackError(
              'Equalizer preview failed',
              error: error,
              stackTrace: stackTrace,
              data: _playbackCrashData(extra: {
                'previewGeneration': generation,
              }),
            );
      },
    );
    return _equalizerPreviewTail;
  }

  Future<void> _applyEqualizerPreview(
    List<double> bandGainsDb,
    int generation,
  ) async {
    if (generation != _equalizerPreviewGeneration) {
      return;
    }
    final normalizedBandGainsDb = CustomEqualizerPreset.normalizeBandGains(
      bandGainsDb,
    );
    final preampDb = CustomEqualizerPreset.recommendedPreampDb(
      normalizedBandGainsDb,
    );
    if (ref.read(nativeEqPlaybackActiveProvider)) {
      await ref.read(nativeEqPlayerServiceProvider).setBandGains(
            presetName: 'custom_preview',
            displayName: 'Custom Preview',
            bandGainsDb: normalizedBandGainsDb,
            preampDb: preampDb,
          );
      return;
    }

    final details = ref.read(nowPlayingDetailsProvider);
    final currentMetadata = details.currentMetadata;
    final canUseNativePreview = currentMetadata != null &&
        !currentMetadata.isAppleMusicCatalogTrack &&
        details.metadataList.isNotEmpty &&
        !normalizedBandGainsDb.every((gain) => gain == 0);
    if (canUseNativePreview) {
      final player = ref.read(audioPlayerProvider);
      final wasPlaying = details.isPlaying || player.playing;
      final position = player.position;
      final startingIndex = details.currentIndex;
      final startingMetadata = currentMetadata;
      _isReconfiguringEqualizerPlayback = true;
      _suppressCompletionAdvanceFor(const Duration(seconds: 2));
      try {
        final didLoadNativePreview = await _trySetNativeEqAudioSource(
          nowPlayingType: details.nowPlayingType,
          musicMetadataList: details.metadataList,
          initialIndex: startingIndex,
          previewBandGainsDb: normalizedBandGainsDb,
          previewPreampDb: preampDb,
          operationReason: 'eq_custom_preview',
        );
        if (didLoadNativePreview &&
            generation == _equalizerPreviewGeneration) {
          await ref.read(nativeEqPlayerServiceProvider).seekTo(position);
          if (wasPlaying) {
            await ref.read(nativeEqPlayerServiceProvider).play();
            ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(true);
          }
          return;
        }
      } finally {
        _restoreEqualizerReconfigureIdentity(startingIndex, startingMetadata);
        _suppressCompletionAdvanceFor(const Duration(seconds: 2));
        _isReconfiguringEqualizerPlayback = false;
      }
    }

    await ref.read(audioEqualizerServiceProvider).applyBandGains(
          presetName: 'custom_preview',
          displayName: 'Custom Preview',
          bandGainsDb: normalizedBandGainsDb,
          preampDb: preampDb,
        );
  }

  Future<void> settleEqualizerPreview() async {
    _equalizerPreviewGeneration++;
    await _equalizerPreviewTail;
  }

  Future<void> restoreEqualizerPreview() async {
    await settleEqualizerPreview();
    await reconfigureEqualizerPlayback();
  }

  Future<void> togglePlayback() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      if (nowPlayingDetails.currentMetadata?.isAppleMusicCatalogTrack ??
          false) {
        if (nowPlayingDetails.isPlaying) {
          await pause();
        } else {
          await play();
        }
        return;
      }

      if (ref.read(nativeEqPlaybackActiveProvider)) {
        if (nowPlayingDetails.isPlaying) {
          await pause();
        } else {
          await play();
        }
        return;
      }

      if (ref.read(audioPlayerProvider).playing) {
        await pause();
      } else {
        await play();
      }
    });
  }

  Future<void> seekForward() async {
    if (ref
            .read(nowPlayingDetailsProvider)
            .currentMetadata
            ?.isAppleMusicCatalogTrack ??
        false) {
      await ref
          .read(appleMusicPlaybackServiceProvider)
          .seekBy(const Duration(seconds: 1));
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (ref.read(nativeEqPlaybackActiveProvider)) {
        final snapshot = await ref.read(nativeEqPlayerServiceProvider).snapshot();
        await ref
            .read(nativeEqPlayerServiceProvider)
            .seekTo(snapshot.position + const Duration(seconds: 1));
        return;
      }
      final int currentDurationInSeconds = ref
          .read(audioPlayerProvider)
          .position
          .inSeconds;
      final int maxDurationInSeconds =
          ref.read(audioPlayerProvider).duration?.inSeconds ?? 0;
      if (currentDurationInSeconds + 1 < maxDurationInSeconds) {
        await _cancelSongTransition();
        await ref
            .read(audioPlayerProvider)
            .seek(
              Duration(
                seconds: ref.read(audioPlayerProvider).position.inSeconds + 1,
              ),
            );
      }
    });
  }

  Future<void> seekBackward() async {
    if (ref
            .read(nowPlayingDetailsProvider)
            .currentMetadata
            ?.isAppleMusicCatalogTrack ??
        false) {
      await ref
          .read(appleMusicPlaybackServiceProvider)
          .seekBy(const Duration(seconds: -1));
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (ref.read(nativeEqPlaybackActiveProvider)) {
        final snapshot = await ref.read(nativeEqPlayerServiceProvider).snapshot();
        final target = snapshot.position - const Duration(seconds: 1);
        await ref
            .read(nativeEqPlayerServiceProvider)
            .seekTo(target.isNegative ? Duration.zero : target);
        return;
      }
      final currentSeconds = ref.read(audioPlayerProvider).position.inSeconds;
      final targetSeconds = (currentSeconds - 1)
          .clamp(0, currentSeconds)
          .toInt();
      await _cancelSongTransition();
      await ref
          .read(audioPlayerProvider)
          .seek(Duration(seconds: targetSeconds));
    });
  }

  Future<void> seekToDuration(int targetDurationInSeconds) async {
    if (ref
            .read(nowPlayingDetailsProvider)
            .currentMetadata
            ?.isAppleMusicCatalogTrack ??
        false) {
      await ref
          .read(appleMusicPlaybackServiceProvider)
          .seekTo(Duration(seconds: targetDurationInSeconds));
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (ref.read(nativeEqPlaybackActiveProvider)) {
        await ref
            .read(nativeEqPlayerServiceProvider)
            .seekTo(Duration(seconds: targetDurationInSeconds));
        return;
      }
      final int maxDurationInSeconds =
          ref.read(audioPlayerProvider).duration?.inSeconds ?? 0;
      final clampedTarget = targetDurationInSeconds
          .clamp(0, maxDurationInSeconds)
          .toInt();
      await _cancelSongTransition();
      await ref
          .read(audioPlayerProvider)
          .seek(Duration(seconds: clampedTarget));
    });
  }
}

final _syncedLyricTimestampRegex = RegExp(
  r'^\[\d{1,2}:\d{2}(?:[\.:]\d{1,3})?\]',
  multiLine: true,
);

bool _hasSyncedLyricTiming(String? lyrics) {
  final value = lyrics?.trim();
  return value != null &&
      value.isNotEmpty &&
      _syncedLyricTimestampRegex.hasMatch(value);
}
