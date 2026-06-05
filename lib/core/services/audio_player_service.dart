import 'dart:async';
import 'dart:math';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/services/debug_log_service.dart';
import 'package:classipod/features/music/album/models/album_model.dart';
import 'package:classipod/features/music/playlist/models/playlist_model.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

final audioPlayerProvider = Provider<AudioPlayer>((_) {
  return AudioPlayer();
});

final audioPlayerServiceProvider =
    AsyncNotifierProvider<AudioPlayerServiceNotifier, void>(
      AudioPlayerServiceNotifier.new,
    );

class AudioPlayerServiceNotifier extends AsyncNotifier<void> {
  static const int _singleSourceThreshold = 80;

  final Random _random = Random();

  AudioPlayerServiceNotifier() : super();

  @override
  Future<void> build() async {
    ref.read(audioPlayerProvider).processingStateStream.listen((state) {
      if (state == ProcessingState.completed && _isSingleSourceMode) {
        unawaited(_handleSingleSourceCompletion());
      }
    });
  }

  Future<void> _handleSingleSourceCompletion() async {
    final player = ref.read(audioPlayerProvider);
    final details = ref.read(nowPlayingDetailsProvider);
    if (!_isSingleSourceMode || details.metadataList.isEmpty) {
      return;
    }
    if (details.loopMode == LoopMode.one) {
      await player.seek(Duration.zero);
      _startPlayback();
      return;
    }
    await nextSong();
  }

  DebugLogService get _logger => ref.read(debugLogServiceProvider);

