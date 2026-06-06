import 'package:classipod/core/constants/constants.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/services/audio_files_service.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/features/music/album/providers/album_details_provider.dart';
import 'package:classipod/features/music/playlist/models/playlist_model.dart';
import 'package:classipod/features/music/playlist/providers/playlists_provider.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart';

final nowPlayingDetailsProvider =
    NotifierProvider<NowPlayingDetailsNotifier, NowPlayingModel>(
      NowPlayingDetailsNotifier.new,
    );

class NowPlayingDetailsNotifier extends Notifier<NowPlayingModel> {
  @override
  NowPlayingModel build() {
    ref.read(audioPlayerProvider).currentIndexStream.listen((newIndex) {
      if (state.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
        return;
      }
      if (newIndex != null &&
          newIndex != state.currentIndex &&
          state.metadataList.isNotEmpty) {
        state = state.copyWith(
          currentIndex: newIndex,
          currentMetadata: state.metadataList[newIndex],
        );
      }
    });

    ref.read(audioPlayerProvider).playingStream.listen((isPlaying) {
      if (state.currentMetadata?.isAppleMusicCatalogTrack ?? false) {
        return;
      }
      if (isPlaying != state.isPlaying) {
        state = state.copyWith(isPlaying: isPlaying);
      }
    });

    ref.read(audioPlayerProvider).loopModeStream.listen((loopMode) {
      if (loopMode != state.loopMode) {
        state = state.copyWith(loopMode: loopMode);
      }
    });

    ref.read(audioPlayerProvider).shuffleModeEnabledStream.listen((
      isShuffleEnabled,
    ) {
      if (isShuffleEnabled != state.isShuffleEnabled) {
        state = state.copyWith(isShuffleEnabled: isShuffleEnabled);
      }
    });

    return NowPlayingModel(
      currentIndex: 0,
      isPlaying: false,
      nowPlayingType: NowPlayingType.songs,
      metadataList: [],
      loopMode: LoopMode.off,
      isShuffleEnabled: false,
    );
  }

  void setNewMetadataList({
    NowPlayingType? nowPlayingType,
    required List<MusicMetadata> newMetadataList,
    int currentIndex = 0,
    bool? isPlaying,
  }) {
    final safeIndex = newMetadataList.isEmpty
        ? 0
        : currentIndex.clamp(0, newMetadataList.length - 1).toInt();
    state = state.copyWith(
      currentIndex: safeIndex,
      nowPlayingType: nowPlayingType,
      currentMetadata: newMetadataList.isNotEmpty
          ? newMetadataList[safeIndex]
          : null,
      metadataList: newMetadataList,
      isPlaying: isPlaying,
    );
  }

  void setPlaybackState(bool isPlaying) {
    state = state.copyWith(isPlaying: isPlaying);
  }

  void setCurrentIndex(int currentIndex) {
    if (state.metadataList.isEmpty) {
      return;
    }
    final safeIndex = currentIndex
        .clamp(0, state.metadataList.length - 1)
        .toInt();
    state = state.copyWith(
      currentIndex: safeIndex,
      currentMetadata: state.metadataList[safeIndex],
    );
  }

  Future<void> setCurrentMetadataRating(int val) async {
    if (0 <= val && val <= 5 && state.currentMetadata != null) {
      final newMetadata = state.currentMetadata!.copyWith(rating: val);
      await updateMetadata(newMetadata);
    }
  }

  Future<void> increaseCurrentMetadataRating() async {
    final int? currentRating = state.currentMetadata?.rating;
    if (currentRating != null && currentRating < 5) {
      await setCurrentMetadataRating(currentRating + 1);
    }
  }

  Future<void> decreaseCurrentMetadataRating() async {
    final int? currentRating = state.currentMetadata?.rating;
    if (currentRating != null && currentRating > 0) {
      await setCurrentMetadataRating(currentRating - 1);
    }
  }

  Future<void> _updatePersistedPlaylistMetadata(
    MusicMetadata updatedMetadata,
  ) async {
    final playlistBox = Hive.box<PlaylistModel>(Constants.playlistBoxName);
    for (var index = 0; index < playlistBox.length; index++) {
      final playlist = playlistBox.getAt(index);
      if (playlist == null) {
        continue;
      }

      var changed = false;
      final updatedSongs = <MusicMetadata>[];
      for (final song in playlist.songs) {
        if (song.originalSongIndex == updatedMetadata.originalSongIndex) {
          updatedSongs.add(updatedMetadata);
          changed = true;
        } else {
          updatedSongs.add(song);
        }
      }

      if (changed) {
        await playlistBox.putAt(
          index,
          playlist.copyWith(songs: updatedSongs),
        );
      }
    }
  }

  Future<void> updateMetadata(MusicMetadata updatedMetadata) async {
    final Box<MusicMetadata> metadataBox = Hive.box<MusicMetadata>(
      Constants.metadataBoxName,
    );
    final storageIndex = _metadataStorageIndex(metadataBox, updatedMetadata);
    final existingMetadata = storageIndex == -1
        ? null
        : metadataBox.getAt(storageIndex);
    final storedMetadata = updatedMetadata.copyWith(
      originalSongIndex:
          existingMetadata?.originalSongIndex ?? updatedMetadata.originalSongIndex,
    );

    if (storageIndex == -1) {
      await metadataBox.add(storedMetadata);
    } else {
      await metadataBox.putAt(storageIndex, storedMetadata);
    }

    state = state.copyWith(
      currentMetadata:
          state.currentMetadata?.originalSongIndex ==
              storedMetadata.originalSongIndex
          ? storedMetadata
          : state.currentMetadata,
      metadataList: [
        for (final metadata in state.metadataList)
          if (metadata.originalSongIndex == storedMetadata.originalSongIndex)
            storedMetadata
          else
            metadata,
      ],
    );

    await _updatePersistedPlaylistMetadata(storedMetadata);
    ref.invalidate(audioFilesServiceProvider);
    ref.invalidate(filteredAudioFilesProvider);
    ref.invalidate(albumDetailsProvider);
    ref.invalidate(playlistsProvider);
  }

  int _metadataStorageIndex(
    Box<MusicMetadata> metadataBox,
    MusicMetadata updatedMetadata,
  ) {
    for (var index = 0; index < metadataBox.length; index++) {
      final metadata = metadataBox.getAt(index);
      if (metadata == null) {
        continue;
      }
      if (metadata.originalSongIndex == updatedMetadata.originalSongIndex) {
        return index;
      }
    }

    final updatedPath = updatedMetadata.filePath;
    if (updatedPath != null) {
      for (var index = 0; index < metadataBox.length; index++) {
        final metadata = metadataBox.getAt(index);
        if (metadata?.filePath == updatedPath) {
          return index;
        }
      }
    }

    if (updatedMetadata.originalSongIndex >= 0 &&
        updatedMetadata.originalSongIndex < metadataBox.length) {
      return updatedMetadata.originalSongIndex;
    }

    return -1;
  }
}
