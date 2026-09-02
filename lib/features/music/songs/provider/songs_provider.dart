import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/providers/filtered_audio_files_provider.dart';
import 'package:dopi/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final songsProvider = Provider<List<MusicMetadata>>((ref) {
  final metadataList = ref
      .watch(filteredAudioFilesProvider)
      .requireValue
      .toList();
  final songSortOrder = ref.watch(
    settingsPreferencesControllerProvider.select(
      (settings) => settings.songSortOrder,
    ),
  );
  metadataList.sort(songSortOrder.compare);
  return metadataList;
});
