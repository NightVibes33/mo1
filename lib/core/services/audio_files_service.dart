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

class ImportLocalAudioResult {
  final int importedCount;
  final int duplicateCount;
  final int skippedCount;

  const ImportLocalAudioResult({
    required this.importedCount,
    required this.duplicateCount,
    required this.skippedCount,
  });

  const ImportLocalAudioResult.empty()
    : importedCount = 0,
      duplicateCount = 0,
      skippedCount = 0;

  bool get hasImportedSongs => importedCount > 0;
  bool get hasActivity =>
      importedCount > 0 || duplicateCount > 0 || skippedCount > 0;

  String get title {
    if (importedCount > 0) {
      return 'Import Complete';
    }
    if (duplicateCount > 0) {
      return 'Already Imported';
    }
    return 'No Songs Imported';
  }

  String get message {
    final parts = <String>[];
    if (importedCount > 0) {
      parts.add('$importedCount song${importedCount == 1 ? '' : 's'} imported');
    }
    if (duplicateCount > 0) {
      parts.add('$duplicateCount duplicate${duplicateCount == 1 ? '' : 's'} skipped');
    }
    if (skippedCount > 0) {
      parts.add('$skippedCount unsupported file${skippedCount == 1 ? '' : 's'} skipped');
    }
    return parts.isEmpty ? 'Pick MP3, M4A, FLAC, WAV, OGG, OPUS, LRC, or TXT files.' : parts.join('\n');
  }
}

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

  Future<ImportLocalAudioResult> importLocalAudioFiles() async {
    if (!Platform.isIOS) {
      return const ImportLocalAudioResult.empty();
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
      return const ImportLocalAudioResult.empty();
    }

    final documentsDirectory = ref
        .read(deviceDirectoryProvider)
        .requireValue
        .documentsDirectory;
    final importsDirectory = Directory(
      '${documentsDirectory.path}/ClassiPod/imports',
    );
    importsDirectory.createSync(recursive: true);

    final metadataBox = Hive.box<MusicMetadata>(Constants.metadataBoxName);
    final existingFingerprints = <String>{};
    for (final metadata in metadataBox.values) {
      final fingerprint = _fingerprintForExistingFile(metadata.filePath);
      if (fingerprint != null) {
        existingFingerprints.add(fingerprint);
      }
    }

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
    final selectedFingerprints = <String>{};
    var duplicateCount = 0;
    var skippedCount = 0;

    for (final file in pickedFiles.files) {
      final sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        skippedCount++;
        continue;
      }
      if (_isLyricsSidecar(sourcePath)) {
        continue;
      }
      if (!metadataReaderRepository.isSupportedAudioFormat(sourcePath)) {
        skippedCount++;
        continue;
      }

      final displayName = file.name.isEmpty
          ? sourcePath.replaceAll('\\', '/').split('/').last
          : file.name;
      final sourceFile = File(sourcePath);
      final int byteLength;
      try {
        if (!sourceFile.existsSync()) {
          skippedCount++;
          continue;
        }
        byteLength = sourceFile.lengthSync();
      } catch (_) {
        skippedCount++;
        continue;
      }

      final fingerprint = _fileFingerprint(displayName, byteLength);
      if (existingFingerprints.contains(fingerprint) ||
          !selectedFingerprints.add(fingerprint)) {
        duplicateCount++;
        continue;
      }

      final destinationPath = _uniqueImportedPath(
        importsDirectory.path,
        displayName,
      );
      final copied = await sourceFile.copy(destinationPath);
      await _copyLyricsSidecarsForAudio(
        sourceAudioPath: sourcePath,
        sourceDisplayName: displayName,
        destinationAudioPath: copied.path,
        selectedSidecarsByStem: selectedSidecarsByStem,
      );
      importedAudioPaths.add(copied.path);
      existingFingerprints.add(fingerprint);
    }

    if (importedAudioPaths.isEmpty) {
      state = AsyncData(UnmodifiableListView(metadataBox.values));
      return ImportLocalAudioResult(
        importedCount: 0,
        duplicateCount: duplicateCount,
        skippedCount: skippedCount,
      );
    }

    final rawResult = await compute(
      ref.read(metadataReaderRepositoryProvider).extractMetadataFromFiles,
      importedAudioPaths,
    );
    skippedCount += importedAudioPaths.length - rawResult.length;

    final existingPaths = metadataBox.values
        .map((metadata) => metadata.filePath)
        .whereType<String>()
        .toSet();
    final startIndex = metadataBox.length;
    final List<MusicMetadata> importedMetadata = [];
    for (final metadata in rawResult) {
      if (metadata.filePath == null || existingPaths.contains(metadata.filePath)) {
        duplicateCount++;
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
    return ImportLocalAudioResult(
      importedCount: importedMetadata.length,
      duplicateCount: duplicateCount,
      skippedCount: skippedCount,
    );
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
    return stem
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  String _fileFingerprint(String pathOrName, int byteLength) {
    return '${_normalizedStem(pathOrName)}:$byteLength';
  }

  String? _fingerprintForExistingFile(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      return _fileFingerprint(path, file.lengthSync());
    } catch (_) {
      return null;
    }
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
