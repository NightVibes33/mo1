import 'dart:convert';
import 'dart:io';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/features/music/songs/models/music_metadata_match.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final musicMetadataLookupServiceProvider = Provider<MusicMetadataLookupService>(
  (ref) => MusicMetadataLookupService(),
);

class MusicMetadataLookupService {
  final AppleMusicCatalogBridge _appleMusicBridge;

  MusicMetadataLookupService({AppleMusicCatalogBridge? appleMusicBridge})
    : _appleMusicBridge = appleMusicBridge ?? AppleMusicCatalogBridge();

  Future<List<MusicMetadataMatch>> search({
    required MusicMetadataSource source,
    required String query,
    int limit = 10,
    String storefront = 'US',
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return [];
    }

    switch (source) {
      case MusicMetadataSource.itunes:
        return _searchItunes(cleanQuery, limit, storefront);
      case MusicMetadataSource.deezer:
        return _searchDeezer(cleanQuery, limit);
      case MusicMetadataSource.appleMusic:
        return _appleMusicBridge.searchSongs(
          query: cleanQuery,
          limit: limit,
          storefront: storefront,
        );
    }
  }

  Future<String?> cacheArtworkForMatch(
    MusicMetadataMatch match,
    MusicMetadata current,
  ) async {
    final artworkUrl = match.artworkUrl;
    if (artworkUrl == null || artworkUrl.trim().isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(artworkUrl);
    if (uri == null || !uri.hasScheme) {
      return null;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final artworkDirectory = Directory(
      '${documentsDirectory.path}/ClassiPod/artwork',
    );
    await artworkDirectory.create(recursive: true);

    final extension = _artworkExtension(uri.path);
    final fileName = _safeFileName(
      '${current.originalSongIndex}_${match.source.name}_${match.id}',
    );
    final destination = File('${artworkDirectory.path}/$fileName.$extension');
    if (destination.existsSync() && destination.lengthSync() > 0) {
      return destination.path;
    }

    final bytes = await _readBytes(uri);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    await destination.writeAsBytes(bytes, flush: true);
    return destination.path;
  }

  Future<List<MusicMetadataMatch>> _searchItunes(
    String query,
    int limit,
    String storefront,
  ) async {
    final response = await _readJson(
      Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'entity': 'song',
        'limit': limit.clamp(1, 25).toString(),
        'country': storefront.trim().isEmpty ? 'US' : storefront.trim(),
      }),
    );

    final rawResults = response is Map<String, dynamic>
        ? response['results']
        : null;
    if (rawResults is! List) {
      return [];
    }

    return rawResults
        .whereType<Map<String, dynamic>>()
        .map(_itunesMatchFromJson)
        .where((match) => match.title.isNotEmpty || match.artist.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<MusicMetadataMatch>> _searchDeezer(
    String query,
    int limit,
  ) async {
    final response = await _readJson(
      Uri.https('api.deezer.com', '/search', {
        'q': query,
        'limit': limit.clamp(1, 25).toString(),
      }),
    );

    final rawResults = response is Map<String, dynamic> ? response['data'] : null;
    if (rawResults is! List) {
      return [];
    }

    return rawResults
        .whereType<Map<String, dynamic>>()
        .map(_deezerMatchFromJson)
        .where((match) => match.title.isNotEmpty || match.artist.isNotEmpty)
        .toList(growable: false);
  }
}

class AppleMusicCatalogBridge {
  static const MethodChannel _channel = MethodChannel('mo1/apple_music');

  Future<List<MusicMetadataMatch>> searchSongs({
    required String query,
    int limit = 10,
    String storefront = 'US',
  }) async {
    if (!Platform.isIOS) {
      return [];
    }

    try {
      final rawResults = await _channel.invokeMethod<List<dynamic>>(
        'searchSongs',
        {
          'query': query,
          'limit': limit.clamp(1, 25),
          'storefront': storefront.trim().isEmpty ? 'US' : storefront.trim(),
        },
      );
      return (rawResults ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map((map) => Map<String, dynamic>.from(map))
          .map(_appleMusicMatchFromJson)
          .where((match) => match.title.isNotEmpty || match.artist.isNotEmpty)
          .toList(growable: false);
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }
}

MusicMetadataMatch _itunesMatchFromJson(Map<String, dynamic> json) {
  return MusicMetadataMatch(
    source: MusicMetadataSource.itunes,
    id: _string(json['trackId']).isEmpty
        ? _string(json['collectionId'])
        : _string(json['trackId']),
    title: _string(json['trackName']),
    artist: _string(json['artistName']),
    album: _string(json['collectionName']),
    genres: _listFromStrings([json['primaryGenreName']]),
    artworkUrl: _highResolutionArtworkUrl(_stringOrNull(json['artworkUrl100'])),
    releaseDate: _date(json['releaseDate']),
    trackNumber: _integer(json['trackNumber']),
    trackCount: _integer(json['trackCount']),
    discNumber: _integer(json['discNumber']),
    durationMs: _integer(json['trackTimeMillis']),
    previewUrl: _stringOrNull(json['previewUrl']),
    isrc: _stringOrNull(json['isrc']),
  );
}

MusicMetadataMatch _deezerMatchFromJson(Map<String, dynamic> json) {
  final artist = json['artist'];
  final album = json['album'];
  final durationSeconds = _integer(json['duration']);

  return MusicMetadataMatch(
    source: MusicMetadataSource.deezer,
    id: _string(json['id']),
    title: _string(json['title_short']).isEmpty
        ? _string(json['title'])
        : _string(json['title_short']),
    artist: artist is Map<String, dynamic> ? _string(artist['name']) : '',
    album: album is Map<String, dynamic> ? _string(album['title']) : '',
    artworkUrl: album is Map<String, dynamic>
        ? _stringOrNull(album['cover_xl']) ?? _stringOrNull(album['cover_big'])
        : null,
    durationMs: durationSeconds == null ? null : durationSeconds * 1000,
    previewUrl: _stringOrNull(json['preview']),
  );
}

MusicMetadataMatch _appleMusicMatchFromJson(Map<String, dynamic> json) {
  return MusicMetadataMatch(
    source: MusicMetadataSource.appleMusic,
    id: _string(json['id']),
    title: _string(json['title']),
    artist: _string(json['artist']),
    album: _string(json['album']),
    genres: _listFromStrings(json['genres']),
    artworkUrl: _stringOrNull(json['artworkUrl']),
    releaseDate: _date(json['releaseDate']),
    trackNumber: _integer(json['trackNumber']),
    discNumber: _integer(json['discNumber']),
    durationMs: _integer(json['durationMs']),
    previewUrl: _stringOrNull(json['previewUrl']),
    isrc: _stringOrNull(json['isrc']),
  );
}

Future<dynamic> _readJson(Uri uri) async {
  final bytes = await _readBytes(uri);
  if (bytes == null) {
    return null;
  }
  return jsonDecode(utf8.decode(bytes));
}

Future<List<int>?> _readBytes(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json,*/*');
    request.headers.set(HttpHeaders.userAgentHeader, 'mo1/1.0');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    return response.expand((chunk) => chunk).toList();
  } finally {
    client.close(force: true);
  }
}

String _string(dynamic value) {
  if (value == null) {
    return '';
  }
  return value.toString().trim();
}

String? _stringOrNull(dynamic value) {
  final string = _string(value);
  return string.isEmpty ? null : string;
}

int? _integer(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

DateTime? _date(dynamic value) {
  final rawDate = _stringOrNull(value);
  if (rawDate == null) {
    return null;
  }
  return DateTime.tryParse(rawDate);
}

List<String> _listFromStrings(dynamic value) {
  if (value is Iterable) {
    return value
        .map(_string)
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
  final singleValue = _string(value);
  return singleValue.isEmpty ? [] : [singleValue];
}

String? _highResolutionArtworkUrl(String? url) {
  if (url == null || url.isEmpty) {
    return null;
  }
  return url
      .replaceAll(RegExp(r'/\d+x\d+bb\.'), '/1200x1200bb.')
      .replaceAll(RegExp(r'/\d+x\d+cw\.'), '/1200x1200bb.');
}

String _artworkExtension(String path) {
  final extension = path.split('.').last.toLowerCase();
  if (extension == 'png' || extension == 'webp') {
    return extension;
  }
  return 'jpg';
}

String _safeFileName(String value) {
  final sanitized = value
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .trim();
  return sanitized.isEmpty
      ? DateTime.now().millisecondsSinceEpoch.toString()
      : sanitized;
}
