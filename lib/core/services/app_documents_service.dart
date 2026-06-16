import 'dart:io';

import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/providers/device_directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appDocumentsServiceProvider = Provider<AppDocumentsService>((ref) {
  final deviceDirectory = ref.read(deviceDirectoryProvider).requireValue;
  return AppDocumentsService(deviceDirectory.documentsDirectory);
});

class AppDocumentsService {
  final Directory documentsDirectory;

  const AppDocumentsService(this.documentsDirectory);

  Directory get appDirectory => Directory(
        _join(documentsDirectory.path, Constants.appDocumentsFolderName),
      );

  Directory get legacyAppDirectory => Directory(
        _join(documentsDirectory.path, Constants.legacyAppDocumentsFolderName),
      );

  String get appDirectoryPath => appDirectory.path;
  String get importsDirectoryPath => _subdirectoryPath(Constants.importsDirectoryName);
  String get artworkDirectoryPath => _subdirectoryPath(Constants.artworkDirectoryName);
  String get thumbnailsDirectoryPath => _subdirectoryPath(Constants.thumbnailsDirectoryName);
  String get appleMusicArtworkDirectoryPath =>
      _subdirectoryPath(Constants.appleMusicArtworkDirectoryName);
  String get debugLogPath => _join(appDirectory.path, 'debug.log');
  String get crashLogPath => _join(appDirectory.path, 'crash.log');
  String get sessionStatePath => _join(appDirectory.path, 'last-session.json');

  Future<void> migrateLegacyStorage() async {
    final legacyDirectory = legacyAppDirectory;
    if (!await legacyDirectory.exists()) {
      await ensureDirectories();
      return;
    }

    final currentDirectory = appDirectory;
    if (!await currentDirectory.exists()) {
      try {
        await legacyDirectory.rename(currentDirectory.path);
      } catch (_) {
        await _mergeDirectoryContents(legacyDirectory, currentDirectory);
        await _deleteDirectoryIfExists(legacyDirectory);
      }
    } else {
      await _mergeDirectoryContents(legacyDirectory, currentDirectory);
      await _deleteDirectoryIfExists(legacyDirectory);
    }

    await ensureDirectories();
  }

  Future<void> ensureDirectories() async {
    for (final path in [
      appDirectoryPath,
      importsDirectoryPath,
      artworkDirectoryPath,
      thumbnailsDirectoryPath,
      appleMusicArtworkDirectoryPath,
    ]) {
      await Directory(path).create(recursive: true);
    }
  }

  Future<void> deleteUserContent() async {
    for (final path in [
      importsDirectoryPath,
      artworkDirectoryPath,
      thumbnailsDirectoryPath,
      appleMusicArtworkDirectoryPath,
    ]) {
      final directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }

    for (final path in [
      debugLogPath,
      crashLogPath,
      sessionStatePath,
    ]) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    final legacyDirectory = legacyAppDirectory;
    if (await legacyDirectory.exists()) {
      await legacyDirectory.delete(recursive: true);
    }

    await ensureDirectories();
  }

  String? migrateLegacyPath(String? path) {
    if (path == null || path.isEmpty) {
      return path;
    }

    final legacyPath = legacyAppDirectory.path.replaceAll('\\', '/');
    final currentPath = appDirectory.path.replaceAll('\\', '/');
    final normalizedPath = path.replaceAll('\\', '/');
    if (normalizedPath == legacyPath) {
      return appDirectory.path;
    }
    if (normalizedPath.startsWith('$legacyPath/')) {
      return '$currentPath${normalizedPath.substring(legacyPath.length)}';
    }
    return path;
  }

  String _subdirectoryPath(String subdirectoryName) {
    return _join(appDirectory.path, subdirectoryName);
  }

  static String _join(String left, String right) {
    if (left.endsWith('/')) {
      return '$left$right';
    }
    return '$left/$right';
  }

  Future<void> _mergeDirectoryContents(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final destinationPath = _join(destination.path, _lastPathSegment(entity.path));
      if (entity is Directory) {
        final destinationDirectory = Directory(destinationPath);
        if (!await destinationDirectory.exists()) {
          try {
            await entity.rename(destinationPath);
            continue;
          } catch (_) {
            // Fall through to recursive merge.
          }
        }
        await _mergeDirectoryContents(entity, destinationDirectory);
        await _deleteDirectoryIfExists(entity);
      } else if (entity is File) {
        final destinationFile = File(destinationPath);
        if (!await destinationFile.exists()) {
          try {
            await entity.rename(destinationPath);
          } catch (_) {
            await entity.copy(destinationPath);
            await entity.delete();
          }
        } else {
          await entity.delete();
        }
      }
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  String _lastPathSegment(String path) {
    final normalizedPath = path.replaceAll('\\', '/');
    final slashIndex = normalizedPath.lastIndexOf('/');
    return slashIndex == -1
        ? normalizedPath
        : normalizedPath.substring(slashIndex + 1);
  }
}