  void _startPlayback() {
    unawaited(
      ref.read(audioPlayerProvider).play().catchError((Object error, StackTrace stackTrace) {
        _logger.error(
          'playback',
          'Audio playback start failed',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  bool get _isSingleSourceMode {
    final player = ref.read(audioPlayerProvider);
    final details = ref.read(nowPlayingDetailsProvider);
    return (player.sequence?.length ?? 0) <= 1 &&
        details.metadataList.length > 1;
  }

  Future<void> play() async {
    final player = ref.read(audioPlayerProvider);
    if (player.playing) {
      return;
    }
    if (player.currentIndex == null) {
      final metadata = ref.read(nowPlayingDetailsProvider).currentMetadata;
      if (metadata != null) {
        await playSongFromOriginalList(metadata.originalSongIndex);
        return;
      }
    }
    _startPlayback();
  }

  Future<void> pause() async {
    if (ref.read(audioPlayerProvider).playing) {
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
      final originalList = ref.read(filteredAudioFilesProvider).requireValue;
      if (originalList.isEmpty) {
        return;
      }

      await setShuffleMode(true);
      final targetIndex = originalList.length == 1
          ? 0
          : _random.nextInt(originalList.length);
      await setAudioSource(
        musicMetadataList: originalList,
        initialIndex: targetIndex,
      );
      await play();

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

  Future<void> setAudioSource({
    NowPlayingType nowPlayingType = NowPlayingType.songs,
    required List<MusicMetadata> musicMetadataList,
    int initialIndex = 0,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (musicMetadataList.isEmpty) {
        await ref.read(audioPlayerProvider).stop();
        ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
              nowPlayingType: nowPlayingType,
              newMetadataList: const [],
            );
        _logger.warning('playback', 'No audio sources to load');
        return;
      }

      final safeInitialIndex = initialIndex
          .clamp(0, musicMetadataList.length - 1)
          .toInt();

      if (musicMetadataList.length > _singleSourceThreshold) {
        await _setSingleAudioSource(
          nowPlayingType: nowPlayingType,
          musicMetadataList: musicMetadataList,
          index: safeInitialIndex,
          autoPlay: false,
        );
        return;
      }

      final List<AudioSource> songSourcePlaylist = [];
      for (final musicMetadata in musicMetadataList) {
        try {
          songSourcePlaylist.add(musicMetadata.toAudioSource());
        } catch (error, stackTrace) {
          _logger.error(
            'playback',
            'Failed to create audio source',
            error: error,
            stackTrace: stackTrace,
            data: {
              'path': musicMetadata.filePath,
              'title': musicMetadata.trackName,
            },
          );
        }
      }

      if (songSourcePlaylist.isEmpty) {
        await ref.read(audioPlayerProvider).stop();
        ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
              nowPlayingType: nowPlayingType,
              newMetadataList: const [],
            );
        _logger.warning('playback', 'All audio sources failed to build');
        return;
      }

      final playlistIndex = safeInitialIndex
          .clamp(0, songSourcePlaylist.length - 1)
          .toInt();
      _logger.info(
        'playback',
        'Loading playlist sources',
        data: {
          'count': songSourcePlaylist.length,
          'index': playlistIndex,
          'type': nowPlayingType.name,
        },
      );
      await ref.read(audioPlayerProvider).setAudioSources(
            songSourcePlaylist,
            initialIndex: playlistIndex,
            initialPosition: Duration.zero,
            shuffleOrder: DefaultShuffleOrder(),
            preload: false,
          );

      ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
            nowPlayingType: nowPlayingType,
            newMetadataList: musicMetadataList,
            currentIndex: playlistIndex,
          );
    });
  }

  Future<void> _setSingleAudioSource({
    required NowPlayingType nowPlayingType,
    required List<MusicMetadata> musicMetadataList,
    required int index,
    required bool autoPlay,
  }) async {
    if (musicMetadataList.isEmpty) {
      return;
    }
    final safeIndex = index.clamp(0, musicMetadataList.length - 1).toInt();
    final metadata = musicMetadataList[safeIndex];
    ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
          nowPlayingType: nowPlayingType,
          newMetadataList: musicMetadataList,
          currentIndex: safeIndex,
        );
    _logger.info(
      'playback',
      'Loading single source',
      data: {
        'libraryCount': musicMetadataList.length,
        'index': safeIndex,
        'title': metadata.trackName,
        'artist': metadata.getTrackArtistNames,
        'path': metadata.filePath,
        'autoPlay': autoPlay,
      },
    );
    await ref.read(audioPlayerProvider).setAudioSource(
          metadata.toAudioSource(),
          initialPosition: Duration.zero,
          preload: false,
        );
    if (autoPlay) {
      _startPlayback();
    }
  }

  Future<void> _playMetadataIndex(int index) async {
    final details = ref.read(nowPlayingDetailsProvider);
    if (details.metadataList.isEmpty) {
      return;
    }
    await _setSingleAudioSource(
      nowPlayingType: details.nowPlayingType,
      musicMetadataList: details.metadataList,
      index: index,
      autoPlay: true,
    );
  }

  Future<void> nextSong() async {
    if (_isSingleSourceMode) {
      final details = ref.read(nowPlayingDetailsProvider);
      if (details.metadataList.isEmpty) {
        return;
      }
      final int targetIndex;
      if (ref.read(audioPlayerProvider).shuffleModeEnabled &&
          details.metadataList.length > 1) {
        var nextIndex = _random.nextInt(details.metadataList.length);
        if (nextIndex == details.currentIndex) {
          nextIndex = (nextIndex + 1) % details.metadataList.length;
        }
        targetIndex = nextIndex;
      } else if (details.currentIndex >= details.metadataList.length - 1) {
        if (details.loopMode == LoopMode.all) {
          targetIndex = 0;
        } else {
          return;
        }
      } else {
        targetIndex = details.currentIndex + 1;
      }
      await _playMetadataIndex(targetIndex);
      return;
    }
    await ref.read(audioPlayerProvider).seekToNext();
  }

  Future<void> seekBackwards() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final player = ref.read(audioPlayerProvider);
      if (player.position.inSeconds > 3) {
        await player.seek(Duration.zero);
        return;
      }
      if (_isSingleSourceMode) {
        final details = ref.read(nowPlayingDetailsProvider);
        if (details.currentIndex <= 0) {
          if (details.loopMode == LoopMode.all && details.metadataList.isNotEmpty) {
            await _playMetadataIndex(details.metadataList.length - 1);
          }
          return;
        }
        await _playMetadataIndex(details.currentIndex - 1);
      } else {
        await player.seekToPrevious();
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
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      if (nowPlayingDetails.nowPlayingType == NowPlayingType.album &&
          nowPlayingDetails.currentMetadata?.getAlbumDetail == albumDetail) {
        await playSongAtIndex(songIndex);
        return;
      }
      await setAudioSource(
        nowPlayingType: NowPlayingType.album,
        musicMetadataList: albumDetail.albumSongs,
        initialIndex: songIndex,
      );
      await playSongAtIndex(songIndex);
      await setShuffleMode(false);
      unawaited(Future.delayed(const Duration(milliseconds: 100), play));
    });
  }

