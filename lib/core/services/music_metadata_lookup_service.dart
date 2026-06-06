import 'dart:convert';
import 'dart:io';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/features/music/songs/models/music_metadata_match.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';


enum AppleMusicAuthorizationStatus {
  unsupported,
  notDetermined,
  denied,
  restricted,
  authorized,
  unknown;

  bool get canSearchCatalog {
    switch (this) {
      case AppleMusicAuthorizationStatus.authorized:
        return true;
      case AppleMusicAuthorizationStatus.unsupported:
      case AppleMusicAuthorizationStatus.notDetermined:
      case AppleMusicAuthorizationStatus.denied:
      case AppleMusicAuthorizationStatus.restricted:
      case AppleMusicAuthorizationStatus.unknown:
        return false;
    }
  }

  String get message {
    switch (this) {
      case AppleMusicAuthorizationStatus.unsupported:
        return 'Apple Music catalog search is only available on iOS.';
      case AppleMusicAuthorizationStatus.notDetermined:
        return 'Apple Music access has not been requested yet.';
      case AppleMusicAuthorizationStatus.denied:
        return 'Apple Music access was denied.';
      case AppleMusicAuthorizationStatus.restricted:
        return 'Apple Music access is restricted on this device.';
      case AppleMusicAuthorizationStatus.authorized:
        return 'Apple Music access is authorized.';
      case AppleMusicAuthorizationStatus.unknown:
        return 'Apple Music authorization status is unknown.';
    }
  }

  static AppleMusicAuthorizationStatus fromName(String? name) {
    return AppleMusicAuthorizationStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => AppleMusicAuthorizationStatus.unknown,
    );
  }
}


class AppleMusicSubscriptionStatus {
  final bool isSupported;
  final bool canPlayCatalogContent;
  final bool canBecomeSubscriber;
  final bool hasCloudLibraryEnabled;

  const AppleMusicSubscriptionStatus({
    required this.isSupported,
    required this.canPlayCatalogContent,
    required this.canBecomeSubscriber,
    required this.hasCloudLibraryEnabled,
  });

  const AppleMusicSubscriptionStatus.unsupported()
    : isSupported = false,
      canPlayCatalogContent = false,
      canBecomeSubscriber = false,
      hasCloudLibraryEnabled = false;

  factory AppleMusicSubscriptionStatus.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const AppleMusicSubscriptionStatus.unsupported();
    }
    return AppleMusicSubscriptionStatus(
      isSupported: _bool(map['isSupported']),
      canPlayCatalogContent: _bool(map['canPlayCatalogContent']),
      canBecomeSubscriber: _bool(map['canBecomeSubscriber']),
      hasCloudLibraryEnabled: _bool(map['hasCloudLibraryEnabled']),
    );
  }

  String get playbackMessage {
    if (!isSupported) {
      return 'Apple Music subscription playback is only available on iOS.';
    }
    if (!canPlayCatalogContent) {
      return 'Apple Music subscription playback is unavailable.';
    }
    return 'Apple Music subscription playback is available.';
  }
}

final musicMetadataLookupServiceProvider = Provider<MusicMetadataLookupService>(
  (ref) => MusicMetadataLookupService(),
);

class MusicMetadataLookupService {
  final AppleMusicCatalogBridge _appleMusicBridge;

  MusicMetadataLookupService({AppleMusicCatalogBridge? appleMusicBridge})
    : _appleMusicBridge = appleMusicBridge ?? AppleMusicCatalogBridge();

  Future<AppleMusicAuthorizationStatus> appleMusicAuthorizationStatus() {
    return _appleMusicBridge.authorizationStatus();
  }

  Future<AppleMusicAuthorizationStatus> requestAppleMusicAuthorization() {
    return _appleMusicBridge.requestAuthorization();
  }


  Future<AppleMusicSubscriptionStatus> appleMusicSubscriptionStatus() {
    return _appleMusicBridge.subscriptionStatus();
  }

  Future<List<MusicMetadataMatch>> appleMusicLibrarySongs({
    int limit = 100,
  }) async {
    if (!_appleMusicBridge.isSupported) {
      return [];
    }
    final status = await _appleMusicBridge.requestAuthorization();
    if (!status.canSearchCatalog) {
      return [];
    }
    return _appleMusicBridge.librarySongs(limit: limit);
  }

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
        if (_appleMusicBridge.isSupported) {
          final status = await _appleMusicBridge.requestAuthorization();
          if (!status.canSearchCatalog) {
            return [];
          }
        }
        final nativeMatches = await _appleMusicBridge.searchSongs(
          query: cleanQuery,
          limit: limit,
          storefront: storefront,
        );
        if (nativeMatches.isNotEmpty) {
          return nativeMatches;
        }
        return _searchItunes(
          cleanQuery,
          limit,
          storefront,
          source: MusicMetadataSource.appleMusic,
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

    for (final artworkUri in _artworkCandidates(uri)) {
      final bytes = await _readBytes(
        artworkUri,
        acceptHeader: 'image/avif,image/webp,image/apng,image/*,*/*',
      );
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      await destination.writeAsBytes(bytes, flush: true);
      return destination.path;
    }

    return null;
  }

