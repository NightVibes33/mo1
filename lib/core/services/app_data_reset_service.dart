import 'package:dopi/core/constants/constants.dart';
import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/providers/filtered_audio_files_provider.dart';
import 'package:dopi/core/services/app_documents_service.dart';
import 'package:dopi/core/services/audio_files_service.dart';
import 'package:dopi/core/services/audio_player_service.dart';
import 'package:dopi/core/services/debug_log_service.dart';
import 'package:dopi/features/music/album/providers/album_details_provider.dart';
import 'package:dopi/features/music/artists/providers/artist_names_provider.dart';
import 'package:dopi/features/music/genres/providers/genres_provider.dart';
import 'package:dopi/features/music/playlist/models/playlist_model.dart';
import 'package:dopi/features/music/playlist/providers/playlists_provider.dart';
import 'package:dopi/features/music/songs/provider/songs_provider.dart';
import 'package:dopi/features/now_playing/models/now_playing_model.dart';
import 'package:dopi/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dopi/features/settings/controller/exclude_directories_controller.dart';
import 'package:dopi/features/settings/models/exclude_directory_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

final appDataResetServiceProvider = Provider<AppDataResetService>((ref) {
  return AppDataResetService(ref);
});

class AppDataResetService {
  final Ref ref;

  const AppDataResetService(this.ref);

  Future<void> resetDatabase() async {
    final debugLogService = ref.read(debugLogServiceProvider);
    debugLogService.info('reset', 'Database reset started');

    await ref.read(audioPlayerServiceProvider.notifier).stopPlaybackAndClearQueue();
    await _clearBox<MusicMetadata>(Constants.metadataBoxName);
    await _clearBox<PlaylistModel>(Constants.playlistBoxName);
    await _clearBox<ExcludeDirectoryModel>(Constants.excludedDirectoriesBoxName);
    await ref.read(appDocumentsServiceProvider).deleteUserContent();

    ref.read(audioFilesServiceProvider.notifier).clearLibraryState();
    ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
          nowPlayingType: NowPlayingType.songs,
          newMetadataList: const [],
          isPlaying: false,
        );

    ref.invalidate(excludedDirectoriesProvider);
    ref.invalidate(playlistsProvider);
    ref.invalidate(filteredAudioFilesProvider);
    ref.invalidate(albumDetailsProvider);
    ref.invalidate(artistNamesProvider);
    ref.invalidate(genresProvider);
    ref.invalidate(songsProvider);

    debugLogService.info('reset', 'Database reset complete');
  }

  Future<void> _clearBox<T>(String boxName) async {
    if (!Hive.isBoxOpen(boxName)) {
      return;
    }
    await Hive.box<T>(boxName).clear();
  }
}
