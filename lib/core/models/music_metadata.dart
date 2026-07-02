import 'dart:convert';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_service/audio_service.dart';
import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/utils/metadata_artwork.dart';
import 'package:dope/features/music/album/models/album_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';

String? normalizeMetadataString(String? value) {
  if (value == null || value.isEmpty) {
    return value;
  }

  final codeUnits = value.codeUnits;

  if (codeUnits.isEmpty || codeUnits.first != 0xFFFE) {
    return value;
  }

  final StringBuffer buffer = StringBuffer();

  for (final int unit in codeUnits) {
    final int swappedUnit = ((unit & 0xFF) << 8) | (unit >> 8);

    if (swappedUnit == 0xFEFF) {
      continue;
    }

    buffer.writeCharCode(swappedUnit);
  }

  final String normalizedValue = buffer.toString();

  return normalizedValue.isEmpty ? value : normalizedValue;
}

String? _cleanMetadataString(String? value) {
  final normalized = normalizeMetadataString(value)?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final folded = normalized.toLowerCase();
  if (folded == 'unknown' ||
      folded == 'unknown song' ||
      folded == 'unknown title' ||
      folded == 'unknown artist' ||
      folded == 'unknown album' ||
      folded == '<unknown>' ||
      folded == 'null') {
    return null;
  }

  return normalized;
}

String? _cleanEmbeddedMetadataString(String? value) {
  final cleaned = _cleanMetadataString(value);
  if (cleaned == null) {
    return null;
  }

  if (_isGeneratedContainerJunk(cleaned)) {
    return null;
  }

  return cleaned;
}

bool _isGeneratedContainerJunk(String value) {
  final folded = value.toLowerCase().trim();
  final compact = folded.replaceAll(RegExp(r'[\s_\-]+'), '');
  const exactJunk = {
    'dash',
    'mp4',
    'mp41',
    'mp42',
    'isom',
    'iso6',
    'iso6mp41',
    'isommp42',
    'majorbrand',
    'minorversion',
    'compatiblebrands',
  };

  if (exactJunk.contains(compact)) {
    return true;
  }

  return compact.startsWith('lavf') ||
      compact.startsWith('lavc') ||
      compact.startsWith('lame') ||
      compact.contains('youtube');
}

List<String> _splitArtistNames(String artist) {
  final List<String> names;
  if (artist.contains(',')) {
    names = artist.split(',');
  } else if (artist.contains('/')) {
    names = artist.split('/');
  } else if (artist.contains(';')) {
    names = artist.split(';');
  } else {
    names = [artist];
  }

  return names
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
}

List<String>? _artistNamesFromValue(dynamic value) {
  if (value is List) {
    final artists = value
        .whereType<String>()
        .map(_cleanMetadataString)
        .whereType<String>()
        .toList(growable: false);
    return artists.isEmpty ? null : artists;
  }

  final artist = _cleanMetadataString(value?.toString());
  if (artist == null) {
    return null;
  }
  final artists = _splitArtistNames(artist);
  return artists.isEmpty ? null : artists;
}

String _fileNameWithoutExtension(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  final fileName = slash == -1 ? normalized : normalized.substring(slash + 1);
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

String? _parentFolderName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  if (slash <= 0) {
    return null;
  }
  final parentPath = normalized.substring(0, slash);
  final parentSlash = parentPath.lastIndexOf('/');
  final folder = parentSlash == -1
      ? parentPath
      : parentPath.substring(parentSlash + 1);
  final cleaned = _cleanMetadataString(folder.replaceAll('_', ' '));
  if (cleaned == null) {
    return null;
  }

  const ignoredParents = {
    'classipod',
    'døpi',
    'documents',
    'downloads',
    'files',
    'imports',
    'music',
  };
  return ignoredParents.contains(cleaned.toLowerCase()) ? null : cleaned;
}

String _cleanFileStem(String value) {
  return value
      .replaceAll(RegExp(r'[_\.]+'), ' ')
      .replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-_. ]\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stripImportCollisionSuffix(String value) {
  return value.replaceFirst(RegExp(r'\s+\d{1,3}$'), '').trim();
}

class _MetadataFallback {
  final String? title;
  final String? artist;
  final String? albumName;

  const _MetadataFallback({this.title, this.artist, this.albumName});

