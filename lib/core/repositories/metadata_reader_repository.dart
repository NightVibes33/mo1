import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/device_directory_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final metadataReaderRepositoryProvider =
    Provider.autoDispose<MetadataReaderRepository>((ref) {
      final documentsDirectory = ref
          .read(deviceDirectoryProvider)
          .requireValue
          .documentsDirectory;
      final thumbnailsDirectoryPath =
          '${documentsDirectory.path}/ClassiPod/thumbnails';
      Directory(thumbnailsDirectoryPath).createSync(recursive: true);
      return MetadataReaderRepository(thumbnailsDirectoryPath);
    });

class MetadataReaderRepository {
  final String thumbnailsDirectoryPath;

  MetadataReaderRepository(this.thumbnailsDirectoryPath);

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
    final List<MusicMetadata> metadataList = [];

    for (final String path in filePaths) {
      final metadata = _extractMetadataFromPath(path, metadataList.length);
      if (metadata != null) {
        metadataList.add(metadata);
      }
    }

    return UnmodifiableListView(metadataList);
  }

  MusicMetadata? _extractMetadataFromPath(String path, int originalSongIndex) {
    if (!isSupportedAudioFormat(path)) {
      return null;
    }

    try {
      final audioMetadata = readMetadata(File(path), getImage: true);
      String? thumbnailPath;

      if (audioMetadata.pictures.isNotEmpty) {
        thumbnailPath = getThumbnailPath(
          albumName: audioMetadata.album,
          artistName: audioMetadata.artist,
          filePath: path,
        );
        File(thumbnailPath).writeAsBytesSync(audioMetadata.pictures[0].bytes);
      }

      return MusicMetadata.fromAudioMetadata(
        audioMetadata,
        thumbnailPath,
        originalSongIndex,
        fallbackLyrics: _readSidecarLyrics(path),
      );
    } catch (e) {
      debugPrint('Metadata Parsing Error: $e');
      return null;
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
