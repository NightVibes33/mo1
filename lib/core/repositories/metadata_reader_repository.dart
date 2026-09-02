import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/services/app_documents_service.dart';
import 'package:dopi/core/services/debug_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final metadataReaderRepositoryProvider =
    Provider.autoDispose<MetadataReaderRepository>((ref) {
      final appDocumentsService = ref.read(appDocumentsServiceProvider);
      final thumbnailsDirectoryPath = appDocumentsService.thumbnailsDirectoryPath;
      Directory(thumbnailsDirectoryPath).createSync(recursive: true);
      return MetadataReaderRepository(
        thumbnailsDirectoryPath,
        ref.read(debugLogServiceProvider),
      );
    });

class MetadataReaderRepository {
  final String thumbnailsDirectoryPath;
  final DebugLogService? debugLogService;

  MetadataReaderRepository(this.thumbnailsDirectoryPath, [this.debugLogService]);

  bool isSupportedAudioFormat(String path) {
    final lowerPath = path.toLowerCase();
    return supportedFileExtensions.any(
      (extension) => lowerPath.endsWith(extension.toLowerCase()),
    );
  }

  String getThumbnailPath({
    required String? albumName,
    required String? artistName,
    required String filePath,
  }) {
    final String? normalizedAlbumName = normalizeMetadataString(albumName);
    final String? normalizedArtistName = normalizeMetadataString(artistName);
    String albumArtFileName;
    if (normalizedAlbumName == null || normalizedArtistName == null) {
      albumArtFileName = filePath;
    } else {
      albumArtFileName = '${normalizedAlbumName}by$normalizedArtistName';
    }
    albumArtFileName = albumArtFileName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('/', '-')
        .replaceAll(' ', '');
    return '$thumbnailsDirectoryPath/$albumArtFileName.jpg';
  }

  UnmodifiableListView<MusicMetadata> extractMetadataFromDirectory(
    String musicFolderPath,
  ) {
    final Directory storageDir = Directory(musicFolderPath);
    final List<FileSystemEntity> files = storageDir.listSync(
      recursive: true,
      followLinks: false,
    );
    final List<String> filePaths = files.map((e) => e.path).toList();

    return extractMetadataFromFiles(filePaths);
  }

  UnmodifiableListView<MusicMetadata> extractMetadataFromFiles(
    List<String> filePaths,
  ) {
    final displayNamesByPath = {for (final path in filePaths) path: null};
    return extractMetadataFromFilesWithDisplayNames(displayNamesByPath);
  }

  UnmodifiableListView<MusicMetadata> extractMetadataFromFilesWithDisplayNames(
    Map<String, String?> displayNamesByPath,
  ) {
    final List<MusicMetadata> metadataList = [];

    for (final entry in displayNamesByPath.entries) {
      final metadata = _extractMetadataFromPath(
        entry.key,
        metadataList.length,
        fallbackFileName: entry.value,
      );
      if (metadata != null) {
        metadataList.add(
          metadata.filePath == entry.key
              ? metadata
              : metadata.copyWith(filePath: entry.key),
        );
      }
    }

    return UnmodifiableListView(metadataList);
  }

  MusicMetadata? _extractMetadataFromPath(
    String path,
    int originalSongIndex, {
    String? fallbackFileName,
  }) {
    if (!isSupportedAudioFormat(path)) {
      return null;
    }

    final fallbackLyrics = _readSidecarLyrics(path);

    try {
      final audioMetadata = readMetadata(File(path), getImage: true);
      String? thumbnailPath;

      if (audioMetadata.pictures.isNotEmpty) {
        thumbnailPath = getThumbnailPath(
          albumName: audioMetadata.album,
          artistName: audioMetadata.artist,
          filePath: path,
        );
        try {
          File(thumbnailPath).writeAsBytesSync(audioMetadata.pictures[0].bytes);
        } catch (e) {
          debugPrint('Album Art Write Error: $e');
          debugLogService?.error(
            'metadata',
            'Album art write failed',
            error: e,
            data: {'path': path, 'thumbnailPath': thumbnailPath},
          );
          thumbnailPath = null;
        }
      }

      return MusicMetadata.fromAudioMetadata(
        audioMetadata,
        thumbnailPath,
        originalSongIndex,
        fallbackLyrics: fallbackLyrics,
        fallbackFileName: fallbackFileName,
      );
    } catch (e) {
      debugPrint('Metadata Parsing Error: $e');
      debugLogService?.error(
        'metadata',
        'Metadata parser failed; using filename fallback',
        error: e,
        data: {'path': path, 'fallbackFileName': fallbackFileName},
      );
      return MusicMetadata.fromFilePathFallback(
        path,
        originalSongIndex,
        fallbackLyrics: fallbackLyrics,
        fallbackFileName: fallbackFileName,
      );
    }
  }

  String? _readSidecarLyrics(String audioPath) {
    final pathWithoutExtension = _pathWithoutExtension(audioPath);
    for (final extension in const ['.lrc', '.txt']) {
      final sidecar = File('$pathWithoutExtension$extension');
      try {
        if (!sidecar.existsSync()) {
          continue;
        }
        final size = sidecar.lengthSync();
        if (size == 0 || size > 512 * 1024) {
          continue;
        }
        return utf8.decode(sidecar.readAsBytesSync(), allowMalformed: true);
      } catch (e) {
        debugPrint('Lyrics Sidecar Error: $e');
        debugLogService?.error(
          'metadata',
          'Lyrics sidecar read failed',
          error: e,
          data: {'path': audioPath},
        );
      }
    }
    return null;
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