  factory _MetadataFallback.fromArtistTitleText(
    String value, {
    bool stripImportCollisionSuffix = false,
  }) {
    final rawCleanedValue = _cleanFileStem(value);
    final cleanedValue = _cleanMetadataString(
      stripImportCollisionSuffix
          ? _stripImportCollisionSuffix(rawCleanedValue)
          : rawCleanedValue,
    );
    if (cleanedValue == null) {
      return const _MetadataFallback();
    }

    String? title = cleanedValue;
    String? artist;

    final separatorMatch = RegExp(r'\s+-\s+').firstMatch(cleanedValue);
    if (separatorMatch != null) {
      final left = cleanedValue.substring(0, separatorMatch.start);
      final right = cleanedValue.substring(separatorMatch.end);
      artist = _cleanMetadataString(left);
      title = _cleanMetadataString(right) ?? title;
    }

    return _MetadataFallback(title: title, artist: artist);
  }

  factory _MetadataFallback.fromPath(
    String path, {
    String? fallbackFileName,
  }) {
    final sourceName = fallbackFileName ?? path;
    final shouldStripImportCollisionSuffix =
        fallbackFileName == null &&
        Constants.isAppSubdirectoryPath(
          path,
          Constants.importsDirectoryName,
        );
    final cleanedStem = _cleanFileStem(_fileNameWithoutExtension(sourceName));
    final artistTitle = _MetadataFallback.fromArtistTitleText(
      cleanedStem,
      stripImportCollisionSuffix: shouldStripImportCollisionSuffix,
    );

    return _MetadataFallback(
      title: artistTitle.title,
      artist: artistTitle.artist,
      albumName: _parentFolderName(path),
    );
  }
}

class MusicMetadata extends HiveObject {
  static const appleMusicCatalogPathPrefix = 'applemusic://song/';

  /// Name of the track.
  final String? trackName;

  /// Names of the artists performing in the track.
  final List<String>? trackArtistNames;

  /// Name of the album.
  final String? albumName;

  /// Name of the album artist.
  final String? albumArtistName;

  /// Position of track in the album.
  final int? trackNumber;

  /// Number of tracks in the album.
  final int? albumLength;

  /// Year of the track.
  final int? year;

  /// Genres of the track.
  final List<String> genres;

  /// Number of the disc.
  final int? discNumber;

  /// Mime type.
  final String? mimeType;

  /// Duration of the track in milliseconds.
  final int? trackDuration;

  /// Bitrate of the track.
  final int? bitrate;

  /// File path of the audio file.
  final String? filePath;

  /// File path of the thumbnail album art file.
  final String? thumbnailPath;

  /// Original Song Index
  final int originalSongIndex;

  /// Bool to Indicate that the File is Located On-Device
  final bool isOnDevice;

  /// Rating of the track.
  final int rating;

  final String? lyrics;
  final int? sourceCreatedAtEpochMs;
  final int? sourceModifiedAtEpochMs;
  final int? importedAtEpochMs;

  MusicMetadata({
    this.trackName,
    this.trackArtistNames,
    this.albumName,
    this.albumArtistName,
    this.trackNumber,
    this.albumLength,
    this.year,
    this.genres = const [],
    this.discNumber,
    this.mimeType,
    this.trackDuration,
    this.bitrate,
    this.filePath,
    this.thumbnailPath,
    this.originalSongIndex = 0,
    this.isOnDevice = true,
    this.rating = 0,
    this.lyrics,
    this.sourceCreatedAtEpochMs,
    this.sourceModifiedAtEpochMs,
    this.importedAtEpochMs,
  });

