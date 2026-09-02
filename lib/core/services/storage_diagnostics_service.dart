import 'dart:io';

import 'package:dopi/core/services/app_documents_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final storageDiagnosticsServiceProvider = Provider<StorageDiagnosticsService>((ref) {
  return StorageDiagnosticsService(ref.read(appDocumentsServiceProvider));
});

class StorageDiagnosticsService {
  final AppDocumentsService _documents;

  const StorageDiagnosticsService(this._documents);

  Future<StorageDiagnosticsSnapshot> snapshot() async {
    final tempDirectory = await getTemporaryDirectory();
    final entries = <StorageDiagnosticsEntry>[
      await _entry('App Data', Directory(_documents.appDirectoryPath)),
      await _entry('Imports', Directory(_documents.importsDirectoryPath)),
      await _entry('Artwork', Directory(_documents.artworkDirectoryPath)),
      await _entry('Thumbnails', Directory(_documents.thumbnailsDirectoryPath)),
      await _entry(
        'Apple Music Artwork',
        Directory(_documents.appleMusicArtworkDirectoryPath),
      ),
      await _entry('Native EQ Cache', Directory('${tempDirectory.path}/dope_native_eq_cache')),
      await _fileEntry('Debug Log', File(_documents.debugLogPath)),
      await _fileEntry('Crash Log', File(_documents.crashLogPath)),
    ];
    final totalBytes = entries.fold<int>(0, (total, entry) => total + entry.bytes);
    return StorageDiagnosticsSnapshot(entries: entries, totalBytes: totalBytes);
  }

  Future<void> clearNativeEqCache() async {
    final tempDirectory = await getTemporaryDirectory();
    final directory = Directory('${tempDirectory.path}/dope_native_eq_cache');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<StorageDiagnosticsEntry> _entry(String label, Directory directory) async {
    if (!await directory.exists()) {
      return StorageDiagnosticsEntry(label: label, bytes: 0, path: directory.path);
    }
    var bytes = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          bytes += await entity.length();
        } catch (_) {}
      }
    }
    return StorageDiagnosticsEntry(label: label, bytes: bytes, path: directory.path);
  }

  Future<StorageDiagnosticsEntry> _fileEntry(String label, File file) async {
    final bytes = await file.exists() ? await file.length() : 0;
    return StorageDiagnosticsEntry(label: label, bytes: bytes, path: file.path);
  }
}

class StorageDiagnosticsSnapshot {
  final List<StorageDiagnosticsEntry> entries;
  final int totalBytes;

  const StorageDiagnosticsSnapshot({required this.entries, required this.totalBytes});
}

class StorageDiagnosticsEntry {
  final String label;
  final int bytes;
  final String path;

  const StorageDiagnosticsEntry({
    required this.label,
    required this.bytes,
    required this.path,
  });

  String get displaySize => formatBytes(bytes);
}

String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(1)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}
