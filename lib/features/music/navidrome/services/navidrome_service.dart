import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/features/music/navidrome/models/navidrome_browser_item.dart';
import 'package:dope/features/music/navidrome/models/navidrome_connection.dart';

class NavidromeServiceException implements Exception {
  final String message;

  const NavidromeServiceException(this.message);

  @override
  String toString() => message;
}

class NavidromeService {
  static const String _apiVersion = '1.16.1';
  static const String _clientName = 'dope';

  final HttpClient _httpClient;

  NavidromeService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  Future<void> ping(NavidromeConnection connection) async {
    await _getSubsonicResponse(connection, 'ping.view');
  }

  Future<List<MusicMetadata>> searchSongs(
    NavidromeConnection connection,
    String query,
  ) async {
    final response = await _getSubsonicResponse(
      connection,
      'search3.view',
      extraQueryParameters: {
        'query': query.trim(),
        'artistCount': '0',
        'albumCount': '0',
        'songCount': '100',
      },
    );
    final searchResult = response['searchResult3'];
    if (searchResult is! Map<String, dynamic>) {
      return const [];
    }
    final songsJson = searchResult['song'];
    if (songsJson is! List) {
      return const [];
    }

    return [
      for (var index = 0; index < songsJson.length; index++)
        if (songsJson[index] is Map<String, dynamic>)
          _songMetadataFromJson(
            connection,
            songsJson[index] as Map<String, dynamic>,
            index,
          ),
    ];
  }

  Future<List<MusicMetadata>> randomSongs(
    NavidromeConnection connection,
  ) async {
    final response = await _getSubsonicResponse(
      connection,
      'getRandomSongs.view',
      extraQueryParameters: {'size': '100'},
    );
    return _songsFromContainer(connection, response['randomSongs'], 'song');
  }

  Future<List<MusicMetadata>> starredSongs(
    NavidromeConnection connection,
  ) async {
    final response = await _getSubsonicResponse(connection, 'getStarred2.view');
    return _songsFromContainer(connection, response['starred2'], 'song');
  }

  Future<List<NavidromeBrowserItem>> albumList(
    NavidromeConnection connection,
    String type, {
    String? musicFolderId,
  }) async {
    final response = await _getSubsonicResponse(
      connection,
      'getAlbumList2.view',
      extraQueryParameters: {
        'type': type,
        'size': '100',
        if (musicFolderId != null) 'musicFolderId': musicFolderId,
      },
    );
    return _itemsFromContainer(
      response['albumList2'],
      'album',
      _albumItemFromJson,
    );
  }

  Future<List<NavidromeBrowserItem>> artists(
    NavidromeConnection connection,
  ) async {
    final response = await _getSubsonicResponse(connection, 'getArtists.view');
    final artists = response['artists'];
    if (artists is! Map<String, dynamic>) {
      return const [];
    }
    final indexes = artists['index'];
    if (indexes is! List) {
      return const [];
    }

    final items = <NavidromeBrowserItem>[];
    for (final index in indexes) {
      if (index is! Map<String, dynamic>) {
        continue;
      }
      final artistList = index['artist'];
      if (artistList is! List) {
        continue;
      }
      for (final artistJson in artistList) {
        if (artistJson is Map<String, dynamic>) {
          items.add(_artistItemFromJson(artistJson));
        }
      }
    }
    return items;
  }

  Future<List<NavidromeBrowserItem>> artistAlbums(
    NavidromeConnection connection,
    String artistId,
  ) async {
    final response = await _getSubsonicResponse(
      connection,
      'getArtist.view',
      extraQueryParameters: {'id': artistId},
    );
    return _itemsFromContainer(response['artist'], 'album', _albumItemFromJson);
  }

  Future<List<MusicMetadata>> albumSongs(
    NavidromeConnection connection,
    String albumId,
  ) async {
    final response = await _getSubsonicResponse(
      connection,
      'getAlbum.view',
      extraQueryParameters: {'id': albumId},
    );
    return _songsFromContainer(connection, response['album'], 'song');
  }

