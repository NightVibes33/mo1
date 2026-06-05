import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:classipod/core/constants/constants.dart';
import 'package:classipod/core/constants/online_audio_files_metadata.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/device_directory_provider.dart';
import 'package:classipod/core/repositories/metadata_reader_repository.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:on_audio_query/on_audio_query.dart';

final audioFilesServiceProvider =
    AsyncNotifierProvider<
      AudioFilesServiceNotifier,
      UnmodifiableListView<MusicMetadata>
    >(AudioFilesServiceNotifier.new);

class AudioFilesServiceNotifier
    extends AsyncNotifier<UnmodifiableListView<MusicMetadata>> {
  static const List<String> _importableExtensions = [
    'mp3',
    'm4a',
    'mp4',
    'm4b',
    'aac',
    'alac',
    'wav',
    'aif',
    'aiff',
    'aifc',
    'flac',
    'ogg',
    'opus',
    'ape',
    'lrc',
    'txt',
  ];

  @override
  Future<UnmodifiableListView<MusicMetadata>> build() async {
    return getAudioFilesMetadata();
  }

  Future<UnmodifiableListView<MusicMetadata>> getAudioFilesMetadata() async {
    state = const AsyncLoading();
    try {
      if (ref.read(settingsPreferencesControllerProvider).fetchOnlineMusic) {
        return UnmodifiableListView(onlineDemoAudioFilesMetaData);
      } else {
        final Box<MusicMetadata> metadataBox = Hive.box<MusicMetadata>(
          Constants.metadataBoxName,
        );
        if (metadataBox.isEmpty) {
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            final newDirectory = await FilePicker.platform.getDirectoryPath(
              dialogTitle: 'Select Music Directory',
              lockParentWindow: true,
              initialDirectory: ref
                  .read(deviceDirectoryProvider)
                  .requireValue
                  .musicFolderPath,
            );
            if (newDirectory != null) {
              final result = await compute(
                ref
                    .read(metadataReaderRepositoryProvider)
                    .extractMetadataFromDirectory,
                newDirectory,
              );
              await metadataBox.addAll(result);
              return UnmodifiableListView(result);
            } else {
              return UnmodifiableListView([]);
            }
          } else if (Platform.isIOS) {
            await importLocalAudioFiles();
            return UnmodifiableListView(metadataBox.values);
          } else {
            final OnAudioQuery audioQuery = OnAudioQuery();
            final queriedSongs = await audioQuery.querySongs();

            final result = await compute(
              ref
                  .read(metadataReaderRepositoryProvider)
                  .extractMetadataFromFiles,
              queriedSongs.map((e) => e.data).toList(growable: false),
            );
            await metadataBox.addAll(result);
            return UnmodifiableListView(result);
          }
        } else {
          return UnmodifiableListView(metadataBox.values);
        }
      }
    } catch (e) {
      debugPrint('Audio Files Error: $e');
      return UnmodifiableListView([]);
    }
  }

  Future<int> importLocalAudioFiles() async {
    if (!Platform.isIOS) {
      return 0;
    }

    final pickedFiles = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      dialogTitle: 'Pick Song Files',
      type: FileType.custom,
      allowedExtensions: _importableExtensions,
      withData: false,
      allowCompression: false,
    );

    if (pickedFiles == null || pickedFiles.files.isEmpty) {
      return 0;
    }

    final documentsDirectory = ref
        .read(deviceDirectoryProvider)
        .requireValue
        .documentsDirectory;
    final importsDirectory = Directory(
      '${documentsDirectory.path}/ClassiPod/imports',
    );
    importsDirectory.createSync(recursive: true);

    final selectedSidecarsByStem = <String, List<String>>{};
    for (final file in pickedFiles.files) {
      final sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        continue;
      }
      if (!_isLyricsSidecar(sourcePath)) {
        continue;
      }
      final stem = _normalizedStem(file.name.isEmpty ? sourcePath : file.name);
      selectedSidecarsByStem.putIfAbsent(stem, () => []).add(sourcePath);
    }

    final metadataReaderRepository = ref.read(metadataReaderRepositoryProvider);
    final List<String> importedAudioPaths = [];
    for (final file in pickedFiles.files) {
      final sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        continue;
      }
      if (!metadataReaderRepository.isSupportedAudioFormat(sourcePath)) {
        continue;
      }
      final displayName = file.name.isEmpty ? sourcePath.split('/').last : file.name;
      final destinationPath = _uniqueImportedPath(
        importsDirectory.path,
        displayName,
      );
      final copied = await File(sourcePath).copy(destinationPath);
      await _copyLyricsSidecarsForAudio(
        sourceAudioPath: sourcePath,
        sourceDisplayName: displayName,
        destinationAudioPath: copied.path,
        selectedSidecarsByStem: selectedSidecarsByStem,
      );
      importedAudioPaths.add(copied.path);
    }

    if (importedAudioPaths.isEmpty) {
      return 0;
    }

    final rawResult = await compute(
      ref.read(metadataReaderRepositoryProvider).extractMetadataFromFiles,
      importedAudioPaths,
    );
    final metadataBox = Hive.box<MusicMetadata>(Constants.metadataBoxName);
    final existingPaths = metadataBox.values
        .map((metadata) => metadata.filePath)
        .whereType<String>()
        .toSet();
    final startIndex = metadataBox.length;
    final List<MusicMetadata> importedMetadata = [];
    for (final metadata in rawResult) {
      if (metadata.filePath == null || existingPaths.contains(metadata.filePath)) {
        continue;
      }
      importedMetadata.add(
        metadata.copyWith(
          originalSongIndex: startIndex + importedMetadata.length,
        ),
      );
    }

    await metadataBox.addAll(importedMetadata);
    state = AsyncData(UnmodifiableListView(metadataBox.values));
    return importedMetadata.length;
  }

  Future<void> _copyLyricsSidecarsForAudio({
    required String sourceAudioPath,
    required String sourceDisplayName,
    required String destinationAudioPath,
    required Map<String, List<String>> selectedSidecarsByStem,
  }) async {
    final destinationStem = _pathWithoutExtension(destinationAudioPath);
    final sourceStem = _pathWithoutExtension(sourceAudioPath);
    final selectedStem = _normalizedStem(sourceDisplayName);
    final candidatePaths = <String>{
      '$sourceStem.lrc',
      '$sourceStem.txt',
      ...?selectedSidecarsByStem[selectedStem],
    };

    for (final sidecarPath in candidatePaths) {
      if (!_isLyricsSidecar(sidecarPath)) {
        continue;
      }
      final source = File(sidecarPath);
      if (!source.existsSync()) {
        continue;
      }
      try {
        final extension = _extensionOf(sidecarPath);
        await source.copy('$destinationStem.$extension');
      } catch (e) {
        debugPrint('Lyrics Import Error: $e');
      }
    }
  }

  String _uniqueImportedPath(String directoryPath, String rawName) {
    final sanitized = rawName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fileName = sanitized.isEmpty ? 'Imported Song' : sanitized;
    final dot = fileName.lastIndexOf('.');
    final baseName = dot > 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot > 0 ? fileName.substring(dot) : '';
    var candidate = '$directoryPath/$fileName';
    var index = 2;
    while (File(candidate).existsSync()) {
      candidate = '$directoryPath/$baseName $index$extension';
      index++;
    }
    return candidate;
  }

  bool _isLyricsSidecar(String path) {
    final extension = _extensionOf(path);
    return extension == 'lrc' || extension == 'txt';
  }

  String _normalizedStem(String pathOrName) {
    final fileName = pathOrName.replaceAll('\\', '/').split('/').last;
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    return stem.trim().toLowerCase();
  }

  String _extensionOf(String path) {
    final fileName = path.replaceAll('\\', '/').split('/').last;
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  String _pathWithoutExtension(String path) {
    final dot = path.lastIndexOf('.');
    final slash = path.replaceAll('\\', '/').lastIndexOf('/');
    if (dot <= slash) {
      return path;
    }
    return path.substring(0, dot);
  }
}
