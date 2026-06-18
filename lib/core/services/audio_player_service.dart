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

AudioPlayer _makePlayer() => AudioPlayer();

final audioPlayerProvider = Provider<AudioPlayer>((_) => _makePlayer());

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
          NowPlayingType.allSongs) {
        await loadAllSongs();
      }
      await ref.read(audioPlayerProvider).shuffle();
      await ref.read(audioPlayerProvider).setShuffleModeEnabled(true);
    });
  }

  Future<void> skipToNext() async {
    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    if (nowPlayingDetails.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
      await ref.read(appleMusicPlaybackServiceProvider).skipToNextTrack();
      return;
    }
    await ref.read(audioPlayerProvider).seekToNext();
  }

  Future<void> skipToPrevious() async {
    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    if (nowPlayingDetails.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
      await ref.read(appleMusicPlaybackServiceProvider).skipToPreviousTrack();
      return;
    }
    final player = ref.read(audioPlayerProvider);
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) async {
    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    if (nowPlayingDetails.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
      await ref.read(appleMusicPlaybackServiceProvider).seekToTime(position);
      return;
    }
    await ref.read(audioPlayerProvider).seek(position);
  }

  Future<void> setVolume(double volume) async {
    await ref.read(audioPlayerProvider).setVolume(volume);
  }

  Future<void> toggleRepeatMode() async {
    final player = ref.read(audioPlayerProvider);
    final currentMode = player.loopMode;
    if (currentMode == LoopMode.off) {
      await player.setLoopMode(LoopMode.all);
    } else if (currentMode == LoopMode.all) {
      await player.setLoopMode(LoopMode.one);
    } else {
      await player.setLoopMode(LoopMode.off);
    }
  }

  Future<void> setRepeatMode(LoopMode mode) async {
    await ref.read(audioPlayerProvider).setLoopMode(mode);
  }

  Future<void> loadAllSongs() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _loadSongs(
        ref.read(filteredAudioFilesProvider),
        nowPlayingType: NowPlayingType.allSongs,
      );
    });
  }

  Future<void> loadAlbum(AlbumModel album) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _loadSongs(
        album.songs,
        nowPlayingType: NowPlayingType.album,
      );
    });
  }

  Future<void> loadPlaylist(PlaylistModel playlist) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _loadSongs(
        playlist.songs,
        nowPlayingType: NowPlayingType.playlist,
      );
    });
  }

  Future<void> playSongFromOriginalList(int originalSongIndex) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final songs = ref.read(filteredAudioFilesProvider);
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);

      if (nowPlayingDetails.nowPlayingType != NowPlayingType.allSongs) {
        await _loadSongs(
          songs,
          nowPlayingType: NowPlayingType.allSongs,
        );
      }

      final newIndex = songs.indexWhere(
        (s) => s.originalSongIndex == originalSongIndex,
      );

      if (newIndex == -1) {
        return;
      }
      await _syncEqualizerPreset();
      await _playIndex(newIndex);
    });
  }

  Future<void> playSongFromAlbum({
    required AlbumModel album,
    required int songIndex,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      if (nowPlayingDetails.nowPlayingType == NowPlayingType.album &&
          nowPlayingDetails.metadataList.isNotEmpty &&
          nowPlayingDetails.metadataList.first.albumName == album.name) {
        await _syncEqualizerPreset();
        await _playIndex(songIndex);
        return;
      }
      await _loadSongs(album.songs, nowPlayingType: NowPlayingType.album);
      await _syncEqualizerPreset();
      await _playIndex(songIndex);
    });
  }

  Future<void> playSongFromPlaylist({
    required PlaylistModel playlist,
    required int songIndex,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      if (nowPlayingDetails.nowPlayingType == NowPlayingType.playlist &&
          nowPlayingDetails.metadataList.isNotEmpty &&
          nowPlayingDetails.metadataList.first.albumName == playlist.name) {
        await _syncEqualizerPreset();
        await _playIndex(songIndex);
        return;
      }
      await _loadSongs(
        playlist.songs,
        nowPlayingType: NowPlayingType.playlist,
      );
      await _syncEqualizerPreset();
      await _playIndex(songIndex);
    });
  }

  Future<void> _syncEqualizerPreset() async {
    final settings = ref.read(settingsPreferencesControllerProvider);
    await ref
        .read(audioEqualizerServiceProvider.notifier)
        .applyPreset(settings.equalizerPreset);
  }

  Future<void> _playIndex(int index) async {
    ref.read(crashLogServiceProvider).recordPlaybackBreadcrumb(
          'Playing index',
          data: _playbackCrashData(extra: {'targetIndex': index}),
        );
    final player = ref.read(audioPlayerProvider);
    await player.seek(Duration.zero, index: index);
    await player.play();
  }

  Future<void> _loadSongs(
    List<MusicMetadata> songs, {
    required NowPlayingType nowPlayingType,
  }) async {
    final player = ref.read(audioPlayerProvider);
    final playlist = ConcatenatingAudioSource(
      children:
          songs.map((song) => AudioSource.file(song.filePath)).toList(),
    );
    await player.setAudioSource(
      playlist,
      preloadIndex: 0,
    );
    ref.read(nowPlayingDetailsProvider.notifier).setMetadataList(
      songs,
      nowPlayingType: nowPlayingType,
    );
  }

  Future<void> _resumeAppleMusicCatalogTrack(
    MusicMetadata metadata, {
    required List<MusicMetadata> metadataList,
    required int currentIndex,
    required NowPlayingType nowPlayingType,
  }) async {
    await ref.read(appleMusicPlaybackServiceProvider).play(
          metadata: metadata,
          metadataList: metadataList,
          currentIndex: currentIndex,
          nowPlayingType: nowPlayingType,
        );
  }

  // ─── Song Transition ────────────────────────────────────────────────────────

  Future<void> _maybeStartSongTransition(Duration position) async {
    final settings = ref.read(settingsPreferencesControllerProvider);
    final transitionStyle = settings.songTransitionStyle;
    if (transitionStyle == SongTransitionStyle.none) return;

    final player = ref.read(audioPlayerProvider);
    final duration = player.duration;
    if (duration == null || duration.inSeconds < 10) return;
    if (!player.playing) return;

    final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
    if (nowPlayingDetails.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
      return;
    }

    final crossfadeDuration = Duration(
      seconds: settings.crossfadeDurationSeconds,
    );
    final transitionStart = duration - crossfadeDuration;
    if (position < transitionStart) return;

    final currentIndex = player.currentIndex;
    if (currentIndex == null) return;
    if (_isPreparingTransition || _isTransitioning) return;
    if (_transitionSourceIndex == currentIndex) return;

    final nextIndex = player.nextIndex;
    if (nextIndex == null) return;

    _isPreparingTransition = true;
    _transitionSourceIndex = currentIndex;

    final analysisService = ref.read(songTransitionAnalysisServiceProvider);
    final metadataList = nowPlayingDetails.metadataList;
    final currentSong = metadataList[currentIndex];
    final nextSong = metadataList[nextIndex];

    final result = await analysisService.analyze(
      currentSong: currentSong,
      nextSong: nextSong,
      transitionStyle: transitionStyle,
      crossfadeDuration: crossfadeDuration,
    );

    if (result == null) {
      _isPreparingTransition = false;
      return;
    }

    _isPreparingTransition = false;
    _isTransitioning = true;

    await _executeTransition(
      result: result,
      nextSong: nextSong,
      nextIndex: nextIndex,
      crossfadeDuration: crossfadeDuration,
    );
  }

  Future<void> _executeTransition({
    required SongTransitionAnalysisResult result,
    required MusicMetadata nextSong,
    required int nextIndex,
    required Duration crossfadeDuration,
  }) async {
    final player = ref.read(audioPlayerProvider);

    _transitionPlayer = _makePlayer();
    await _transitionPlayer!.setAudioSource(
      AudioSource.file(nextSong.filePath),
    );
    await _transitionPlayer!.seek(result.nextSongStartPosition);

    await _transitionPlayer!.setVolume(0);
    await _transitionPlayer!.play();

    final steps = 20;
    final stepDuration = crossfadeDuration ~/ steps;

    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(stepDuration);
      final progress = i / steps;
      _mainVolumeBeforeTransition = player.volume;
      await player.setVolume(1.0 - progress);
      await _transitionPlayer!.setVolume(progress);
    }

    await player.seekToIndex(nextIndex);
    await player.setVolume(1.0);
    await _transitionPlayer!.stop();
    await _transitionPlayer!.dispose();
    _transitionPlayer = null;
    _isTransitioning = false;
  }

  Future<void> _cancelSongTransition() async {
    if (_transitionPlayer != null) {
      await _transitionPlayer!.stop();
      await _transitionPlayer!.dispose();
      _transitionPlayer = null;
    }
    _isPreparingTransition = false;
    _isTransitioning = false;
    _transitionSourceIndex = null;
    await ref.read(audioPlayerProvider).setVolume(_mainVolumeBeforeTransition);
  }

  // ─── Lyrics ───────────────────────────────────────────────────────────────────

  Future<void> lookupLyrics(MusicMetadata metadata) async {
    await ref.read(lyricsLookupServiceProvider).lookupLyrics(metadata);
  }
}