  Future<List<NavidromeBrowserItem>> playlists(
    NavidromeConnection connection,
  ) async {
    final response = await _getSubsonicResponse(
      connection,
      'getPlaylists.view',
    );
    return _itemsFromContainer(
      response['playlists'],
      'playlist',
      _playlistItemFromJson,
    );
  }

  Future<List<MusicMetadata>> playlistSongs(
    NavidromeConnection connection,
    String playlistId,
  ) async {
    final response = await _getSubsonicResponse(
      connection,
      'getPlaylist.view',
      extraQueryParameters: {'id': playlistId},
    );
    return _songsFromContainer(connection, response['playlist'], 'entry');
  }

  Future<List<NavidromeBrowserItem>> musicFolders(
    NavidromeConnection connection,
  ) async {
    final response = await _getSubsonicResponse(
      connection,
      'getMusicFolders.view',
    );
    return _itemsFromContainer(
      response['musicFolders'],
      'musicFolder',
      _folderItemFromJson,
    );
  }

  Future<List<NavidromeBrowserItem>> genres(
    NavidromeConnection connection,
  ) async {
    final response = await _getSubsonicResponse(connection, 'getGenres.view');
    return _itemsFromContainer(response['genres'], 'genre', _genreItemFromJson);
  }

  Future<List<MusicMetadata>> songsByGenre(
    NavidromeConnection connection,
    String genre,
  ) async {
    final response = await _getSubsonicResponse(
      connection,
      'getSongsByGenre.view',
      extraQueryParameters: {'genre': genre, 'count': '100'},
    );
    return _songsFromContainer(connection, response['songsByGenre'], 'song');
  }

  Future<List<MusicMetadata>> serverNowPlaying(
    NavidromeConnection connection,
  ) async {
    final response = await _getSubsonicResponse(
      connection,
      'getNowPlaying.view',
    );
    return _songsFromContainer(connection, response['nowPlaying'], 'entry');
  }

  Future<String?> lyrics(
    NavidromeConnection connection,
    MusicMetadata song,
  ) async {
    final artist = song.getTrackArtistNames;
    final title = song.getTrackName;
    final response = await _getSubsonicResponse(
      connection,
      'getLyrics.view',
      extraQueryParameters: {'artist': artist, 'title': title},
    );
    final lyrics = response['lyrics'];
    if (lyrics is! Map<String, dynamic>) {
      return null;
    }
    final value = lyrics['value']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String> scanStatus(NavidromeConnection connection) async {
    final response = await _getSubsonicResponse(
      connection,
      'getScanStatus.view',
    );
    return _scanStatusText(response['scanStatus']);
  }

  Future<String> startScan(NavidromeConnection connection) async {
    final response = await _getSubsonicResponse(connection, 'startScan.view');
    return _scanStatusText(response['scanStatus']);
  }

  Future<void> starSong(
    NavidromeConnection connection,
    MusicMetadata song,
  ) async {
    final id = _songIdFromMetadata(song);
    if (id == null) {
      throw const NavidromeServiceException('Missing Navidrome song id.');
    }
    await _getSubsonicResponse(
      connection,
      'star.view',
      extraQueryParameters: {'id': id},
    );
  }

  Future<void> unstarSong(
    NavidromeConnection connection,
    MusicMetadata song,
  ) async {
    final id = _songIdFromMetadata(song);
    if (id == null) {
      throw const NavidromeServiceException('Missing Navidrome song id.');
    }
    await _getSubsonicResponse(
      connection,
      'unstar.view',
      extraQueryParameters: {'id': id},
    );
  }

  Future<void> setSongRating(
    NavidromeConnection connection,
    MusicMetadata song,
    int rating,
  ) async {
    final id = _songIdFromMetadata(song);
    if (id == null) {
      throw const NavidromeServiceException('Missing Navidrome song id.');
    }
    await _getSubsonicResponse(
      connection,
      'setRating.view',
      extraQueryParameters: {'id': id, 'rating': rating.clamp(0, 5).toString()},
    );
  }

  Future<void> scrobble(
    NavidromeConnection connection,
    MusicMetadata song,
  ) async {
    final id = _songIdFromMetadata(song);
    if (id == null) {
      return;
    }
    await _getSubsonicResponse(
      connection,
      'scrobble.view',
      extraQueryParameters: {'id': id, 'submission': 'true'},
    );
  }

  Future<Map<String, dynamic>> _getSubsonicResponse(
    NavidromeConnection connection,
    String endpoint, {
    Map<String, String> extraQueryParameters = const {},
  }) async {
    final uri = _buildUri(
      connection,
      endpoint,
      extraQueryParameters: extraQueryParameters,
      includeJsonFormat: true,
    );
    final request = await _httpClient.getUrl(uri);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NavidromeServiceException(
        'Navidrome returned HTTP ${response.statusCode}.',
      );
    }

    final decodedJson = jsonDecode(responseBody);
    if (decodedJson is! Map<String, dynamic>) {
      throw const NavidromeServiceException('Navidrome returned invalid JSON.');
    }
    final subsonicResponse = decodedJson['subsonic-response'];
    if (subsonicResponse is! Map<String, dynamic>) {
      throw const NavidromeServiceException(
        'Navidrome returned an invalid Subsonic response.',
      );
    }

    if (subsonicResponse['status'] != 'ok') {
      final error = subsonicResponse['error'];
      final message = error is Map<String, dynamic>
          ? error['message']?.toString()
          : null;
      throw NavidromeServiceException(
        message ?? 'Navidrome rejected the request.',
      );
    }

    return subsonicResponse;
  }