  factory MusicMetadata.fromAudioMetadata(
    AudioMetadata audioMetadata,
    String? thumbnailPath,
    int originalSongIndex, {
    String? fallbackLyrics,
    String? fallbackFileName,
  }) {
    final fallback = _MetadataFallback.fromPath(
      audioMetadata.file.path,
      fallbackFileName: fallbackFileName,
    );
    final embeddedArtist = _cleanEmbeddedMetadataString(audioMetadata.artist);
    final embeddedTitle = _cleanEmbeddedMetadataString(audioMetadata.title);
    final titleFallback = embeddedArtist == null && embeddedTitle != null
        ? _MetadataFallback.fromArtistTitleText(embeddedTitle)
        : null;
    final artist = embeddedArtist ?? titleFallback?.artist ?? fallback.artist;
    final List<String>? trackArtistNames = artist == null
        ? null
        : _splitArtistNames(artist);
    final albumName =
        _cleanEmbeddedMetadataString(audioMetadata.album) ?? fallback.albumName;
    final trackName = titleFallback?.title ?? embeddedTitle ?? fallback.title;

    return MusicMetadata(
      trackName: trackName,
      trackArtistNames: trackArtistNames,
      albumName: albumName,
      albumArtistName: trackArtistNames?.first ?? fallback.artist,
      trackNumber: audioMetadata.trackNumber,
      albumLength: audioMetadata.trackTotal,
      year: audioMetadata.year?.year,
      genres: audioMetadata.genres
          .map(_cleanMetadataString)
          .whereType<String>()
          .toList(growable: false),
      discNumber: audioMetadata.discNumber,
      mimeType: audioMetadata.pictures.isEmpty
          ? null
          : audioMetadata.pictures[0].mimetype,
      trackDuration: audioMetadata.duration?.inMilliseconds,
      bitrate: audioMetadata.bitrate,
      filePath: audioMetadata.file.path,
      thumbnailPath: thumbnailPath,
      originalSongIndex: originalSongIndex,
      lyrics:
          _cleanMetadataString(audioMetadata.lyrics) ??
          _cleanMetadataString(fallbackLyrics),
      importedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory MusicMetadata.fromFilePathFallback(
    String path,
    int originalSongIndex, {
    String? fallbackLyrics,
    String? fallbackFileName,
  }) {
    final fallback = _MetadataFallback.fromPath(
      path,
      fallbackFileName: fallbackFileName,
    );
    final trackArtistNames = fallback.artist == null
        ? null
        : _splitArtistNames(fallback.artist!);

    return MusicMetadata(
      trackName: fallback.title,
      trackArtistNames: trackArtistNames,
      albumName: fallback.albumName,
      albumArtistName: trackArtistNames?.first ?? fallback.artist,
      filePath: path,
      originalSongIndex: originalSongIndex,
      lyrics: _cleanMetadataString(fallbackLyrics),
      importedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory MusicMetadata.fromMap(Map<String, dynamic> map) => MusicMetadata(
    trackName: _cleanMetadataString(map['metadata']['trackName']),
    trackArtistNames: _artistNamesFromValue(
      map['metadata']['trackArtistNames'],
    ),
    albumName: _cleanMetadataString(map['metadata']['albumName']),
    albumArtistName: _cleanMetadataString(
      map['metadata']['albumArtistName'],
    ),
    trackNumber: parseInteger(map['metadata']['trackNumber']),
    albumLength: parseInteger(map['metadata']['albumLength']),
    year: parseInteger(map['metadata']['year']),
    genres: map['genres'],
    discNumber: parseInteger(map['metadata']['discNumber']),
    mimeType: map['metadata']['mimeType'],
    trackDuration: parseInteger(map['metadata']['trackDuration']),
    bitrate: parseInteger(map['metadata']['bitrate']),
    filePath: map['filePath'],
    thumbnailPath: map['thumbnailPath'],
    originalSongIndex: map['originalSongIndex'],
    isOnDevice: map['isOnDevice'],
    rating: map['rating'],
    lyrics: _cleanMetadataString(map['lyrics']),
    sourceCreatedAtEpochMs: parseInteger(map['sourceCreatedAtEpochMs']),
    sourceModifiedAtEpochMs: parseInteger(map['sourceModifiedAtEpochMs']),
    importedAtEpochMs: parseInteger(map['importedAtEpochMs']),
  );

  Map<String, dynamic> toMap() => {
    'trackName': trackName,
    'trackArtistNames': trackArtistNames,
    'albumName': albumName,
    'albumArtistName': albumArtistName,
    'trackNumber': trackNumber,
    'albumLength': albumLength,
    'year': year,
    'genres': genres,
    'discNumber': discNumber,
    'mimeType': mimeType,
    'trackDuration': trackDuration,
    'bitrate': bitrate,
    'filePath': filePath,
    'thumbnailPath': thumbnailPath,
    'originalSongIndex': originalSongIndex,
    'isOnDevice': isOnDevice,
    'rating': rating,
    'lyrics': lyrics,
    'sourceCreatedAtEpochMs': sourceCreatedAtEpochMs,
    'sourceModifiedAtEpochMs': sourceModifiedAtEpochMs,
    'importedAtEpochMs': importedAtEpochMs,
  };

  factory MusicMetadata.fromJson(String source) =>
      MusicMetadata.fromMap(jsonDecode(source));

  String toJson() => jsonEncode(toMap());

  MusicMetadata copyWith({
    String? trackName,
    List<String>? trackArtistNames,
    String? albumName,
    String? albumArtistName,
    int? trackNumber,
    int? albumLength,
    int? year,
    List<String>? genres,
    int? discNumber,
    String? mimeType,
    int? trackDuration,
    int? bitrate,
    String? filePath,
    String? thumbnailPath,
    int? originalSongIndex,
    bool? isOnDevice,
    int? rating,
    String? lyrics,
    int? sourceCreatedAtEpochMs,
    int? sourceModifiedAtEpochMs,
    int? importedAtEpochMs,
  }) {
    return MusicMetadata(
      trackName: trackName ?? this.trackName,
      trackArtistNames: trackArtistNames ?? this.trackArtistNames,
      albumName: albumName ?? this.albumName,
      albumArtistName: albumArtistName ?? this.albumArtistName,
      trackNumber: trackNumber ?? this.trackNumber,
      albumLength: albumLength ?? this.albumLength,
      year: year ?? this.year,
      genres: genres ?? this.genres,
      discNumber: discNumber ?? this.discNumber,
      mimeType: mimeType ?? this.mimeType,
      trackDuration: trackDuration ?? this.trackDuration,
      bitrate: bitrate ?? this.bitrate,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      originalSongIndex: originalSongIndex ?? this.originalSongIndex,
      isOnDevice: isOnDevice ?? this.isOnDevice,
      rating: rating ?? this.rating,
      lyrics: lyrics ?? this.lyrics,
      sourceCreatedAtEpochMs:
          sourceCreatedAtEpochMs ?? this.sourceCreatedAtEpochMs,
      sourceModifiedAtEpochMs:
          sourceModifiedAtEpochMs ?? this.sourceModifiedAtEpochMs,
      importedAtEpochMs: importedAtEpochMs ?? this.importedAtEpochMs,
    );
  }

  bool get isAppleMusicCatalogTrack {
    return filePath?.startsWith(appleMusicCatalogPathPrefix) ?? false;
  }

  String? get appleMusicCatalogId {
    final path = filePath;
    if (path == null || !path.startsWith(appleMusicCatalogPathPrefix)) {
      return null;
    }
    final catalogId = path.substring(appleMusicCatalogPathPrefix.length);
    return catalogId.isEmpty ? null : catalogId;
  }

  MusicMetadata withFilenameFallbacks() {
    final path = filePath;
    if (path == null || path.isEmpty) {
      return this;
    }

    final fallback = _MetadataFallback.fromPath(path);
    final cleanedArtists = trackArtistNames
        ?.map(_cleanEmbeddedMetadataString)
        .whereType<String>()
        .toList(growable: false);
    final fallbackArtists = fallback.artist == null
        ? null
        : _splitArtistNames(fallback.artist!);
    final safeArtists = cleanedArtists == null || cleanedArtists.isEmpty
        ? fallbackArtists
        : cleanedArtists;

    return MusicMetadata(
      trackName: _cleanEmbeddedMetadataString(trackName) ?? fallback.title,
      trackArtistNames: safeArtists,
      albumName: _cleanEmbeddedMetadataString(albumName) ?? fallback.albumName,
      albumArtistName:
          _cleanEmbeddedMetadataString(albumArtistName) ??
          safeArtists?.first ??
          fallback.artist,
      trackNumber: trackNumber,
      albumLength: albumLength,
      year: year,
      genres: genres,
      discNumber: discNumber,
      mimeType: mimeType,
      trackDuration: trackDuration,
      bitrate: bitrate,
      filePath: filePath,
      thumbnailPath: thumbnailPath,
      originalSongIndex: originalSongIndex,
      isOnDevice: isOnDevice,
      rating: rating,
      lyrics: lyrics,
      sourceCreatedAtEpochMs: sourceCreatedAtEpochMs,
      sourceModifiedAtEpochMs: sourceModifiedAtEpochMs,
      importedAtEpochMs: importedAtEpochMs,
    );
  }

  AudioSource toAudioSource() {
    if (isOnDevice) {
      return AudioSource.file(
        filePath ?? '',
        tag: MediaItem(
          id: filePath ?? '',
          title: trackName ?? "Unknown Song",
          album: albumName ?? "Unknown Album",
          artist: getTrackArtistNames,
          genre: genres.isEmpty ? null : genres[0],
          duration: trackDuration != null
              ? Duration(milliseconds: trackDuration!)
              : null,
          artUri: metadataArtworkUri(thumbnailPath),
          rating: Rating.newStarRating(RatingStyle.range5stars, rating),
          extras: {"loadThumbnailUri": true},
        ),
      );
    } else {
      return AudioSource.uri(
        Uri.parse(filePath ?? ''),
        tag: MediaItem(
          id: filePath ?? '',
          title: trackName ?? "Unknown Song",
          album: albumName ?? "Unknown Album",
          artist: getTrackArtistNames,
          genre: genres.isEmpty ? null : genres[0],
          duration: trackDuration != null
              ? Duration(milliseconds: trackDuration!)
              : null,
          artUri: metadataArtworkUri(thumbnailPath) ??
              Uri.parse(Constants.defaultNotificationAlbumArtImageUrl),
          rating: Rating.newStarRating(RatingStyle.range5stars, rating),
        ),
      );
    }
  }

  @override
  String toString() => toJson().toString();

  String get getTrackName {
    return trackName ?? 'Unknown Song';
  }

  String get getAlbumName {
    return albumName ?? "Unknown Album";
  }

  String get getAlbumArtistName {
    return albumArtistName ?? "Unknown Album Artist";
  }

  int get getTrackNumber {
    return trackNumber ?? 0;
  }

  int get getTrackDuration {
    return trackDuration ?? 0;
  }

  String get getMainArtistName {
    if (trackArtistNames == null || trackArtistNames!.isEmpty) {
      return "Unknown Artist";
    }
    return trackArtistNames!.first;
  }

  String? get getTrackArtistNames {
    final artists = trackArtistNames
        ?.map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .join(', ');
    return artists == null || artists.isEmpty ? null : artists;
  }

  int get effectiveAddedAtEpochMs {
    return sourceCreatedAtEpochMs ??
        sourceModifiedAtEpochMs ??
        importedAtEpochMs ??
        originalSongIndex;
  }

  String get getMainGenre {
    return genres.isNotEmpty ? genres[0] : "Unknown Genre";
  }

  AlbumModel get getAlbumDetail {
    return AlbumModel(
      albumName: getAlbumName,
      albumArtPath: thumbnailPath,
      albumArtistName: getAlbumArtistName,
      albumSongs: [this],
    );
  }

  String? get parentDirectoryPath {
    if (filePath == null) return null;

    // Normalize separators to forward slash for processing
    String normalizedPath = filePath!.replaceAll('\\', '/');

    // Remove trailing slash if present
    if (normalizedPath.endsWith('/')) {
      normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
    }

    // Find the last separator index
    final int lastSeparatorIndex = normalizedPath.lastIndexOf('/');

    // If no separator found, return root (or empty string)
    if (lastSeparatorIndex == -1) return null;

    String parent = normalizedPath.substring(0, lastSeparatorIndex);

    // For Windows: if the path is like C:/folder, preserve the drive letter and slash
    if (parent.length == 2 && parent[1] == ':') {
      parent += '/';
    }

    // Restore original backslashes on Windows if needed
    if (filePath!.contains('\\')) {
      parent = parent.replaceAll('/', '\\');
    }

    return parent;
  }

  @override
  bool operator ==(Object other) {
    return other is MusicMetadata &&
        trackName == other.trackName &&
        listEquals(trackArtistNames, other.trackArtistNames) &&
        albumName == other.albumName &&
        albumArtistName == other.albumArtistName &&
        trackNumber == other.trackNumber &&
        albumLength == other.albumLength &&
        year == other.year &&
        listEquals(genres, other.genres) &&
        discNumber == other.discNumber &&
        mimeType == other.mimeType &&
        trackDuration == other.trackDuration &&
        bitrate == other.bitrate &&
        filePath == other.filePath &&
        rating == other.rating &&
        lyrics == other.lyrics &&
        sourceCreatedAtEpochMs == other.sourceCreatedAtEpochMs &&
        sourceModifiedAtEpochMs == other.sourceModifiedAtEpochMs &&
        importedAtEpochMs == other.importedAtEpochMs;
  }

  @override
  int get hashCode => Object.hash(
    trackName,
    trackArtistNames,
    albumName,
    albumArtistName,
    trackNumber,
    albumLength,
    year,
    genres,
    discNumber,
    mimeType,
    trackDuration,
    bitrate,
    filePath,
    rating,
    lyrics,
    sourceCreatedAtEpochMs,
    sourceModifiedAtEpochMs,
    importedAtEpochMs,
  );
}

int? parseInteger(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  } else if (value is String) {
    try {
      try {
        return int.parse(value);
      } catch (_) {
        return int.parse(value.split('/').first);
      }
    } catch (_) {}
  }
  return null;
}
