import 'dart:async';
import 'dart:io';

import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/providers/filtered_audio_files_provider.dart';
import 'package:dope/core/services/audio_equalizer_service.dart';
import 'package:dope/core/services/apple_music_playback_service.dart';
import 'package:dope/core/services/crash_log_service.dart';
import 'package:dope/core/services/lyrics_lookup_service.dart';
import 'package:dope/core/services/song_transition_analysis_service.dart';
import 'package:dope/features/music/album/models/album_model.dart';
import 'package:dope/features/music/playlist/models/playlist_model.dart';
import 'package:dope/features/now_playing/models/now_playing_model.dart';
import 'package:dope/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/song_transition_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

// ---------------------------------------------------------------------------
// EQ effect — created once, shared via provider so AudioEqualizerService
// can reach it without going through a MethodChannel.
// ---------------------------------------------------------------------------

/// The DarwinEqualizer wired into the main AudioPlayer on iOS.
/// On non-iOS platforms this is null and EQ is a no-op.
final iosEqualizerProvider = Provider<DarwinEqualizer?>((ref) {
  if (!Platform.isIOS) return null;
  // 10-band EQ matching the frequencies used in EqualizerPreset.
  return DarwinEqualizer(
    bandCount: 10,
    minFrequency: 20,
    maxFrequency: 20000,
  );
});

/// Creates an [AudioPlayer] with the iOS EQ effect attached (if on iOS).
/// On other platforms a plain [AudioPlayer] is returned.
AudioPlayer _makePlayer(DarwinEqualizer? equalizer) {
  if (Platform.isIOS && equalizer != null) {
    return AudioPlayer(
      audioLoadConfiguration: const AudioLoadConfiguration(
        darwinLoadControl: DarwinLoadControl(
          avAudioEngineEnabled: true,
        ),
      ),
      audioPipeline: AudioPipeline(
        darwinAudioEffects: [equalizer],
      ),
    );
  }
  return AudioPlayer();
}

final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final eq = ref.read(iosEqualizerProvider);
  return _makePlayer(eq);
});

final audioPlayerServiceProvider =
    AsyncNotifierProvider<AudioPlayerServiceNotifier, void>(
      AudioPlayerServiceNotifier.new,
    );

class AudioPlayerServiceNotifier extends AsyncNotifier<void> {
  AudioPlayerServiceNotifier() : super();

  AudioPlayer? _transitionPlayer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  Timer? _playbackCrashHeartbeatTimer;
  ProcessingState? _lastLoggedProcessingState;
  int? _transitionSourceIndex;
  bool _isPreparingTransition = false;
  bool _isTransitioning = false;
  double _mainVolumeBeforeTransition = 1;