  Future<List<MusicMetadataMatch>> _searchItunes(
    String query,
    int limit,
    String storefront, {
    MusicMetadataSource source = MusicMetadataSource.itunes,
  }) async {
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
        .map((json) => _itunesMatchFromJson(json, source: source))
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

  bool get isSupported => !kIsWeb && Platform.isIOS;

  Future<AppleMusicAuthorizationStatus> authorizationStatus() async {
    if (!isSupported) {
      return AppleMusicAuthorizationStatus.unsupported;
    }
    try {
      final status = await _channel.invokeMethod<String>(
        'authorizationStatus',
      );
      return AppleMusicAuthorizationStatus.fromName(status);
    } on PlatformException {
      return AppleMusicAuthorizationStatus.unknown;
    } on MissingPluginException {
      return AppleMusicAuthorizationStatus.unsupported;
    }
  }

  Future<AppleMusicAuthorizationStatus> requestAuthorization() async {
    if (!isSupported) {
      return AppleMusicAuthorizationStatus.unsupported;
    }
    try {
      final status = await _channel.invokeMethod<String>(
        'requestAuthorization',
      );
      return AppleMusicAuthorizationStatus.fromName(status);
    } on PlatformException {
      return AppleMusicAuthorizationStatus.unknown;
    } on MissingPluginException {
      return AppleMusicAuthorizationStatus.unsupported;
    }
  }


  Future<AppleMusicSubscriptionStatus> subscriptionStatus() async {
    if (!isSupported) {
      return const AppleMusicSubscriptionStatus.unsupported();
    }
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>(
        'subscriptionStatus',
      );
      return AppleMusicSubscriptionStatus.fromMap(status);
    } on PlatformException {
      return const AppleMusicSubscriptionStatus.unsupported();
    } on MissingPluginException {
      return const AppleMusicSubscriptionStatus.unsupported();
    }
  }

  Future<List<MusicMetadataMatch>> searchSongs({
    required String query,
    int limit = 10,
    String storefront = 'US',
  }) async {
    if (!isSupported) {
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


  Future<List<MusicMetadataMatch>> librarySongs({int limit = 100}) async {
    if (!isSupported) {
      return [];
    }

    try {
      final rawResults = await _channel.invokeMethod<List<dynamic>>(
        'librarySongs',
        {'limit': limit.clamp(1, 250)},
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

MusicMetadataMatch _itunesMatchFromJson(
  Map<String, dynamic> json, {
  MusicMetadataSource source = MusicMetadataSource.itunes,
}) {
  return MusicMetadataMatch(
    source: source,
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
    catalogUrl: _stringOrNull(json['trackViewUrl']),
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
    catalogUrl: _stringOrNull(json['catalogUrl']),
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

Future<List<int>?> _readBytes(
  Uri uri, {
  String acceptHeader = 'application/json,*/*',
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, acceptHeader);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'mo1/1.17 local-music-metadata',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    return await response.expand((chunk) => chunk).toList();
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


bool _bool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
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

List<Uri> _artworkCandidates(Uri uri) {
  final urls = <String>[
    uri.toString(),
    _replaceArtworkSize(uri.toString(), '1000x1000bb'),
    _replaceArtworkSize(uri.toString(), '600x600bb'),
    _replaceArtworkSize(uri.toString(), '300x300bb'),
    _replaceArtworkSize(uri.toString(), '100x100bb'),
  ];
  final seen = <String>{};
  return urls
      .where((url) => url.trim().isNotEmpty)
      .where(seen.add)
      .map(Uri.tryParse)
      .whereType<Uri>()
      .where((candidate) => candidate.hasScheme)
      .toList(growable: false);
}

String _replaceArtworkSize(String url, String size) {
  return url
      .replaceAll(RegExp(r'/\d+x\d+(?:bb|cw)\.'), '/$size.')
      .replaceAll(RegExp(r'/source/\d+x\d+(?:bb|cw)\.'), '/source/$size.');
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
