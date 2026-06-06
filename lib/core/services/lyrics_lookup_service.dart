import 'dart:convert';
import 'dart:io';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final lyricsLookupServiceProvider = Provider<LyricsLookupService>(
  (ref) => LyricsLookupService(),
);

class LyricsLookupService {
  Future<List<LyricsSearchResult>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return [];
    }

    final response = await _readJson(
      Uri.https('lrclib.net', '/api/search', {'q': cleanQuery}),
    );
    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map<String, dynamic>>()
        .map(LyricsSearchResult.fromJson)
        .where((result) => result.bestLyrics != null)
        .toList(growable: false);
  }

  Future<String?> findBestFor(MusicMetadata metadata) async {
    final title = metadata.trackName?.trim();
    if (title == null || title.isEmpty) {
      return null;
    }

    final query = <String, String>{'track_name': title};
    final artist = metadata.getTrackArtistNames;
    if (artist != null && artist.trim().isNotEmpty) {
      query['artist_name'] = artist;
    }
    final album = metadata.albumName;
    if (album != null && album.trim().isNotEmpty) {
      query['album_name'] = album;
    }
    final duration = metadata.trackDuration;
    if (duration != null && duration > 0) {
      query['duration'] = (duration / 1000).round().toString();
    }

    final response = await _readJson(Uri.https('lrclib.net', '/api/get', query));
    final exactResult = response is Map<String, dynamic>
        ? LyricsSearchResult.fromJson(response)
        : null;
    final exactSyncedLyrics = exactResult?.syncedLyrics?.trim();
    if (exactSyncedLyrics != null && exactSyncedLyrics.isNotEmpty) {
      return exactSyncedLyrics;
    }

    final fallbackResult = await _searchFallback(title, artist);
    final fallbackSyncedLyrics = fallbackResult?.syncedLyrics?.trim();
    if (fallbackSyncedLyrics != null && fallbackSyncedLyrics.isNotEmpty) {
      return fallbackSyncedLyrics;
    }

    return exactResult?.bestLyrics ?? fallbackResult?.bestLyrics;
  }

  Future<LyricsSearchResult?> _searchFallback(
    String title,
    String? artist,
  ) async {
    final query = [
      title,
      if (artist != null && artist.trim().isNotEmpty) artist,
    ].join(' ');
    final results = await search(query);
    if (results.isEmpty) {
      return null;
    }
    for (final result in results) {
      final syncedLyrics = result.syncedLyrics?.trim();
      if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
        return result;
      }
    }
    return results.first;
  }
}

class LyricsSearchResult {
  final int id;
  final String trackName;
  final String artistName;
  final String albumName;
  final int? durationSeconds;
  final String? plainLyrics;
  final String? syncedLyrics;

  const LyricsSearchResult({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.durationSeconds,
    this.plainLyrics,
    this.syncedLyrics,
  });

  factory LyricsSearchResult.fromJson(Map<String, dynamic> json) {
    return LyricsSearchResult(
      id: _integer(json['id']) ?? 0,
      trackName: _string(json['trackName']),
      artistName: _string(json['artistName']),
      albumName: _string(json['albumName']),
      durationSeconds: _integer(json['duration']),
      plainLyrics: _stringOrNull(json['plainLyrics']),
      syncedLyrics: _stringOrNull(json['syncedLyrics']),
    );
  }

  String? get bestLyrics {
    final synced = syncedLyrics?.trim();
    if (synced != null && synced.isNotEmpty) {
      return synced;
    }
    final plain = plainLyrics?.trim();
    return plain == null || plain.isEmpty ? null : plain;
  }

  String get subtitle {
    final values = [artistName, albumName]
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    return values.join(' - ');
  }
}

Future<dynamic> _readJson(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) mo1/1.0',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final payload = await response.transform(utf8.decoder).join();
    return jsonDecode(payload);
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