  MusicMetadata _songMetadataFromJson(
    NavidromeConnection connection,
    Map<String, dynamic> songJson,
    int index,
  ) {
    final songId = songJson['id']?.toString();
    final coverArtId = songJson['coverArt']?.toString();
    final durationSeconds = _intFromJson(songJson['duration']);
    final genre = songJson['genre']?.toString().trim();

    return MusicMetadata(
      trackName: songJson['title']?.toString(),
      trackArtistNames: _artistsFromJson(songJson['artist']),
      albumName: songJson['album']?.toString(),
      albumArtistName: songJson['albumArtist']?.toString(),
      trackNumber: _intFromJson(songJson['track']),
      year: _intFromJson(songJson['year']),
      genres: genre == null || genre.isEmpty ? const [] : [genre],
      discNumber: _intFromJson(songJson['discNumber']),
      trackDuration: durationSeconds == null ? null : durationSeconds * 1000,
      filePath: songId == null
          ? null
          : _buildUri(
              connection,
              'stream.view',
              extraQueryParameters: {'id': songId},
            ).toString(),
      thumbnailPath: coverArtId == null
          ? null
          : _buildUri(
              connection,
              'getCoverArt.view',
              extraQueryParameters: {'id': coverArtId},
            ).toString(),
      originalSongIndex: -index - 1,
      isOnDevice: false,
    );
  }

  List<MusicMetadata> _songsFromContainer(
    NavidromeConnection connection,
    dynamic container,
    String key,
  ) {
    if (container is! Map<String, dynamic>) {
      return const [];
    }
    final songsJson = container[key];
    if (songsJson is! List) {
      return const [];
    }
    return [
      for (var index = 0; index < songsJson.length; index++)
        if (songsJson[index] is Map<String, dynamic>)
          _songMetadataFromJson(
            connection,
            songsJson[index] as Map<String, dynamic>,
            index,
          ),
    ];
  }

  List<NavidromeBrowserItem> _itemsFromContainer(
    dynamic container,
    String key,
    NavidromeBrowserItem Function(Map<String, dynamic>) mapper,
  ) {
    if (container is! Map<String, dynamic>) {
      return const [];
    }
    final itemsJson = container[key];
    if (itemsJson is! List) {
      return const [];
    }
    return [
      for (final itemJson in itemsJson)
        if (itemJson is Map<String, dynamic>) mapper(itemJson),
    ];
  }

  NavidromeBrowserItem _artistItemFromJson(Map<String, dynamic> artistJson) {
    final id = artistJson['id']?.toString() ?? '';
    final name = artistJson['name']?.toString() ?? 'Unknown Artist';
    final albumCount = _intFromJson(artistJson['albumCount']);
    return NavidromeBrowserItem.artist(
      id: id,
      title: name,
      subtitle: albumCount == null ? null : '$albumCount albums',
    );
  }

