import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/providers/filtered_audio_files_provider.dart';
import 'package:dopi/features/music/album/providers/album_details_provider.dart';
import 'package:dopi/features/music/artists/providers/artist_names_provider.dart';
import 'package:dopi/features/music/genres/providers/genres_provider.dart';
import 'package:dopi/features/music/playlist/providers/playlists_provider.dart';
import 'package:dopi/features/music/songs/provider/songs_provider.dart';
import 'package:dopi/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<List<MusicMetadata>> refreshImportedLibraryProviders(
  WidgetRef ref,
) async {
  ref.invalidate(filteredAudioFilesProvider);
  final metadataList = await ref
      .read(filteredAudioFilesProvider.future)
      .then((value) => value.toList());

  ref.invalidate(albumDetailsProvider);
  ref.invalidate(artistNamesProvider);
  ref.invalidate(songsProvider);
  ref.invalidate(genresProvider);
  ref.invalidate(playlistsProvider);
  ref.read(playlistsProvider.notifier).refreshProvider();

  final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);
  final currentMetadata = nowPlayingDetails.currentMetadata;
  final currentIndex = _currentMetadataIndex(metadataList, currentMetadata);
  ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
        nowPlayingType: nowPlayingDetails.nowPlayingType,
        newMetadataList: metadataList,
        currentIndex: currentIndex == -1
            ? nowPlayingDetails.currentIndex
            : currentIndex,
        isPlaying: nowPlayingDetails.isPlaying,
      );

  return metadataList;
}

int _currentMetadataIndex(
  List<MusicMetadata> metadataList,
  MusicMetadata? currentMetadata,
) {
  if (currentMetadata == null) {
    return metadataList.isEmpty ? -1 : 0;
  }

  final currentPath = currentMetadata.filePath;
  return metadataList.indexWhere((metadata) {
    if (metadata.hasSameSourceIdentity(currentMetadata)) {
      return true;
    }
    return currentPath != null && metadata.filePath == currentPath;
  });
}
