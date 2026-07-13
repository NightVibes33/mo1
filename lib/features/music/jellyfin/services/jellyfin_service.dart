import 'dart:convert';
import 'dart:io';

import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/features/music/jellyfin/models/jellyfin_browser_item.dart';
import 'package:dope/features/music/jellyfin/models/jellyfin_connection.dart';

class JellyfinServiceException implements Exception {
  final String message;

  const JellyfinServiceException(this.message);

  @override
  String toString() => message;
}

class JellyfinService {
  static const String _clientName = 'dope';
  static const String _clientVersion = '3.0.0';
  static const String _deviceName = 'iOS';

  final HttpClient _httpClient;

  JellyfinService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  Future<JellyfinConnection> authenticate({
    required String serverUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final cleanServerUrl = _normalizeServerUrl(serverUrl);
    final body = jsonEncode({'Username': username.trim(), 'Pw': password});
    final response = await _postJson(
      cleanServerUrl,
      '/Users/AuthenticateByName',
      body: body,
      deviceId: deviceId,
    );
    final user = response['User'];
    final token = response['AccessToken']?.toString();
    final serverName = response['ServerName']?.toString() ?? 'Jellyfin';
    final userId = user is Map<String, dynamic> ? user['Id']?.toString() : null;

    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      throw const JellyfinServiceException('Jellyfin login returned no token.');
    }

    return JellyfinConnection(
      serverUrl: cleanServerUrl,
      username: username.trim(),
      accessToken: token,
      userId: userId,
      serverName: serverName,
      deviceId: deviceId,
    ).normalized();
  }

  Future<String> serverInfo(JellyfinConnection connection) async {
    final response = await _getJson(connection, '/System/Info/Public');
    final name = response['ServerName']?.toString() ?? connection.serverName;
    final version = response['Version']?.toString();
    return version == null || version.isEmpty
        ? '$name • ${connection.audioQuality.label}'
        : '$name • $version • ${connection.audioQuality.label}';
  }