  NavidromeBrowserItem _albumItemFromJson(Map<String, dynamic> albumJson) {
    final id = albumJson['id']?.toString() ?? '';
    final title =
        albumJson['name']?.toString() ??
        albumJson['title']?.toString() ??
        'Unknown Album';
    final artist = albumJson['artist']?.toString();
    final songCount = _intFromJson(albumJson['songCount']);
    final year = albumJson['year']?.toString();
    final parts = [
      if (artist != null && artist.trim().isNotEmpty) artist,
      if (year != null && year.trim().isNotEmpty) year,
      if (songCount != null) '$songCount songs',
    ];
    return NavidromeBrowserItem.album(
      id: id,
      title: title,
      subtitle: parts.isEmpty ? null : parts.join(' • '),
    );
  }

  NavidromeBrowserItem _playlistItemFromJson(
    Map<String, dynamic> playlistJson,
  ) {
    final id = playlistJson['id']?.toString() ?? '';
    final title = playlistJson['name']?.toString() ?? 'Untitled Playlist';
    final songCount = _intFromJson(playlistJson['songCount']);
    return NavidromeBrowserItem.playlist(
      id: id,
      title: title,
      subtitle: songCount == null ? null : '$songCount songs',
    );
  }

  NavidromeBrowserItem _genreItemFromJson(Map<String, dynamic> genreJson) {
    final name =
        genreJson['value']?.toString() ??
        genreJson['name']?.toString() ??
        'Unknown Genre';
    final songCount = _intFromJson(genreJson['songCount']);
    final albumCount = _intFromJson(genreJson['albumCount']);
    final parts = [
      if (songCount != null) '$songCount songs',
      if (albumCount != null) '$albumCount albums',
    ];
    return NavidromeBrowserItem.genre(
      id: name,
      title: name,
      subtitle: parts.isEmpty ? null : parts.join(' • '),
    );
  }

  NavidromeBrowserItem _folderItemFromJson(Map<String, dynamic> folderJson) {
    final id = folderJson['id']?.toString() ?? '';
    final name = folderJson['name']?.toString() ?? 'Music Folder';
    return NavidromeBrowserItem.folder(id: id, title: name);
  }

  String _scanStatusText(dynamic scanStatus) {
    if (scanStatus is! Map<String, dynamic>) {
      return 'Scan status unavailable.';
    }
    final scanning = scanStatus['scanning'] == true;
    final count = _intFromJson(scanStatus['count']);
    final lastScan = scanStatus['lastScan']?.toString();
    final parts = [
      scanning ? 'Scanning' : 'Not scanning',
      if (count != null) '$count files',
      if (lastScan != null && lastScan.isNotEmpty) 'last scan $lastScan',
    ];
    return parts.join(' • ');
  }

  String? _songIdFromMetadata(MusicMetadata song) {
    final filePath = song.filePath;
    if (filePath == null) {
      return null;
    }
    final uri = Uri.tryParse(filePath);
    return uri?.queryParameters['id'];
  }

  Uri _buildUri(
    NavidromeConnection connection,
    String endpoint, {
    Map<String, String> extraQueryParameters = const {},
    bool includeJsonFormat = false,
  }) {
    final normalizedConnection = connection.normalized();
    final baseUri = Uri.parse(normalizedConnection.serverUrl);
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final token = md5
        .convert(utf8.encode(normalizedConnection.password + salt))
        .toString();
    return baseUri.replace(
      pathSegments: [
        ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
        'rest',
        endpoint,
      ],
      queryParameters: {
        'u': normalizedConnection.username,
        't': token,
        's': salt,
        'v': _apiVersion,
        'c': _clientName,
        if (includeJsonFormat) 'f': 'json',
        ...extraQueryParameters,
      },
    );
  }

  List<String>? _artistsFromJson(dynamic value) {
    final artist = value?.toString().trim();
    if (artist == null || artist.isEmpty) {
      return null;
    }
    return [artist];
  }

  int? _intFromJson(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