  Future<void> playPlaylist({
    required PlaylistModel playlistDetail,
    required int songIndex,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (playlistDetail.songs.isEmpty || songIndex >= playlistDetail.songs.length) {
        return;
      }
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      if (nowPlayingDetails.nowPlayingType == NowPlayingType.playlist &&
          listEquals(nowPlayingDetails.metadataList, playlistDetail.songs)) {
        await playSongAtIndex(songIndex);
        return;
      }
      await setAudioSource(
        nowPlayingType: NowPlayingType.playlist,
        musicMetadataList: playlistDetail.songs,
        initialIndex: songIndex,
      );
      await playSongAtIndex(songIndex);
      await setShuffleMode(false);
      unawaited(Future.delayed(const Duration(milliseconds: 100), play));
    });
  }

  Future<void> playSongAtIndex(int index) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final details = ref.read(nowPlayingDetailsProvider);
      if (details.currentIndex == index && ref.read(audioPlayerProvider).playing) {
        return;
      }
      if (_isSingleSourceMode || details.metadataList.length > _singleSourceThreshold) {
        await _playMetadataIndex(index);
      } else {
        await ref.read(audioPlayerProvider).seek(Duration.zero, index: index);
        unawaited(Future.delayed(const Duration(milliseconds: 100), play));
      }
    });
  }

  Future<void> playSongFromOriginalList(int originalIndex) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final player = ref.read(audioPlayerProvider);
      var nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
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
          _logger.warning(
            'playback',
            'Requested song was not found in original list',
            data: {'originalIndex': originalIndex},
          );
          return;
        }
        if (originalList.length > _singleSourceThreshold) {
          await _setSingleAudioSource(
            nowPlayingType: NowPlayingType.songs,
            musicMetadataList: originalList,
            index: initialIndex,
            autoPlay: true,
          );
          return;
        }
        await setAudioSource(
          musicMetadataList: originalList,
          initialIndex: initialIndex,
        );
        nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
      }

      if (originalIndex == nowPlayingDetails.currentMetadata?.originalSongIndex) {
        _startPlayback();
        return;
      }

      final int index = nowPlayingDetails.metadataList.indexWhere(
        (element) => element.originalSongIndex == originalIndex,
      );
      if (index == -1) {
        _logger.warning(
          'playback',
          'Requested song was not found in current queue',
          data: {'originalIndex': originalIndex},
        );
        return;
      }

      if (_isSingleSourceMode ||
          nowPlayingDetails.metadataList.length > _singleSourceThreshold) {
        await _playMetadataIndex(index);
      } else {
        await player.seek(Duration.zero, index: index);
        unawaited(Future.delayed(const Duration(milliseconds: 200), play));
      }
    });
  }

  Future<void> togglePlayback() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (ref.read(audioPlayerProvider).playing) {
        await pause();
      } else {
        await play();
      }
    });
  }

  Future<void> seekForward() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final int currentDurationInSeconds = ref
          .read(audioPlayerProvider)
          .position
          .inSeconds;
      final int maxDurationInSeconds =
          ref.read(audioPlayerProvider).duration?.inSeconds ?? 0;
      if (currentDurationInSeconds + 1 < maxDurationInSeconds) {
        await ref.read(audioPlayerProvider).seek(
              Duration(seconds: currentDurationInSeconds + 1),
            );
      }
    });
  }

  Future<void> seekBackward() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final currentSeconds = ref.read(audioPlayerProvider).position.inSeconds;
      final targetSeconds = (currentSeconds - 1).clamp(0, currentSeconds).toInt();
      await ref.read(audioPlayerProvider).seek(Duration(seconds: targetSeconds));
    });
  }

  Future<void> seekToDuration(int targetDurationInSeconds) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final int maxDurationInSeconds =
          ref.read(audioPlayerProvider).duration?.inSeconds ?? 0;
      final clampedTarget = targetDurationInSeconds
          .clamp(0, maxDurationInSeconds)
          .toInt();
      await ref.read(audioPlayerProvider).seek(Duration(seconds: clampedTarget));
    });
  }
}