  Future<List<JellyfinBrowserItem>> musicLibraries(
    JellyfinConnection connection,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Views',
    );
    return _items(response)
        .where((item) => item['CollectionType']?.toString() == 'music')
        .map(_folderItemFromJson)
        .toList(growable: false);
  }


  Future<List<MusicMetadata>> librarySongs(
    JellyfinConnection connection,
    String libraryId,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'ParentId': libraryId,
        'Recursive': 'true',
        'IncludeItemTypes': 'Audio',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': _itemFields,
        'Limit': '500',
      },
    );
    return _songsFromItems(connection, _items(response));
  }

  Future<List<JellyfinBrowserItem>> searchResults(
    JellyfinConnection connection,
    String query,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'Recursive': 'true',
        'SearchTerm': query.trim(),
        'IncludeItemTypes': 'Audio,MusicAlbum,MusicArtist,Playlist',
        'Fields': _itemFields,
        'Limit': '80',
      },
    );
    final results = <JellyfinBrowserItem>[];
    final items = _items(response);
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final type = item['Type']?.toString();
      if (type == 'Audio') {
        results.add(_songItemFromJson(connection, item, index, prefix: 'Song'));
      } else if (type == 'MusicAlbum') {
        final album = _albumItemFromJson(item);
        results.add(
          JellyfinBrowserItem.album(
            id: album.id,
            title: album.title,
            subtitle: album.subtitle == null ? 'Album' : 'Album • ${album.subtitle}',
          ),
        );
      } else if (type == 'MusicArtist' || type == 'Person') {
        final artist = _artistItemFromJson(item);
        results.add(
          JellyfinBrowserItem.artist(
            id: artist.id,
            title: artist.title,
            subtitle: artist.subtitle == null
                ? 'Artist'
                : 'Artist • ${artist.subtitle}',
          ),
        );
      } else if (type == 'Playlist') {
        final playlist = _playlistItemFromJson(item);
        results.add(
          JellyfinBrowserItem.playlist(
            id: playlist.id,
            title: playlist.title,
            subtitle: playlist.subtitle == null
                ? 'Playlist'
                : 'Playlist • ${playlist.subtitle}',
          ),
        );
      }
    }
    return results;
  }

  Future<List<MusicMetadata>> songs(JellyfinConnection connection) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'Recursive': 'true',
        'IncludeItemTypes': 'Audio',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': _itemFields,
        'Limit': '500',
      },
    );
    return _songsFromItems(connection, _items(response));
  }

  Future<List<JellyfinBrowserItem>> albums(JellyfinConnection connection) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'Recursive': 'true',
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': _itemFields,
        'Limit': '300',
      },
    );
    return _items(response).map(_albumItemFromJson).toList(growable: false);
  }

  Future<List<JellyfinBrowserItem>> artists(
    JellyfinConnection connection,
  ) async {
    final response = await _getJson(
      connection,
      '/Artists/AlbumArtists',
      queryParameters: {
        'userId': connection.userId,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': '300',
      },
    );
    return _items(response).map(_artistItemFromJson).toList(growable: false);
  }

  Future<List<MusicMetadata>> artistSongs(
    JellyfinConnection connection,
    String artistId,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'Recursive': 'true',
        'IncludeItemTypes': 'Audio',
        'ArtistIds': artistId,
        'SortBy': 'Album,ParentIndexNumber,IndexNumber,SortName',
        'SortOrder': 'Ascending',
        'Fields': _itemFields,
        'Limit': '300',
      },
    );
    return _songsFromItems(connection, _items(response));
  }

  Future<List<MusicMetadata>> albumSongs(
    JellyfinConnection connection,
    String albumId,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'ParentId': albumId,
        'IncludeItemTypes': 'Audio',
        'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
        'SortOrder': 'Ascending',
        'Fields': _itemFields,
      },
    );
    return _songsFromItems(connection, _items(response));
  }

  Future<List<JellyfinBrowserItem>> playlists(
    JellyfinConnection connection,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'Recursive': 'true',
        'IncludeItemTypes': 'Playlist',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': _itemFields,
        'Limit': '300',
      },
    );
    return _items(response).map(_playlistItemFromJson).toList(growable: false);
  }

  Future<List<MusicMetadata>> playlistSongs(
    JellyfinConnection connection,
    String playlistId,
  ) async {
    final response = await _getJson(
      connection,
      '/Playlists/$playlistId/Items',
      queryParameters: {'userId': connection.userId, 'Fields': _itemFields},
    );
    return _songsFromItems(
      connection,
      _items(response).where((item) => item['Type']?.toString() == 'Audio'),
    );
  }

  Future<List<JellyfinBrowserItem>> favorites(
    JellyfinConnection connection,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'Recursive': 'true',
        'Filters': 'IsFavorite',
        'IncludeItemTypes': 'Audio,MusicAlbum,MusicArtist',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': _itemFields,
        'Limit': '300',
      },
    );
    final results = <JellyfinBrowserItem>[];
    final items = _items(response);
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final type = item['Type']?.toString();
      if (type == 'Audio') {
        results.add(_songItemFromJson(connection, item, index, prefix: 'Favorite'));
      } else if (type == 'MusicAlbum') {
        results.add(_albumItemFromJson(item));
      } else if (type == 'MusicArtist' || type == 'Person') {
        results.add(_artistItemFromJson(item));
      }
    }
    return results;
  }

  Future<List<MusicMetadata>> recentlyAdded(
    JellyfinConnection connection,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'Recursive': 'true',
        'IncludeItemTypes': 'Audio',
        'SortBy': 'DateCreated',
        'SortOrder': 'Descending',
        'Fields': _itemFields,
        'Limit': '100',
      },
    );
    return _songsFromItems(connection, _items(response));
  }

  Future<List<MusicMetadata>> randomSongs(
    JellyfinConnection connection,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'Recursive': 'true',
        'IncludeItemTypes': 'Audio',
        'SortBy': 'Random',
        'Fields': _itemFields,
        'Limit': '100',
      },
    );
    return _songsFromItems(connection, _items(response));
  }

  Future<List<MusicMetadata>> recentlyPlayed(
    JellyfinConnection connection,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items',
      queryParameters: {
        'Recursive': 'true',
        'IncludeItemTypes': 'Audio',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Fields': _itemFields,
        'Limit': '100',
      },
    );
    return _songsFromItems(connection, _items(response));
  }

  Future<List<MusicMetadata>> resumableSongs(
    JellyfinConnection connection,
  ) async {
    final response = await _getJson(
      connection,
      '/Users/${connection.userId}/Items/Resume',
      queryParameters: {
        'IncludeItemTypes': 'Audio',
        'Fields': _itemFields,
        'Limit': '100',
      },
    );
    return _songsFromItems(connection, _items(response));
  }

  Future<void> createPlaylist(
    JellyfinConnection connection,
    String name,
  ) async {
    await _postJson(
      connection.serverUrl,
      '/Playlists',
      connection: connection,
      queryParameters: {'userId': connection.userId},
      body: jsonEncode({'Name': name.trim(), 'MediaType': 'Audio'}),
    );
  }

  Future<void> deletePlaylist(
    JellyfinConnection connection,
    String playlistId,
  ) async {
    await _deleteJson(connection, '/Items/$playlistId');
  }

  Future<void> addSongToPlaylist(
    JellyfinConnection connection,
    String playlistId,
    MusicMetadata song,
  ) async {
    final id = _songIdFromMetadata(song);
    if (id == null) {
      throw const JellyfinServiceException('Missing Jellyfin song id.');
    }
    await _postJson(
      connection.serverUrl,
      '/Playlists/$playlistId/Items',
      connection: connection,
      queryParameters: {'ids': id, 'userId': connection.userId},
    );
  }

  Future<void> favoriteSong(
    JellyfinConnection connection,
    MusicMetadata song,
  ) async {
    final id = _songIdFromMetadata(song);
    if (id == null) {
      throw const JellyfinServiceException('Missing Jellyfin song id.');
    }
    await _postJson(connection.serverUrl, '/Users/${connection.userId}/FavoriteItems/$id', connection: connection);
  }

  Future<void> unfavoriteSong(
    JellyfinConnection connection,
    MusicMetadata song,
  ) async {
    final id = _songIdFromMetadata(song);
    if (id == null) {
      throw const JellyfinServiceException('Missing Jellyfin song id.');
    }
    await _deleteJson(connection, '/Users/${connection.userId}/FavoriteItems/$id');
  }

  Future<void> favoriteItem(
    JellyfinConnection connection,
    String itemId,
  ) async {
    await _postJson(
      connection.serverUrl,
      '/Users/${connection.userId}/FavoriteItems/$itemId',
      connection: connection,
    );
  }

  Future<void> unfavoriteItem(
    JellyfinConnection connection,
    String itemId,
  ) async {
    await _deleteJson(connection, '/Users/${connection.userId}/FavoriteItems/$itemId');
  }

  Future<void> reportPlaybackStart(
    JellyfinConnection connection,
    MusicMetadata song,
  ) async {
    final id = _songIdFromMetadata(song);
    if (id == null) {
      return;
    }
    await _postJson(
      connection.serverUrl,
      '/Sessions/Playing',
      connection: connection,
      body: jsonEncode({'ItemId': id, 'CanSeek': true}),
    );
  }

  Uri streamUri(JellyfinConnection connection, String itemId) {
    final maxBitrate = connection.audioQuality.maxStreamingBitrate;
    return _buildUri(
      connection.serverUrl,
      '/Audio/$itemId/stream',
      queryParameters: {
        'api_key': connection.accessToken,
        if (maxBitrate == null) 'static': 'true',
        if (maxBitrate != null) 'static': 'false',
        if (maxBitrate != null) 'maxStreamingBitrate': maxBitrate,
      },
    );
  }

  Uri artworkUri(JellyfinConnection connection, String itemId) {
    return _buildUri(
      connection.serverUrl,
      '/Items/$itemId/Images/Primary',
      queryParameters: {
        'fillWidth': '800',
        'fillHeight': '800',
        'quality': '90',
        'api_key': connection.accessToken,
      },
    );
  }

  Future<Map<String, dynamic>> _getJson(
    JellyfinConnection connection,
    String path, {
    Map<String, String> queryParameters = const {},
  }) async {
    final uri = _buildUri(
      connection.serverUrl,
      path,
      queryParameters: queryParameters,
    );
    final request = await _httpClient.getUrl(uri);
    _applyHeaders(request, connection: connection);
    final response = await request.close();
    return _decodeResponse(response, 'Jellyfin request failed');
  }

  Future<Map<String, dynamic>> _postJson(
    String serverUrl,
    String path, {
    String? body,
    JellyfinConnection? connection,
    String? deviceId,
    Map<String, String> queryParameters = const {},
  }) async {
    final uri = _buildUri(serverUrl, path, queryParameters: queryParameters);
    final request = await _httpClient.postUrl(uri);
    _applyHeaders(request, connection: connection, deviceId: deviceId);
    request.headers.contentType = ContentType.json;
    if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    return _decodeResponse(response, 'Jellyfin request failed');
  }

  Future<Map<String, dynamic>> _deleteJson(
    JellyfinConnection connection,
    String path,
  ) async {
    final uri = _buildUri(connection.serverUrl, path);
    final request = await _httpClient.deleteUrl(uri);
    _applyHeaders(request, connection: connection);
    final response = await request.close();
    return _decodeResponse(response, 'Jellyfin request failed');
  }

  Future<Map<String, dynamic>> _decodeResponse(
    HttpClientResponse response,
    String fallbackMessage,
  ) async {
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JellyfinServiceException(
        'Jellyfin returned HTTP ${response.statusCode}.',
      );
    }
    if (responseBody.trim().isEmpty) {
      return const {};
    }
    final decodedJson = jsonDecode(responseBody);
    if (decodedJson is Map<String, dynamic>) {
      return decodedJson;
    }
    throw JellyfinServiceException(fallbackMessage);
  }

  void _applyHeaders(
    HttpClientRequest request, {
    JellyfinConnection? connection,
    String? deviceId,
  }) {
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      HttpHeaders.authorizationHeader,
      _authorizationHeader(connection: connection, deviceId: deviceId),
    );
  }

  String _authorizationHeader({
    JellyfinConnection? connection,
    String? deviceId,
  }) {
    final id = connection?.deviceId ?? deviceId ?? 'dope-ios';
    final token = connection?.accessToken;
    final parts = [
      'MediaBrowser Client="$_clientName"',
      'Device="$_deviceName"',
      'DeviceId="$id"',
      'Version="$_clientVersion"',
      if (token != null && token.isNotEmpty) 'Token="$token"',
    ];
    return parts.join(', ');
  }

  bool _isExplicitSong(Map<String, dynamic> songJson) {
    return parseExplicitFlag(songJson['OfficialRating']) ||
        parseExplicitFlag(songJson['CustomRating']) ||
        parseExplicitFlag(songJson['CriticRating']) ||
        parseExplicitFlag(songJson['InheritedParentalRatingValue']);
  }

  MusicMetadata _songMetadataFromJson(
    JellyfinConnection connection,
    Map<String, dynamic> songJson,
    int index,
  ) {
    final itemId = songJson['Id']?.toString();
    final albumId = songJson['AlbumId']?.toString();
    final imageId = albumId?.isNotEmpty == true ? albumId : itemId;
    final runtimeTicks = _intFromJson(songJson['RunTimeTicks']);
    final productionYear = _intFromJson(songJson['ProductionYear']);
    final genres = _stringList(songJson['Genres']);
    final artists = _artistsFromJson(songJson['Artists']) ??
        _artistsFromJson(songJson['ArtistItems']);

    return MusicMetadata(
      trackName: songJson['Name']?.toString(),
      trackArtistNames: artists,
      albumName: songJson['Album']?.toString(),
      albumArtistName: songJson['AlbumArtist']?.toString(),
      trackNumber: _intFromJson(songJson['IndexNumber']),
      year: productionYear,
      genres: genres,
      discNumber: _intFromJson(songJson['ParentIndexNumber']),
      trackDuration: runtimeTicks == null ? null : runtimeTicks ~/ 10000,
      bitrate: _intFromJson(songJson['Bitrate']),
      filePath: itemId == null ? null : streamUri(connection, itemId).toString(),
      thumbnailPath: imageId == null ? null : artworkUri(connection, imageId).toString(),
      originalSongIndex: -100000 - index,
      isOnDevice: false,
      rating: _userData(songJson)?['IsFavorite'] == true ? 5 : 0,
      isExplicit: _isExplicitSong(songJson),
      sourceCreatedAtEpochMs: _epochMsFromDate(songJson['DateCreated']),
    );
  }

  JellyfinBrowserItem _songItemFromJson(
    JellyfinConnection connection,
    Map<String, dynamic> songJson,
    int index, {
    String prefix = 'Song',
  }) {
    final song = _songMetadataFromJson(connection, songJson, index);
    return JellyfinBrowserItem.song(
      id: songJson['Id']?.toString() ?? '',
      title: song.getTrackName,
      subtitle: song.getTrackArtistNames == null
          ? prefix
          : '$prefix • ${song.getTrackArtistNames}',
      song: song,
    );
  }

  List<MusicMetadata> _songsFromItems(
    JellyfinConnection connection,
    Iterable<Map<String, dynamic>> items,
  ) {
    final songs = <MusicMetadata>[];
    var index = 0;
    for (final item in items) {
      songs.add(_songMetadataFromJson(connection, item, index));
      index++;
    }
    return songs;
  }

  JellyfinBrowserItem _artistItemFromJson(Map<String, dynamic> artistJson) {
    final id = artistJson['Id']?.toString() ?? '';
    final name = artistJson['Name']?.toString() ?? 'Unknown Artist';
    final count = _intFromJson(artistJson['ChildCount']);
    return JellyfinBrowserItem.artist(
      id: id,
      title: name,
      subtitle: count == null ? null : '$count items',
    );
  }

  JellyfinBrowserItem _albumItemFromJson(Map<String, dynamic> albumJson) {
    final id = albumJson['Id']?.toString() ?? '';
    final title = albumJson['Name']?.toString() ?? 'Unknown Album';
    final artist = albumJson['AlbumArtist']?.toString();
    final year = albumJson['ProductionYear']?.toString();
    final parts = [
      if (artist != null && artist.trim().isNotEmpty) artist,
      if (year != null && year.trim().isNotEmpty) year,
    ];
    return JellyfinBrowserItem.album(
      id: id,
      title: title,
      subtitle: parts.isEmpty ? null : parts.join(' • '),
    );
  }

  JellyfinBrowserItem _playlistItemFromJson(Map<String, dynamic> playlistJson) {
    final id = playlistJson['Id']?.toString() ?? '';
    final title = playlistJson['Name']?.toString() ?? 'Untitled Playlist';
    final count = _intFromJson(playlistJson['ChildCount']);
    return JellyfinBrowserItem.playlist(
      id: id,
      title: title,
      subtitle: count == null ? null : '$count items',
    );
  }

  JellyfinBrowserItem _folderItemFromJson(Map<String, dynamic> folderJson) {
    final id = folderJson['Id']?.toString() ?? '';
    final name = folderJson['Name']?.toString() ?? 'Music Library';
    return JellyfinBrowserItem.folder(id: id, title: name);
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> response) {
    final items = response['Items'];
    if (items is! List) {
      return const [];
    }
    return items.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Map<String, dynamic>? _userData(Map<String, dynamic> item) {
    final value = item['UserData'];
    return value is Map<String, dynamic> ? value : null;
  }

  String? _songIdFromMetadata(MusicMetadata song) {
    final path = song.filePath;
    if (path == null) {
      return null;
    }
    final match = RegExp(r'/Audio/([^/]+)/stream').firstMatch(path);
    return match == null ? null : Uri.decodeComponent(match.group(1)!);
  }

  Uri _buildUri(
    String serverUrl,
    String path, {
    Map<String, String> queryParameters = const {},
  }) {
    final baseUri = Uri.parse(_normalizeServerUrl(serverUrl));
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final joinedPath = [
      if (baseUri.path.isNotEmpty) baseUri.path.replaceFirst(RegExp(r'/+$'), ''),
      cleanPath,
    ].where((part) => part.isNotEmpty).join('/');
    return baseUri.replace(
      path: '/$joinedPath',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  String _normalizeServerUrl(String serverUrl) {
    final clean = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (clean.isEmpty) {
      throw const JellyfinServiceException('Enter a Jellyfin server URL.');
    }
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      return 'https://$clean';
    }
    return clean;
  }

  List<String>? _artistsFromJson(dynamic value) {
    if (value is List) {
      final names = <String>[];
      for (final item in value) {
        if (item is String && item.trim().isNotEmpty) {
          names.add(item.trim());
        } else if (item is Map<String, dynamic>) {
          final name = item['Name']?.toString().trim();
          if (name != null && name.isNotEmpty) {
            names.add(name);
          }
        }
      }
      return names.isEmpty ? null : names;
    }
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : [text];
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item?.toString().trim())
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  int? _intFromJson(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  int? _epochMsFromDate(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text)?.millisecondsSinceEpoch;
  }

  static const String _itemFields =
      'Genres,DateCreated,MediaSources,Path,Overview,ParentId,AlbumArtist,Artists,ArtistItems,UserData,Bitrate';
}
