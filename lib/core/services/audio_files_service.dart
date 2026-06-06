import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:classipod/core/constants/constants.dart';
import 'package:classipod/core/constants/online_audio_files_metadata.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/device_directory_provider.dart';
import 'package:classipod/core/repositories/metadata_reader_repository.dart';
import 'package:classipod/core/services/debug_log_service.dart';
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

class ImportAppleMusicMetadataResult {
  final int importedCount;
  final int updatedCount;

  const ImportAppleMusicMetadataResult({
    required this.importedCount,
    required this.updatedCount,
  });

  const ImportAppleMusicMetadataResult.empty()
    : importedCount = 0,
      updatedCount = 0;

  int get changedCount => importedCount + updatedCount;
}

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
            await importLocalAudioFiles(updateState: false);
            return _storedMetadata(metadataBox);
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
          return _storedMetadata(metadataBox);
        }
      }
    } catch (e) {
      debugPrint('Audio Files Error: $e');
      return UnmodifiableListView([]);
    }
  }

  UnmodifiableListView<MusicMetadata> _storedMetadata(
    Box<MusicMetadata> metadataBox,
  ) {
    final playableMetadata = <MusicMetadata>[];
    for (final metadata in metadataBox.values) {
      final repairedMetadata = metadata.withFilenameFallbacks();
      if (_isPlayableMetadata(repairedMetadata)) {
        playableMetadata.add(repairedMetadata);
      }
    }
    return UnmodifiableListView(playableMetadata);
  }

  bool _isPlayableMetadata(MusicMetadata metadata) {
    final path = metadata.filePath;
    if (path == null || path.isEmpty) {
      return false;
    }
    if (!metadata.isOnDevice) {
      return true;
    }
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }


  Future<ImportAppleMusicMetadataResult> importAppleMusicMetadata(
    List<MusicMetadata> appleMusicMetadata,
  ) async {
    if (!Hive.isBoxOpen(Constants.metadataBoxName)) {
      return const ImportAppleMusicMetadataResult.empty();
    }

    final metadataBox = Hive.box<MusicMetadata>(Constants.metadataBoxName);
    final existingPathIndexes = <String, int>{};
    final existingSignatureIndexes = <String, int>{};
    for (var index = 0; index < metadataBox.length; index++) {
      final existing = metadataBox.getAt(index);
      final path = existing?.filePath;
      if (path != null && path.isNotEmpty) {
        existingPathIndexes[path] = index;
      }
      if (existing?.isAppleMusicCatalogTrack ?? false) {
        final signature = _appleMusicSignature(existing!);
        if (signature != null) {
          existingSignatureIndexes[signature] = index;
        }
      }
    }

    var importedCount = 0;
    var updatedCount = 0;
    final importedMetadata = <MusicMetadata>[];

    for (final metadata in appleMusicMetadata) {
      final path = metadata.filePath;
      if (path == null || path.isEmpty || !metadata.isAppleMusicCatalogTrack) {
        continue;
      }

      final signature = _appleMusicSignature(metadata);
      final existingIndex =
          existingPathIndexes[path] ??
          (signature == null ? null : existingSignatureIndexes[signature]);
      if (existingIndex != null) {
        final existing = metadataBox.getAt(existingIndex);
        if (existing == null) {
          continue;
        }
        final refreshed = _mergeAppleMusicMetadata(existing, metadata);
        if (refreshed != existing) {
          await metadataBox.putAt(existingIndex, refreshed);
          updatedCount++;
        }
        existingPathIndexes[path] = existingIndex;
        if (signature != null) {
          existingSignatureIndexes[signature] = existingIndex;
        }
        continue;
      }

      final imported = metadata.copyWith(
        originalSongIndex: metadataBox.length + importedMetadata.length,
        isOnDevice: false,
      );
      importedMetadata.add(imported);
      final importedIndex = metadataBox.length + importedMetadata.length - 1;
      existingPathIndexes[path] = importedIndex;
      if (signature != null) {
        existingSignatureIndexes[signature] = importedIndex;
      }
      importedCount++;
    }

    if (importedMetadata.isNotEmpty) {
      await metadataBox.addAll(importedMetadata);
    }

    state = AsyncData(_storedMetadata(metadataBox));
    ref.read(debugLogServiceProvider).info(
      'apple_music',
      'Upserted Apple Music library references.',
      data: {'imported': importedCount, 'updated': updatedCount},
    );
    return ImportAppleMusicMetadataResult(
      importedCount: importedCount,
      updatedCount: updatedCount,
    );
  }

  String? _appleMusicSignature(MusicMetadata metadata) {
    final values = [
      metadata.trackName,
      metadata.getTrackArtistNames,
      metadata.albumName,
    ]
        .map((value) => value?.trim().toLowerCase() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (values.length < 2) {
      return null;
    }
    return values.join('|');
  }

  MusicMetadata _mergeAppleMusicMetadata(
    MusicMetadata existing,
    MusicMetadata incoming,
  ) {
    return existing.copyWith(
      trackName: incoming.trackName,
      trackArtistNames: incoming.trackArtistNames,
      albumName: incoming.albumName,
      albumArtistName: incoming.albumArtistName,
      trackNumber: incoming.trackNumber,
      albumLength: incoming.albumLength,
      year: incoming.year,
      genres: incoming.genres.isEmpty ? existing.genres : incoming.genres,
      discNumber: incoming.discNumber,
      trackDuration: incoming.trackDuration,
      filePath: incoming.filePath,
      thumbnailPath: _mergedAppleMusicThumbnailPath(existing, incoming),
      isOnDevice: false,
      lyrics: incoming.lyrics,
    );
  }

  String? _mergedAppleMusicThumbnailPath(
    MusicMetadata existing,
    MusicMetadata incoming,
  ) {
    final existingPath = existing.thumbnailPath;
    if (existingPath != null && _isUserManagedArtworkPath(existingPath)) {
      return existingPath;
    }
    return incoming.thumbnailPath ?? existing.thumbnailPath;
  }

  bool _isUserManagedArtworkPath(String path) {
    return path.contains('/ClassiPod/artwork/');
  }

  Future<ImportLocalAudioResult> importLocalAudioFiles({
    bool updateState = true,
  }) async {
    if (!Platform.isIOS) {
      return const ImportLocalAudioResult.empty();
    }

    try {
      return await _importLocalAudioFiles(updateState: updateState);
    } catch (error, stackTrace) {
      ref.read(debugLogServiceProvider).error(
        'import',
        'Fatal import error',
        error: error,
        stackTrace: stackTrace,
      );
      debugPrint('Audio Import Fatal Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (updateState && Hive.isBoxOpen(Constants.metadataBoxName)) {
        final metadataBox = Hive.box<MusicMetadata>(Constants.metadataBoxName);
        state = AsyncData(_storedMetadata(metadataBox));
      }
      return const ImportLocalAudioResult(
        importedCount: 0,
        duplicateCount: 0,
        skippedCount: 1,
      );
    }
  }

  Future<ImportLocalAudioResult> _importLocalAudioFiles({
    required bool updateState,
  }) async {
    final debugLogService = ref.read(debugLogServiceProvider);
    debugLogService.info('import', 'Opening file picker');
    final pickedFiles = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      dialogTitle: 'Pick Song Files',
      type: FileType.custom,
      allowedExtensions: _importableExtensions,
      withData: false,
      allowCompression: false,
    );

    if (pickedFiles == null || pickedFiles.files.isEmpty) {
      debugLogService.info('import', 'File picker cancelled');
      return const ImportLocalAudioResult.empty();
    }

    debugLogService.info(
      'import',
      'Files selected',
      data: {'count': pickedFiles.files.length},
    );

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
    final importedDisplayNamesByPath = <String, String>{};
    final List<String> importedAudioPaths = [];
    final selectedFingerprints = <String>{};
    var duplicateCount = 0;
    var skippedCount = 0;

    for (final file in pickedFiles.files) {
      final sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        skippedCount++;
        debugLogService.warning('import', 'Skipped file with empty source path');
        continue;
      }
      if (_isLyricsSidecar(sourcePath)) {
        continue;
      }
      if (!metadataReaderRepository.isSupportedAudioFormat(sourcePath)) {
        skippedCount++;
        debugLogService.warning(
          'import',
          'Skipped unsupported file',
          data: {'path': sourcePath},
        );
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
          debugLogService.warning(
            'import',
            'Skipped missing source file',
            data: {'path': sourcePath, 'name': displayName},
          );
          continue;
        }
        byteLength = sourceFile.lengthSync();
      } catch (error) {
        skippedCount++;
        debugLogService.error(
          'import',
          'Skipped unreadable source file',
          error: error,
          data: {'path': sourcePath, 'name': displayName},
        );
        continue;
      }

      final fingerprint = _fileFingerprint(displayName, byteLength);
      if (existingFingerprints.contains(fingerprint) ||
          !selectedFingerprints.add(fingerprint)) {
        duplicateCount++;
        debugLogService.info(
          'import',
          'Skipped duplicate file',
          data: {'name': displayName, 'bytes': byteLength},
        );
        continue;
      }

      final destinationPath = _uniqueImportedPath(
        importsDirectory.path,
        displayName,
      );
      try {
        final copied = await sourceFile.copy(destinationPath);
        await _copyLyricsSidecarsForAudio(
          sourceAudioPath: sourcePath,
          sourceDisplayName: displayName,
          destinationAudioPath: copied.path,
          selectedSidecarsByStem: selectedSidecarsByStem,
        );
        importedAudioPaths.add(copied.path);
        importedDisplayNamesByPath[copied.path] = displayName;
        existingFingerprints.add(fingerprint);
        debugLogService.info(
          'import',
          'Copied import file',
          data: {
            'source': sourcePath,
            'destination': copied.path,
            'displayName': displayName,
            'bytes': byteLength,
          },
        );
      } catch (error, stackTrace) {
        skippedCount++;
        debugLogService.error(
          'import',
          'Audio import copy failed',
          error: error,
          stackTrace: stackTrace,
          data: {'source': sourcePath, 'displayName': displayName},
        );
        debugPrint('Audio Import Copy Error: $error');
      }
    }

    if (importedAudioPaths.isEmpty) {
      if (updateState) {
        state = AsyncData(_storedMetadata(metadataBox));
      }
      debugLogService.info(
        'import',
        'Import finished with no copied audio files',
        data: {'duplicates': duplicateCount, 'skipped': skippedCount},
      );
      return ImportLocalAudioResult(
        importedCount: 0,
        duplicateCount: duplicateCount,
        skippedCount: skippedCount,
      );
    }

    debugLogService.info(
      'import',
      'Extracting imported metadata',
      data: {'count': importedAudioPaths.length},
    );
    final rawResult = await compute(
      metadataReaderRepository.extractMetadataFromFilesWithDisplayNames,
      importedDisplayNamesByPath,
    );
    skippedCount += importedAudioPaths.length - rawResult.length;

    final existingPaths = metadataBox.values
        .map((metadata) => metadata.filePath)
        .whereType<String>()
        .toSet();
    final startIndex = metadataBox.length;
    final List<MusicMetadata> importedMetadata = [];
    for (final metadata in rawResult) {
      if (metadata.filePath == null ||
          existingPaths.contains(metadata.filePath) ||
          !_isPlayableMetadata(metadata)) {
        duplicateCount++;
        continue;
      }
      final repairedMetadata = metadata.copyWith(
        originalSongIndex: startIndex + importedMetadata.length,
      );
      importedMetadata.add(repairedMetadata);
      debugLogService.info(
        'import',
        'Imported metadata ready',
        data: {
          'title': repairedMetadata.trackName,
          'artist': repairedMetadata.getTrackArtistNames,
          'album': repairedMetadata.albumName,
          'path': repairedMetadata.filePath,
          'originalSongIndex': repairedMetadata.originalSongIndex,
        },
      );
    }

    await metadataBox.addAll(importedMetadata);
    if (updateState) {
      state = AsyncData(_storedMetadata(metadataBox));
    }
    debugLogService.info(
      'import',
      'Import finished',
      data: {
        'imported': importedMetadata.length,
        'duplicates': duplicateCount,
        'skipped': skippedCount,
      },
    );
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
        ref.read(debugLogServiceProvider).error(
          'import',
          'Lyrics sidecar copy failed',
          error: e,
          data: {'sidecarPath': sidecarPath, 'destinationStem': destinationStem},
        );
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
