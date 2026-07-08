import 'dart:io';

import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/providers/device_directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appDocumentsServiceProvider = Provider<AppDocumentsService>((ref) {
  final deviceDirectory = ref.read(deviceDirectoryProvider).requireValue;
  return AppDocumentsService(deviceDirectory.documentsDirectory);
});

class AppDocumentsService {
  static String? _activeAppDirectoryPath;

  final Directory documentsDirectory;

  AppDocumentsService(this.documentsDirectory) {
    _activeAppDirectoryPath = appDirectory.path.replaceAll('\\', '/');
  }

  Directory get appDirectory => Directory(
    _join(documentsDirectory.path, Constants.appDocumentsFolderName),
  );

  Directory get legacyAppDirectory => Directory(
    _join(documentsDirectory.path, Constants.legacyAppDocumentsFolderName),
  );

  String get appDirectoryPath => appDirectory.path;
  String get importsDirectoryPath =>
      _subdirectoryPath(Constants.importsDirectoryName);
  String get artworkDirectoryPath =>
      _subdirectoryPath(Constants.artworkDirectoryName);
  String get thumbnailsDirectoryPath =>
      _subdirectoryPath(Constants.thumbnailsDirectoryName);
  String get appleMusicArtworkDirectoryPath =>
      _subdirectoryPath(Constants.appleMusicArtworkDirectoryName);
  String get debugLogPath => _join(appDirectory.path, 'debug.log');
  String get crashLogPath => _join(appDirectory.path, 'crash.log');
  String get sessionStatePath => _join(appDirectory.path, 'last-session.json');
  static String? resolveManagedPath(String? path) {
    if (path == null || path.isEmpty) {
      return path;
    }

    final currentPath = _activeAppDirectoryPath;
    if (currentPath == null || currentPath.isEmpty) {
      return path;
    }

    final normalizedPath = path.replaceAll('\\', '/');
    final managedSuffix = _managedAppPathSuffixFor(normalizedPath);
    if (managedSuffix == null) {
      return path;
    }
    return managedSuffix.isEmpty ? currentPath : '$currentPath/$managedSuffix';
  }

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

    for (final path in [debugLogPath, crashLogPath, sessionStatePath]) {
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

    final currentPath = appDirectory.path.replaceAll('\\', '/');
    _activeAppDirectoryPath = currentPath;
    final normalizedPath = path.replaceAll('\\', '/');
    final managedSuffix = _managedAppPathSuffixFor(normalizedPath);
    if (managedSuffix == null) {
      return path;
    }

    return managedSuffix.isEmpty
        ? appDirectory.path
        : '$currentPath/$managedSuffix';
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
      final destinationPath = _join(
        destination.path,
        _lastPathSegment(entity.path),
      );
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

  static String? _managedAppPathSuffixFor(String normalizedPath) {
    for (final marker in [
      '/${Constants.appDocumentsFolderName}',
      '/${Constants.legacyAppDocumentsFolderName}',
    ]) {
      if (normalizedPath == marker.substring(1) ||
          normalizedPath.endsWith(marker)) {
        return '';
      }

      final markerWithSeparator = '$marker/';
      final markerIndex = normalizedPath.indexOf(markerWithSeparator);
      if (markerIndex != -1) {
        return normalizedPath.substring(
          markerIndex + markerWithSeparator.length,
        );
      }
    }
    return null;
  }
}
