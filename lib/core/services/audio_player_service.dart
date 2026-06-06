import 'dart:async';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/services/audio_equalizer_service.dart';
import 'package:classipod/core/services/apple_music_playback_service.dart';
import 'package:classipod/core/services/lyrics_lookup_service.dart';
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
  AudioPlayerServiceNotifier() : super();

  @override
  Future<void> build() async {}

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
      //If Album or Playlist is being played then Switch to original List of Songs
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

  Future<void> setAudioSource({
    NowPlayingType nowPlayingType = NowPlayingType.songs,
    required List<MusicMetadata> musicMetadataList,
    int initialIndex = 0,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _pauseAppleMusicPlaybackIfCurrent();
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
        await ref.read(audioPlayerProvider).seek(Duration.zero);
      } else {
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
      // If Album has no songs or the songIndex is out of bounds
      if (albumDetail.albumSongs.isEmpty ||
          songIndex >= albumDetail.albumSongs.length) {
        return;
      }
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);

      // If the album is already playing
      if (nowPlayingDetails.nowPlayingType == NowPlayingType.album &&
          nowPlayingDetails.currentMetadata?.getAlbumDetail == albumDetail) {
        await playSongAtIndex(songIndex);
        return;
      } else {
        await setAudioSource(
          nowPlayingType: NowPlayingType.album,
          musicMetadataList: albumDetail.albumSongs,
          initialIndex: songIndex,
        );
        await playSongAtIndex(songIndex);
        await setShuffleMode(false);
        Future.delayed(const Duration(milliseconds: 100), play);
      }
    });
  }

  Future<void> playPlaylist({
    required PlaylistModel playlistDetail,
    required int songIndex,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // If Playlist has no songs or the songIndex is out of bounds
      if (playlistDetail.songs.isEmpty ||
          songIndex >= playlistDetail.songs.length) {
        return;
      }
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);

      // If the playlist is already playing
      if (nowPlayingDetails.nowPlayingType == NowPlayingType.playlist &&
          listEquals(nowPlayingDetails.metadataList, playlistDetail.songs)) {
        await playSongAtIndex(songIndex);
        return;
      } else {
        await setAudioSource(
          nowPlayingType: NowPlayingType.playlist,
          musicMetadataList: playlistDetail.songs,
          initialIndex: songIndex,
        );
        await playSongAtIndex(songIndex);
        await setShuffleMode(false);
        Future.delayed(const Duration(milliseconds: 100), play);
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

      //In case the same song is already playing
      if (nowPlayingDetails.currentIndex == index) {
        return;
      } else {
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
          nowPlayingDetails.nowPlayingType !=
              NowPlayingType.songs ||
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
            (metadata) => metadata.filePath == selectedOriginalMetadata.filePath,
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
    final didStart = await ref
        .read(appleMusicPlaybackServiceProvider)
        .playCatalogQueue(
          catalogIds: catalogIds.isEmpty ? [catalogId] : catalogIds,
          startCatalogId: catalogId,
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
        (metadata.lyrics?.trim().isNotEmpty ?? false)) {
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
      final int currentDurationInSeconds = ref
          .read(audioPlayerProvider)
          .position
          .inSeconds;
      final int maxDurationInSeconds =
          ref.read(audioPlayerProvider).duration?.inSeconds ?? 0;
      if (currentDurationInSeconds + 1 < maxDurationInSeconds) {
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
      final currentSeconds = ref.read(audioPlayerProvider).position.inSeconds;
      final targetSeconds = (currentSeconds - 1).clamp(0, currentSeconds).toInt();
      await ref.read(audioPlayerProvider).seek(Duration(seconds: targetSeconds));
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
      await ref.read(audioPlayerProvider).seek(Duration(seconds: clampedTarget));
    });
  }
}