  @override
  Future<void> build() async {
    final player = ref.read(audioPlayerProvider);
    _positionSubscription = player.positionStream.listen((position) {
      unawaited(_maybeStartSongTransition(position));
    });
    _installPlaybackCrashLogging(player);
    ref.onDispose(() {
      _playbackCrashHeartbeatTimer?.cancel();
      unawaited(_positionSubscription?.cancel());
      unawaited(_playerStateSubscription?.cancel());
      unawaited(_playbackEventSubscription?.cancel());
      unawaited(_transitionPlayer?.dispose());
    });
    await syncSongTransitionStyle();
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
      ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
            'Playback heartbeat',
            data: _playbackCrashData(),
            appendToCrashLog: false,
          );
    } catch (_) {
      // Crash logging must never be able to crash playback.
    }
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
      'transitionStyle': settings.songTransitionStyle.name,
      'crossfadeSeconds': settings.crossfadeDurationSeconds,
      'isPreparingTransition': _isPreparingTransition,
      'isTransitioning': _isTransitioning,
      'transitionSourceIndex': _transitionSourceIndex,
      ...extra,
    };
  }

  Future<void> syncSongTransitionStyle() async {
    final settings = ref.read(settingsPreferencesControllerProvider);
    await ref.read(appleMusicPlaybackServiceProvider).setTransitionStyle(
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

    if (player.playing) {
      return;
    }
    ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
          'Local playback requested',
          data: _playbackCrashData(),
        );
    if (player.currentIndex == null && metadata != null) {
      await playSongFromOriginalList(metadata.originalSongIndex);
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

    if (ref.read(audioPlayerProvider).playing) {
      ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
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
      if (ref.read(nowPlayingDetailsProvider).nowPlayingType !=
          NowPlayingType.songs) {
        await setAudioSource(
          musicMetadataList: ref.read(filteredAudioFilesProvider).requireValue,
        );
      }

      await setShuffleMode(true);
      await ref.read(audioPlayerProvider).shuffle();
      await nextSong();
      Future.delayed(const Duration(milliseconds: 100), play);

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
      await ref.read(audioPlayerProvider).stop();
      ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
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
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _pauseAppleMusicPlaybackIfCurrent();
      await _cancelSongTransition();
      ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
            'Setting local audio source',
            data: {
              'requestedCount': musicMetadataList.length,
              'initialIndex': initialIndex,
              'nowPlayingType': nowPlayingType.name,
            },
          );
      final requestedMetadata = musicMetadataList.isEmpty
          ? null
          : musicMetadataList[
              initialIndex.clamp(0, musicMetadataList.length - 1).toInt()
            ];
      final localMetadataList = musicMetadataList
          .where((metadata) => !metadata.isAppleMusicCatalogTrack)
          .toList(growable: false);
      final List<AudioSource> songSourcePlaylist = [];
      try {
        for (final musicMetadata in localMetadataList) {
          songSourcePlaylist.add(musicMetadata.toAudioSource());
        }
      } catch (_) {}

      if (songSourcePlaylist.isEmpty) {
        ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
              'Local audio source was empty',
              data: {
                'requestedCount': musicMetadataList.length,
                'localCount': localMetadataList.length,
              },
            );
        await ref.read(audioPlayerProvider).stop();
        ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
              nowPlayingType: nowPlayingType,
              newMetadataList: const [],
            );
        return;
      }

      final matchingInitialIndex = localMetadataList.indexWhere((metadata) {
        final requestedPath = requestedMetadata?.filePath;
        return (requestedPath != null && metadata.filePath == requestedPath) ||
            metadata.originalSongIndex == requestedMetadata?.originalSongIndex;
      });
      final safeInitialIndex = matchingInitialIndex == -1
          ? 0
          : matchingInitialIndex.clamp(0, songSourcePlaylist.length - 1).toInt();

      await ref.read(audioPlayerProvider).setAudioSources(
            songSourcePlaylist,
            initialIndex: safeInitialIndex,
            initialPosition: Duration.zero,
            shuffleOrder: DefaultShuffleOrder(),
          );
      ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
            'Local audio source loaded',
            data: {
              'localCount': localMetadataList.length,
              'safeInitialIndex': safeInitialIndex,
              'requestedTrack': requestedMetadata?.trackName,
              'requestedPath': requestedMetadata?.filePath,
            },
          );

      await _syncEqualizerPreset();

      ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
            nowPlayingType: nowPlayingType,
            newMetadataList: localMetadataList,
            currentIndex: safeInitialIndex,
          );
    });
  }

  Future<void> nextSong() async {
    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    if (nowPlayingDetails.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
      final nextIndex = nowPlayingDetails.currentIndex + 1;
      if (nextIndex >= nowPlayingDetails.metadataList.length) {
        return;
      }
      final metadata = nowPlayingDetails.metadataList[nextIndex];
      if (!metadata.isAppleMusicCatalogTrack) {
        return;
      }
      await _playAppleMusicCatalogTrack(
        metadata,
        metadataList: nowPlayingDetails.metadataList,
        currentIndex: nextIndex,
        nowPlayingType: nowPlayingDetails.nowPlayingType,
      );
      return;
    }
    await _cancelSongTransition();
    await ref.read(audioPlayerProvider).seekToNext();
  }

  Future<void> seekBackwards() async {
    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    if (nowPlayingDetails.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
      final previousIndex = nowPlayingDetails.currentIndex - 1;
      if (previousIndex < 0) {
        return;
      }
      final metadata = nowPlayingDetails.metadataList[previousIndex];
      if (!metadata.isAppleMusicCatalogTrack) {
        return;
      }
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

      if (nowPlayingDetails.currentIndex == index) {
        return;
      } else {
        await _cancelSongTransition();
        await ref.read(audioPlayerProvider).seek(Duration.zero, index: index);
        Future.delayed(const Duration(milliseconds: 100), play);
      }
    });
  }

  Future<void> playSongFromOriginalList(int originalIndex) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final player = ref.read(audioPlayerProvider);
      var nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      final externalIndex = nowPlayingDetails.metadataList.indexWhere(
        (element) => element.originalSongIndex == originalIndex,
      );
      if (externalIndex != -1 &&
          nowPlayingDetails.metadataList[externalIndex]
              .isAppleMusicCatalogTrack) {
        await _playAppleMusicCatalogTrack(
          nowPlayingDetails.metadataList[externalIndex],
          metadataList: nowPlayingDetails.metadataList,
          currentIndex: externalIndex,
          nowPlayingType: nowPlayingDetails.nowPlayingType,
        );
        return;
      }
      final hasLoadedSources = player.currentIndex != null;
      final shouldUseOriginalList = !hasLoadedSources ||
          nowPlayingDetails.nowPlayingType != NowPlayingType.songs ||
          nowPlayingDetails.metadataList.isEmpty ||
          !nowPlayingDetails.metadataList.any(
            (element) => element.originalSongIndex == originalIndex,
          );

      if (shouldUseOriginalList) {
        final originalList = ref.read(filteredAudioFilesProvider).requireValue;
        final initialIndex = originalList.indexWhere(
          (element) => element.originalSongIndex == originalIndex,
        );
        if (initialIndex == -1) {
          return;
        }
        final selectedOriginalMetadata = originalList[initialIndex];
        if (selectedOriginalMetadata.isAppleMusicCatalogTrack) {
          final appleMusicList = originalList
              .where((metadata) => metadata.isAppleMusicCatalogTrack)
              .toList(growable: false);
          final appleMusicIndex = appleMusicList.indexWhere(
            (metadata) =>
                metadata.filePath == selectedOriginalMetadata.filePath,
          );
          if (appleMusicIndex == -1) {
            return;
          }
          await _playAppleMusicCatalogTrack(
            appleMusicList[appleMusicIndex],
            metadataList: appleMusicList,
            currentIndex: appleMusicIndex,
          );
          return;
        }
        await setAudioSource(
          musicMetadataList: originalList,
          initialIndex: initialIndex,
        );
        nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      }

      if (originalIndex ==
          nowPlayingDetails.currentMetadata?.originalSongIndex) {
        await _syncEqualizerPreset();
        await player.play();
        return;
      }

      final int index = nowPlayingDetails.metadataList.indexWhere(
        (element) => element.originalSongIndex == originalIndex,
      );
      if (index == -1) {
        return;
      }

      await _cancelSongTransition();
      await player.seek(Duration.zero, index: index);
      Future.delayed(const Duration(milliseconds: 200), play);
    });
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
      final appleMusicList = metadataList
          .where((metadata) => metadata.isAppleMusicCatalogTrack)
          .toList(growable: false);
      final appleMusicIndex = appleMusicList.indexWhere(
        (metadata) => metadata.filePath == selectedMetadata.filePath,
      );
      if (appleMusicIndex == -1) {
        return false;
      }
      return _playAppleMusicCatalogTrack(
        appleMusicList[appleMusicIndex],
        metadataList: appleMusicList,
        currentIndex: appleMusicIndex,
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
    final didResume = await ref.read(appleMusicPlaybackServiceProvider).resume();
    if (didResume) {
      ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
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

    final localPlayer = ref.read(audioPlayerProvider);
    if (localPlayer.playing) {
      await localPlayer.pause();
    }

    final playbackList = metadataList ?? [metadata];
    final catalogIds = playbackList
        .map((entry) => entry.appleMusicCatalogId)
        .whereType<String>()
        .toList(growable: false);
    final settings = ref.read(settingsPreferencesControllerProvider);
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
    ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
          nowPlayingType: nowPlayingType,
          newMetadataList: playbackList,
          currentIndex: currentIndex,
          isPlaying: didStart,
        );
    if (didStart) {
      unawaited(_refreshAppleMusicLyrics(metadata));
    }
    return didStart;
  }

  Future<void> _refreshAppleMusicLyrics(MusicMetadata metadata) async {
    if (metadata.originalSongIndex < 0 ||
        _hasSyncedLyricTiming(metadata.lyrics)) {
      return;
    }

    try {
      final lyrics = await ref.read(lyricsLookupServiceProvider).findBestFor(
            metadata,
          );
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
    if (ref
            .read(nowPlayingDetailsProvider)
            .currentMetadata
            ?.isAppleMusicCatalogTrack ??
        false) {
      await ref.read(appleMusicPlaybackServiceProvider).pause();
      ref.read(nowPlayingDetailsProvider.notifier).setPlaybackState(false);
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
    final currentIndex = player.currentIndex ?? nowPlayingDetails.currentIndex;
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
    ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
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
    // Transition player uses the same iOS equalizer so EQ is consistent
    // during crossfades.
    final eq = ref.read(iosEqualizerProvider);
    final transitionPlayer = _makePlayer(eq);
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
      ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
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
      ref.read(crashLogServiceProvider).recordPlaybackError(
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
    await ref.read(audioEqualizerServiceProvider).applyPreset(
          ref.read(settingsPreferencesControllerProvider).equalizerPreset,
        );
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

      if (ref.read(audioPlayerProvider).playing) {
        await pause();
      } else {
        await play();
      }
    });
  }

  Future<void> seekForward() async {
    if (ref.read(nowPlayingDetailsProvider).currentMetadata
            ?.isAppleMusicCatalogTrack ??
        false) {
      await ref
          .read(appleMusicPlaybackServiceProvider)
          .seekBy(const Duration(seconds: 1));
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final int currentDurationInSeconds =
          ref.read(audioPlayerProvider).position.inSeconds;
      final int maxDurationInSeconds =
          ref.read(audioPlayerProvider).duration?.inSeconds ?? 0;
      if (currentDurationInSeconds + 1 < maxDurationInSeconds) {
        await _cancelSongTransition();
        await ref.read(audioPlayerProvider).seek(
              Duration(
                seconds:
                    ref.read(audioPlayerProvider).position.inSeconds + 1,
              ),
            );
      }
    });
  }

  Future<void> seekBackward() async {
    if (ref.read(nowPlayingDetailsProvider).currentMetadata
            ?.isAppleMusicCatalogTrack ??
        false) {
      await ref
          .read(appleMusicPlaybackServiceProvider)
          .seekBy(const Duration(seconds: -1));
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final currentSeconds =
          ref.read(audioPlayerProvider).position.inSeconds;
      final targetSeconds =
          (currentSeconds - 1).clamp(0, currentSeconds).toInt();
      await _cancelSongTransition();
      await ref
          .read(audioPlayerProvider)
          .seek(Duration(seconds: targetSeconds));
    });
  }

  Future<void> seekToDuration(int targetDurationInSeconds) async {
    if (ref.read(nowPlayingDetailsProvider).currentMetadata
            ?.isAppleMusicCatalogTrack ??
        false) {
      await ref.read(appleMusicPlaybackServiceProvider).seekTo(
            Duration(seconds: targetDurationInSeconds),
          );
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
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
