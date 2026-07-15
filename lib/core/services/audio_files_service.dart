import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/constants/online_audio_files_metadata.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/providers/device_directory_provider.dart';
import 'package:dope/core/services/app_documents_service.dart';
import 'package:dope/core/repositories/metadata_reader_repository.dart';
import 'package:dope/core/services/debug_log_service.dart';
import 'package:dope/core/services/music_metadata_lookup_service.dart';
import 'package:dope/features/music/playlist/models/playlist_model.dart' as playlist_models;
import 'package:dope/features/music/songs/models/music_metadata_match.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:crypto/crypto.dart';
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
      parts.add(
        '$duplicateCount duplicate${duplicateCount == 1 ? '' : 's'} skipped',
      );
    }
    if (skippedCount > 0) {
      parts.add(
        '$skippedCount unsupported file${skippedCount == 1 ? '' : 's'} skipped',
      );
    }
    return parts.isEmpty
        ? 'Pick MP3, M4A, FLAC, WAV, OGG, OPUS, LRC, or TXT files.'
        : parts.join('\n');
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

  void clearLibraryState() {
    state = AsyncData(UnmodifiableListView<MusicMetadata>(const []));
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
            return UnmodifiableListView([]);
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
          await _repairStoredLocalAddedDates(metadataBox);
          await _repairStoredLocalDurations(metadataBox);
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

  Future<void> _repairStoredLocalAddedDates(
    Box<MusicMetadata> metadataBox,
  ) async {
    final repairedDatesByPath = <String, int>{};
    var repairedCount = 0;
    for (var index = 0; index < metadataBox.length; index++) {
      final metadata = metadataBox.getAt(index);
      final path = metadata?.filePath;
      final importedAt = metadata?.importedAtEpochMs;
      if (metadata == null ||
          path == null ||
          path.isEmpty ||
          importedAt == null ||
          !metadata.isOnDevice ||
          metadata.isAppleMusicCatalogTrack ||
          path.startsWith('applemusic://')) {
        continue;
      }
      if (metadata.sourceCreatedAtEpochMs == importedAt &&
          metadata.sourceModifiedAtEpochMs == importedAt) {
        continue;
      }
      await metadataBox.putAt(
        index,
        metadata.copyWith(
          sourceCreatedAtEpochMs: importedAt,
          sourceModifiedAtEpochMs: importedAt,
        ),
      );
      repairedDatesByPath[path] = importedAt;
      repairedCount++;
    }

    if (repairedDatesByPath.isNotEmpty &&
        Hive.isBoxOpen(Constants.playlistBoxName)) {
      await _repairPlaylistLocalAddedDates(repairedDatesByPath);
    }

    if (repairedCount > 0) {
      ref.read(debugLogServiceProvider).info(
        'import',
        'Repaired stored local audio date-added order.',
        data: {'repaired': repairedCount},
      );
    }
  }

  Future<void> _repairPlaylistLocalAddedDates(
    Map<String, int> addedDatesByPath,
  ) async {
    final playlistBox = Hive.box<playlist_models.PlaylistModel>(
      Constants.playlistBoxName,
    );
    var repairedPlaylists = 0;
    for (var index = 0; index < playlistBox.length; index++) {
      final playlist = playlistBox.getAt(index);
      if (playlist == null) {
        continue;
      }

      var changed = false;
      final repairedSongs = playlist.songs.map((song) {
        final path = song.filePath;
        final importedAt = path == null ? null : addedDatesByPath[path];
        if (importedAt == null ||
            (song.sourceCreatedAtEpochMs == importedAt &&
                song.sourceModifiedAtEpochMs == importedAt)) {
          return song;
        }
        changed = true;
        return song.copyWith(
          sourceCreatedAtEpochMs: importedAt,
          sourceModifiedAtEpochMs: importedAt,
        );
      }).toList(growable: false);

      if (changed) {
        await playlistBox.putAt(
          index,
          playlist.copyWith(songs: repairedSongs),
        );
        repairedPlaylists++;
      }
    }

    if (repairedPlaylists > 0) {
      ref.read(debugLogServiceProvider).info(
        'import',
        'Repaired playlist local audio date-added order.',
        data: {'playlists': repairedPlaylists},
      );
    }
  }

  Future<void> _repairStoredLocalDurations(
    Box<MusicMetadata> metadataBox,
  ) async {
    final pathsToRepair = <String>[];
    final seenPaths = <String>{};
    for (final metadata in metadataBox.values) {
      final path = metadata.filePath;
      if (path == null ||
          path.isEmpty ||
          !metadata.isOnDevice ||
          metadata.isAppleMusicCatalogTrack ||
          path.startsWith('applemusic://') ||
          !seenPaths.add(path)) {
        continue;
      }
      try {
        if (File(path).existsSync()) {
          pathsToRepair.add(path);
        }
      } catch (_) {
        continue;
      }
    }

    if (pathsToRepair.isEmpty) {
      return;
    }

    final extractedMetadata = await compute(
      ref.read(metadataReaderRepositoryProvider).extractMetadataFromFiles,
      pathsToRepair,
    );
    final durationsByPath = <String, int>{};
    for (final metadata in extractedMetadata) {
      final path = metadata.filePath;
      final duration = metadata.trackDuration;
      if (path != null && duration != null && duration > 0) {
        durationsByPath[path] = duration;
      }
    }

    if (durationsByPath.isEmpty) {
      return;
    }

    final repairedDurationsByPath = <String, int>{};
    var repairedCount = 0;
    for (var index = 0; index < metadataBox.length; index++) {
      final storedMetadata = metadataBox.getAt(index);
      final path = storedMetadata?.filePath;
      if (storedMetadata == null || path == null) {
        continue;
      }
      final fileDuration = durationsByPath[path];
      if (fileDuration == null) {
        continue;
      }
      final storedDuration = storedMetadata.trackDuration;
      if (storedDuration != null &&
          (storedDuration - fileDuration).abs() <= 1000) {
        continue;
      }
      await metadataBox.putAt(
        index,
        storedMetadata.copyWith(trackDuration: fileDuration),
      );
      repairedDurationsByPath[path] = fileDuration;
      repairedCount++;
    }

    if (repairedDurationsByPath.isNotEmpty &&
        Hive.isBoxOpen(Constants.playlistBoxName)) {
      await _repairPlaylistLocalDurations(repairedDurationsByPath);
    }

    if (repairedCount > 0) {
      ref.read(debugLogServiceProvider).info(
        'import',
        'Repaired stored local audio durations from file metadata.',
        data: {'repaired': repairedCount},
      );
    }
  }

  Future<void> _repairPlaylistLocalDurations(
    Map<String, int> durationsByPath,
  ) async {
    final playlistBox = Hive.box<playlist_models.PlaylistModel>(
      Constants.playlistBoxName,
    );
    var repairedPlaylists = 0;
    for (var index = 0; index < playlistBox.length; index++) {
      final playlist = playlistBox.getAt(index);
      if (playlist == null) {
        continue;
      }

      var changed = false;
      final repairedSongs = playlist.songs.map((song) {
        final path = song.filePath;
        final fileDuration = path == null ? null : durationsByPath[path];
        if (fileDuration == null) {
          return song;
        }
        final storedDuration = song.trackDuration;
        if (storedDuration != null &&
            (storedDuration - fileDuration).abs() <= 1000) {
          return song;
        }
        changed = true;
        return song.copyWith(trackDuration: fileDuration);
      }).toList(growable: false);

      if (changed) {
        await playlistBox.putAt(
          index,
          playlist.copyWith(songs: repairedSongs),
        );
        repairedPlaylists++;
      }
    }

    if (repairedPlaylists > 0) {
      ref.read(debugLogServiceProvider).info(
        'import',
        'Repaired playlist local audio durations from file metadata.',
        data: {'playlists': repairedPlaylists},
      );
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
        importedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
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
    ref
        .read(debugLogServiceProvider)
        .info(
          'apple_music',
          'Upserted Apple Music library references.',
          data: {'imported': importedCount, 'updated': updatedCount},
        );
    return ImportAppleMusicMetadataResult(
      importedCount: importedCount,
      updatedCount: updatedCount,
    );
  }

  Future<bool> deleteSong(MusicMetadata metadata) async {
    if (!Hive.isBoxOpen(Constants.metadataBoxName)) {
      return false;
    }

    final metadataBox = Hive.box<MusicMetadata>(Constants.metadataBoxName);
    final storageIndex = _metadataStorageIndex(metadataBox, metadata);
    if (storageIndex == -1) {
      return false;
    }

    final storedMetadata = metadataBox.getAt(storageIndex);
    if (storedMetadata == null) {
      return false;
    }

    await _deleteManagedAudioFile(storedMetadata);
    await metadataBox.deleteAt(storageIndex);
    state = AsyncData(_storedMetadata(metadataBox));
    ref
        .read(debugLogServiceProvider)
        .info(
          'audio_files',
          'Deleted song from library.',
          data: {
            'trackName': storedMetadata.trackName,
            'artist': storedMetadata.getTrackArtistNames,
            'album': storedMetadata.albumName,
            'filePath': storedMetadata.filePath,
            'isAppleMusic': storedMetadata.isAppleMusicCatalogTrack,
            'isOnDevice': storedMetadata.isOnDevice,
          },
        );
    return true;
  }

  int _metadataStorageIndex(
    Box<MusicMetadata> metadataBox,
    MusicMetadata metadata,
  ) {
    final values = metadataBox.values.toList(growable: false);
    if (values.isEmpty) {
      return -1;
    }

    final sourceIdentityIndex = values.indexWhere(
      (existing) => existing.hasSameSourceIdentity(metadata),
    );
    if (sourceIdentityIndex != -1) {
      return sourceIdentityIndex;
    }

    if (metadata.isAppleMusicCatalogTrack) {
      final signature = _appleMusicSignature(metadata);
      if (signature != null) {
        final appleMusicIndex = values.indexWhere((existing) {
          return existing.isAppleMusicCatalogTrack &&
              _appleMusicSignature(existing) == signature;
        });
        if (appleMusicIndex != -1) {
          return appleMusicIndex;
        }
      }
    }

    final filePath = metadata.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      final filePathIndex = values.indexWhere(
        (existing) => existing.filePath == filePath,
      );
      if (filePathIndex != -1) {
        return filePathIndex;
      }
    }

    final originalIndex = metadata.originalSongIndex;
    if (originalIndex >= 0) {
      final originalIndexMatch = values.indexWhere(
        (existing) => existing.originalSongIndex == originalIndex,
      );
      if (originalIndexMatch != -1) {
        return originalIndexMatch;
      }
    }

    return -1;
  }

  String? _appleMusicSignature(MusicMetadata metadata) {
    final values =
        [metadata.trackName, metadata.getTrackArtistNames, metadata.albumName]
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
      isExplicit: incoming.isExplicit,
      lyrics: incoming.lyrics,
      sourceCreatedAtEpochMs:
          incoming.sourceCreatedAtEpochMs ?? existing.sourceCreatedAtEpochMs,
      sourceModifiedAtEpochMs:
          incoming.sourceModifiedAtEpochMs ?? existing.sourceModifiedAtEpochMs,
      importedAtEpochMs:
          incoming.importedAtEpochMs ?? existing.importedAtEpochMs,
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
    return Constants.isAppSubdirectoryPath(
      path,
      Constants.artworkDirectoryName,
    );
  }

  Future<MusicMetadata> _autoEnhanceImportedMetadata(
    MusicMetadata metadata,
  ) async {
    if (!_shouldAutoLookupMetadata(metadata)) {
      return metadata;
    }

    final query = _metadataLookupQuery(metadata);
    if (query == null) {
      return metadata;
    }

    try {
      final lookupService = ref.read(musicMetadataLookupServiceProvider);
      final matches = <MusicMetadataMatch>[
        ...await lookupService.search(
          source: MusicMetadataSource.itunes,
          query: query,
          limit: 5,
        ),
        ...await lookupService.search(
          source: MusicMetadataSource.deezer,
          query: query,
          limit: 5,
        ),
      ];
      final bestMatch = _bestHighConfidenceMatch(metadata, matches);
      if (bestMatch == null) {
        ref.read(debugLogServiceProvider).info(
          'import',
          'Auto metadata skipped; no high-confidence match.',
          data: {'query': query, 'title': metadata.trackName},
        );
        return metadata;
      }

      String? thumbnailPath;
      try {
        thumbnailPath = await lookupService.cacheArtworkForMatch(
          bestMatch,
          metadata,
        );
      } catch (_) {
        thumbnailPath = null;
      }

      final updated = bestMatch
          .applyTo(
            metadata,
            thumbnailPath: thumbnailPath ?? metadata.thumbnailPath,
          )
          .copyWith(
            trackDuration: metadata.trackDuration,
            sourceCreatedAtEpochMs: metadata.sourceCreatedAtEpochMs,
            sourceModifiedAtEpochMs: metadata.sourceModifiedAtEpochMs,
            importedAtEpochMs: metadata.importedAtEpochMs,
          );
      ref.read(debugLogServiceProvider).info(
        'import',
        'Auto metadata applied.',
        data: {
          'query': query,
          'source': bestMatch.source.name,
          'matchTitle': bestMatch.title,
          'matchArtist': bestMatch.artist,
          'path': metadata.filePath,
          'localDurationMs': metadata.trackDuration,
          'remoteDurationMs': bestMatch.durationMs,
        },
      );
      return updated;
    } catch (error, stackTrace) {
      ref.read(debugLogServiceProvider).warning(
        'import',
        'Auto metadata lookup failed; keeping imported metadata.',
        data: {'error': error, 'stackTrace': stackTrace, 'query': query},
      );
      return metadata;
    }
  }

  bool _shouldAutoLookupMetadata(MusicMetadata metadata) {
    if (metadata.isAppleMusicCatalogTrack || !metadata.isOnDevice) {
      return false;
    }
    final title = metadata.trackName?.trim() ?? '';
    final artist = metadata.getTrackArtistNames?.trim() ?? '';
    final album = metadata.albumName?.trim() ?? '';
    final hasArtwork = (metadata.thumbnailPath?.trim().isNotEmpty ?? false);
    final weakTitle = title.isEmpty || title.toLowerCase().startsWith('unknown');
    final weakArtist = artist.isEmpty || artist.toLowerCase().startsWith('unknown');
    final weakAlbum = album.isEmpty || album.toLowerCase().startsWith('unknown');
    return weakTitle || weakArtist || weakAlbum || !hasArtwork;
  }

  String? _metadataLookupQuery(MusicMetadata metadata) {
    final title = _cleanLookupTerm(metadata.trackName);
    final artist = _cleanLookupTerm(metadata.getTrackArtistNames);
    final album = _cleanLookupTerm(metadata.albumName);
    final fallbackTitle = _cleanLookupTerm(_fileStem(metadata.filePath));
    final parts = <String>[
      if (title != null) title,
      if (artist != null) artist,
      if (title == null && fallbackTitle != null) fallbackTitle,
      if (album != null && title == null) album,
    ];
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' ');
  }

  MusicMetadataMatch? _bestHighConfidenceMatch(
    MusicMetadata metadata,
    List<MusicMetadataMatch> matches,
  ) {
    MusicMetadataMatch? bestMatch;
    var bestScore = 0.0;
    for (final match in matches) {
      final score = _metadataMatchScore(metadata, match);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = match;
      }
    }
    return bestScore >= 0.82 ? bestMatch : null;
  }

  double _metadataMatchScore(MusicMetadata metadata, MusicMetadataMatch match) {
    final title = _cleanLookupTerm(metadata.trackName) ?? _cleanLookupTerm(_fileStem(metadata.filePath));
    final artist = _cleanLookupTerm(metadata.getTrackArtistNames);
    final album = _cleanLookupTerm(metadata.albumName);
    final titleScore = _similarity(title, match.title);
    final artistScore = artist == null ? 0.55 : _similarity(artist, match.artist);
    final albumScore = album == null || match.album.trim().isEmpty
        ? 0.65
        : _similarity(album, match.album);
    final durationScore = _durationScore(metadata.trackDuration, match.durationMs);
    return titleScore * 0.48 +
        artistScore * 0.28 +
        albumScore * 0.10 +
        durationScore * 0.14;
  }

  double _durationScore(int? localMs, int? remoteMs) {
    if (localMs == null || localMs <= 0 || remoteMs == null || remoteMs <= 0) {
      return 0.65;
    }
    final deltaSeconds = ((localMs - remoteMs).abs() / 1000).round();
    if (deltaSeconds <= 3) {
      return 1;
    }
    if (deltaSeconds <= 8) {
      return 0.82;
    }
    if (deltaSeconds <= 15) {
      return 0.55;
    }
    return 0;
  }

  double _similarity(String? left, String right) {
    final a = _normalizeLookupText(left);
    final b = _normalizeLookupText(right);
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    if (a == b) {
      return 1;
    }
    if (a.contains(b) || b.contains(a)) {
      return 0.9;
    }
    final distance = _levenshteinDistance(a, b);
    final maxLength = a.length > b.length ? a.length : b.length;
    return (1 - distance / maxLength).clamp(0, 1).toDouble();
  }

  int _levenshteinDistance(String a, String b) {
    final previous = List<int>.generate(b.length + 1, (index) => index);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        final insertion = current[j] + 1;
        final deletion = previous[j + 1] + 1;
        final substitution = previous[j] + cost;
        current[j + 1] = [insertion, deletion, substitution].reduce((x, y) => x < y ? x : y);
      }
      previous.setAll(0, current);
    }
    return previous[b.length];
  }

  String? _cleanLookupTerm(String? value) {
    final normalized = _normalizeLookupText(value);
    return normalized.isEmpty ? null : normalized;
  }

  String _normalizeLookupText(String? value) {
    if (value == null) {
      return '';
    }
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\b(feat|ft|featuring|explicit|clean|remaster|remastered|single|version)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _fileStem(String? path) {
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _deleteManagedAudioFile(MusicMetadata metadata) async {
    if (!metadata.isOnDevice || metadata.isAppleMusicCatalogTrack) {
      return;
    }

    final path = metadata.filePath;
    if (path == null || path.isEmpty) {
      return;
    }

    final resolvedPath = AppDocumentsService.resolveManagedPath(path) ?? path;
    final file = File(resolvedPath);
    if (!await file.exists()) {
      return;
    }

    try {
      await file.delete();
    } catch (error, stackTrace) {
      ref
          .read(debugLogServiceProvider)
          .error(
            'audio_files',
            'Failed to delete song file from disk.',
            error: error,
            stackTrace: stackTrace,
            data: {
              'trackName': metadata.trackName,
              'artist': metadata.getTrackArtistNames,
              'filePath': resolvedPath,
            },
          );
    }
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
      ref
          .read(debugLogServiceProvider)
          .error(
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

    final importsDirectory = Directory(
      ref.read(appDocumentsServiceProvider).importsDirectoryPath,
    );
    importsDirectory.createSync(recursive: true);

    final metadataBox = Hive.box<MusicMetadata>(Constants.metadataBoxName);
    final existingFingerprints = <String>{};
    for (final metadata in metadataBox.values) {
      final fingerprint = _fingerprintForExistingMetadata(metadata);
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
    var duplicateCount = 0;
    var skippedCount = 0;

    for (final file in pickedFiles.files) {
      final sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        skippedCount++;
        ref.read(debugLogServiceProvider).warning(
          'import',
          'Skipped file with empty source path',
        );
        continue;
      }
      if (_isLyricsSidecar(sourcePath)) {
        continue;
      }
      if (!metadataReaderRepository.isSupportedAudioFormat(sourcePath)) {
        skippedCount++;
        ref.read(debugLogServiceProvider).warning(
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
          ref.read(debugLogServiceProvider).warning(
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

      final fingerprint = _fileFingerprintForFile(
        sourceFile,
        sourcePath,
        byteLength,
      );
      if (existingFingerprints.contains(fingerprint)) {
        duplicateCount++;
        ref.read(debugLogServiceProvider).info(
          'import',
          'Skipped duplicate file',
          data: {
            'name': displayName,
            'source': sourcePath,
            'bytes': byteLength,
            'fingerprint': fingerprint,
          },
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
        ref.read(debugLogServiceProvider).info(
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
      ref.read(debugLogServiceProvider).info(
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
    final shouldAutoEnhanceImport = rawResult.length <= 25;
    for (final metadata in rawResult) {
      if (metadata.filePath == null ||
          existingPaths.contains(metadata.filePath) ||
          !_isPlayableMetadata(metadata)) {
        duplicateCount++;
        continue;
      }
      final importedAt = DateTime.now().millisecondsSinceEpoch;
      final repairedMetadata = metadata.copyWith(
        originalSongIndex: startIndex + importedMetadata.length,
        sourceCreatedAtEpochMs: importedAt,
        sourceModifiedAtEpochMs: importedAt,
        importedAtEpochMs: importedAt,
      );
      final enhancedMetadata = shouldAutoEnhanceImport
          ? await _autoEnhanceImportedMetadata(repairedMetadata)
          : repairedMetadata;
      importedMetadata.add(enhancedMetadata);
      ref.read(debugLogServiceProvider).info(
        'import',
        'Imported metadata ready',
        data: {
          'title': enhancedMetadata.trackName,
          'artist': enhancedMetadata.getTrackArtistNames,
          'album': enhancedMetadata.albumName,
          'path': enhancedMetadata.filePath,
          'originalSongIndex': enhancedMetadata.originalSongIndex,
          'autoMetadataApplied': enhancedMetadata != repairedMetadata,
          'autoMetadataSkippedForBulkImport': !shouldAutoEnhanceImport,
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
        ref
            .read(debugLogServiceProvider)
            .error(
              'import',
              'Lyrics sidecar copy failed',
              error: e,
              data: {
                'sidecarPath': sidecarPath,
                'destinationStem': destinationStem,
              },
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
    return stem.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  String _fileFingerprint(String pathOrName, int byteLength) {
    return '${_normalizedStem(pathOrName)}:$byteLength';
  }

  String _fileFingerprintForFile(File file, String pathOrName, int byteLength) {
    try {
      final randomAccessFile = file.openSync();
      try {
        final sample = <int>[];
        final headLength = byteLength < 4096 ? byteLength : 4096;
        sample.addAll(randomAccessFile.readSync(headLength));
        if (byteLength > 4096) {
          final tailLength = byteLength < 8192 ? byteLength - 4096 : 4096;
          randomAccessFile.setPositionSync(byteLength - tailLength);
          sample.addAll(randomAccessFile.readSync(tailLength));
        }
        final digest = sha1.convert(utf8.encode(_normalizedStem(pathOrName)) + sample);
        return '$byteLength:$digest';
      } finally {
        randomAccessFile.closeSync();
      }
    } catch (_) {
      return _fileFingerprint(pathOrName, byteLength);
    }
  }

  String? _fingerprintForExistingMetadata(MusicMetadata metadata) {
    if (!metadata.isOnDevice || metadata.isAppleMusicCatalogTrack) {
      return null;
    }
    final path = metadata.filePath;
    if (path == null || path.isEmpty) {
      return null;
    }
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      final length = file.lengthSync();
      return _fileFingerprintForFile(file, path, length);
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
