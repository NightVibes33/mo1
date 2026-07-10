import 'dart:async';

import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/core/widgets/display_list_tile.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/music/navidrome/models/navidrome_browser_item.dart';
import 'package:dope/features/music/navidrome/models/navidrome_connection.dart';
import 'package:dope/features/music/navidrome/providers/navidrome_connection_provider.dart';
import 'package:dope/features/music/navidrome/providers/navidrome_service_provider.dart';
import 'package:dope/features/music/navidrome/services/navidrome_service.dart';
import 'package:dope/features/music/songs/widgets/song_list_tile.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class NavidromeScreen extends ConsumerStatefulWidget {
  const NavidromeScreen({super.key});

  @override
  ConsumerState<NavidromeScreen> createState() => _NavidromeScreenState();
}

class _NavidromePage {
  final String title;
  final List<NavidromeBrowserItem> items;

  const _NavidromePage({required this.title, required this.items});
}

class _NavidromeScreenState extends ConsumerState<NavidromeScreen>
    with CustomScreen {
  static const String _connectAction = 'connect';
  static const String _searchAction = 'search';
  static const String _randomSongsAction = 'randomSongs';
  static const String _starredSongsAction = 'starredSongs';
  static const String _newestAlbumsAction = 'newestAlbums';
  static const String _recentAlbumsAction = 'recentAlbums';
  static const String _frequentAlbumsAction = 'frequentAlbums';
  static const String _artistsAction = 'artists';
  static const String _playlistsAction = 'playlists';
  static const String _genresAction = 'genres';
  static const String _nowPlayingAction = 'nowPlaying';
  static const String _foldersAction = 'folders';
  static const String _scanStatusAction = 'scanStatus';
  static const String _startScanAction = 'startScan';
  static const String _disconnectAction = 'disconnect';
  static const String _backAction = 'back';

  final List<_NavidromePage> _pageStack = [];
  bool _isBusy = false;
  String _query = '';
  String? _statusText;
  String? _errorText;

  @override
  double get displayTileHeight => 54;

  @override
  String get routeName => Routes.navidrome.name;

  @override
  List<NavidromeBrowserItem> get displayItems => _currentItems;

  List<NavidromeBrowserItem> get _currentItems {
    final connection = ref.read(navidromeConnectionProvider);
    if (_pageStack.isNotEmpty) {
      return _pageStack.last.items;
    }
    return _homeItems(connection);
  }

  List<NavidromeBrowserItem> _homeItems(NavidromeConnection? connection) {
    if (connection == null) {
      return const [
        NavidromeBrowserItem.action(
          id: _connectAction,
          title: 'Connect Navidrome',
        ),
      ];
    }

    return const [
      NavidromeBrowserItem.action(
        id: _connectAction,
        title: 'Connect Navidrome',
        subtitle: 'Update server or login',
      ),
      NavidromeBrowserItem.action(id: _searchAction, title: 'Search Navidrome'),
      NavidromeBrowserItem.action(
        id: _randomSongsAction,
        title: 'Random Songs',
      ),
      NavidromeBrowserItem.action(
        id: _starredSongsAction,
        title: 'Starred Songs',
      ),
      NavidromeBrowserItem.action(
        id: _newestAlbumsAction,
        title: 'Newest Albums',
      ),
      NavidromeBrowserItem.action(
        id: _recentAlbumsAction,
        title: 'Recently Played Albums',
      ),
      NavidromeBrowserItem.action(
        id: _frequentAlbumsAction,
        title: 'Most Played Albums',
      ),
      NavidromeBrowserItem.action(id: _artistsAction, title: 'Artists'),
      NavidromeBrowserItem.action(id: _playlistsAction, title: 'Playlists'),
      NavidromeBrowserItem.action(id: _genresAction, title: 'Genres'),
      NavidromeBrowserItem.action(
        id: _nowPlayingAction,
        title: 'Now Playing on Server',
      ),
      NavidromeBrowserItem.action(id: _foldersAction, title: 'Music Folders'),
      NavidromeBrowserItem.action(id: _scanStatusAction, title: 'Scan Status'),
      NavidromeBrowserItem.action(
        id: _startScanAction,
        title: 'Start Library Scan',
      ),
      NavidromeBrowserItem.action(
        id: _disconnectAction,
        title: 'Disconnect Server',
      ),
    ];
  }

  @override
  Future<void> onSelectPressed() => _onDisplayItemAction(selectedDisplayItem);

  Future<void> _onDisplayItemAction(int displayIndex) async {
    final items = _currentItems;
    if (displayIndex < 0 || displayIndex >= items.length) {
      return;
    }
    setState(() => selectedDisplayItem = displayIndex);
    final item = items[displayIndex];

    switch (item.type) {
      case NavidromeBrowserItemType.action:
        await _handleAction(item.id);
        break;
      case NavidromeBrowserItemType.artist:
        await _loadArtistAlbums(item);
        break;
      case NavidromeBrowserItemType.album:
        await _loadAlbumSongs(item);
        break;
      case NavidromeBrowserItemType.playlist:
        await _loadPlaylistSongs(item);
        break;
      case NavidromeBrowserItemType.genre:
        await _loadGenreSongs(item);
        break;
      case NavidromeBrowserItemType.folder:
        await _loadFolderAlbums(item);
        break;
      case NavidromeBrowserItemType.song:
        await _playSong(displayIndex);
        break;
    }
  }

  Future<void> _handleAction(String action) async {
    final connection = ref.read(navidromeConnectionProvider);
    switch (action) {
      case _connectAction:
        await _connectNavidrome(existingConnection: connection);
        break;
      case _searchAction:
        if (connection != null) {
          await _promptAndSearch(connection);
        }
        break;
      case _randomSongsAction:
        if (connection != null) {
          await _loadSongPage(
            title: 'Random Songs',
            loader: () =>
                ref.read(navidromeServiceProvider).randomSongs(connection),
          );
        }
        break;
      case _starredSongsAction:
        if (connection != null) {
          await _loadSongPage(
            title: 'Starred Songs',
            loader: () =>
                ref.read(navidromeServiceProvider).starredSongs(connection),
          );
        }
        break;
      case _newestAlbumsAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Newest Albums',
            loader: () => ref
                .read(navidromeServiceProvider)
                .albumList(connection, 'newest'),
          );
        }
        break;
      case _recentAlbumsAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Recently Played',
            loader: () => ref
                .read(navidromeServiceProvider)
                .albumList(connection, 'recent'),
          );
        }
        break;
      case _frequentAlbumsAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Most Played',
            loader: () => ref
                .read(navidromeServiceProvider)
                .albumList(connection, 'frequent'),
          );
        }
        break;
      case _artistsAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Navidrome Artists',
            loader: () =>
                ref.read(navidromeServiceProvider).artists(connection),
          );
        }
        break;
      case _playlistsAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Navidrome Playlists',
            loader: () =>
                ref.read(navidromeServiceProvider).playlists(connection),
          );
        }
        break;
      case _genresAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Navidrome Genres',
            loader: () => ref.read(navidromeServiceProvider).genres(connection),
          );
        }
        break;
      case _nowPlayingAction:
        if (connection != null) {
          await _loadSongPage(
            title: 'Server Now Playing',
            loader: () =>
                ref.read(navidromeServiceProvider).serverNowPlaying(connection),
          );
        }
        break;
      case _foldersAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Music Folders',
            loader: () =>
                ref.read(navidromeServiceProvider).musicFolders(connection),
          );
        }
        break;
      case _scanStatusAction:
        if (connection != null) {
          await _showScanStatus(connection, startScan: false);
        }
        break;
      case _startScanAction:
        if (connection != null) {
          await _showScanStatus(connection, startScan: true);
        }
        break;
      case _disconnectAction:
        await _disconnectNavidrome();
        break;
      case _backAction:
        _goBack();
        break;
    }
  }

  Future<void> _connectNavidrome({
    NavidromeConnection? existingConnection,
  }) async {
    final connection = await _promptForConnection(existingConnection);
    if (!mounted || connection == null) {
      return;
    }
    if (!connection.isComplete) {
      setState(() => _errorText = 'Enter server URL, username, and password.');
      return;
    }

    setState(() {
      _isBusy = true;
      _statusText = 'Connecting to Navidrome...';
      _errorText = null;
    });

    try {
      await ref.read(navidromeServiceProvider).ping(connection);
      await ref.read(navidromeConnectionProvider.notifier).save(connection);
      if (!mounted) {
        return;
      }
      setState(() {
        _isBusy = false;
        _pageStack.clear();
        _statusText = 'Connected. Pick a Navidrome section.';
        selectedDisplayItem = 1;
      });
    } on NavidromeServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Could not connect to Navidrome.');
    }
  }

  Future<NavidromeConnection?> _promptForConnection(
    NavidromeConnection? existingConnection,
  ) async {
    final serverController = TextEditingController(
      text: existingConnection?.serverUrl ?? '',
    );
    final usernameController = TextEditingController(
      text: existingConnection?.username ?? '',
    );
    final passwordController = TextEditingController(
      text: existingConnection?.password ?? '',
    );

    final connection = await showCupertinoDialog<NavidromeConnection>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Connect Navidrome'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              CupertinoTextField(
                controller: serverController,
                autofocus: existingConnection == null,
                clearButtonMode: OverlayVisibilityMode.editing,
                keyboardType: TextInputType.url,
                placeholder: 'https://music.example.com',
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: usernameController,
                clearButtonMode: OverlayVisibilityMode.editing,
                placeholder: 'Username',
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: passwordController,
                obscureText: true,
                placeholder: 'Password',
                onSubmitted: (_) => Navigator.of(context).pop(
                  NavidromeConnection(
                    serverUrl: serverController.text,
                    username: usernameController.text,
                    password: passwordController.text,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(
              NavidromeConnection(
                serverUrl: serverController.text,
                username: usernameController.text,
                password: passwordController.text,
              ),
            ),
            child: const Text('Connect'),
          ),
        ],
      ),
    );

    serverController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    return connection;
  }

  Future<void> _promptAndSearch(NavidromeConnection connection) async {
    final query = await _promptForSearchQuery();
    if (!mounted || query == null) {
      return;
    }
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() => _errorText = 'Enter a song, artist, or album.');
      return;
    }
    await _loadSongPage(
      title: 'Search: $cleanQuery',
      loader: () => ref
          .read(navidromeServiceProvider)
          .searchSongs(connection, cleanQuery),
      onLoaded: () => _query = cleanQuery,
    );
  }

  Future<String?> _promptForSearchQuery() async {
    final controller = TextEditingController(text: _query);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Search Navidrome'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            clearButtonMode: OverlayVisibilityMode.editing,
            placeholder: 'Song, artist, or album',
            textInputAction: TextInputAction.search,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _loadArtistAlbums(NavidromeBrowserItem artist) async {
    final connection = ref.read(navidromeConnectionProvider);
    if (connection == null) {
      return;
    }
    await _loadBrowserPage(
      title: artist.title,
      loader: () => ref
          .read(navidromeServiceProvider)
          .artistAlbums(connection, artist.id),
    );
  }

  Future<void> _loadAlbumSongs(NavidromeBrowserItem album) async {
    final connection = ref.read(navidromeConnectionProvider);
    if (connection == null) {
      return;
    }
    await _loadSongPage(
      title: album.title,
      loader: () =>
          ref.read(navidromeServiceProvider).albumSongs(connection, album.id),
    );
  }

  Future<void> _loadPlaylistSongs(NavidromeBrowserItem playlist) async {
    final connection = ref.read(navidromeConnectionProvider);
    if (connection == null) {
      return;
    }
    await _loadSongPage(
      title: playlist.title,
      loader: () => ref
          .read(navidromeServiceProvider)
          .playlistSongs(connection, playlist.id),
    );
  }

  Future<void> _loadFolderAlbums(NavidromeBrowserItem folder) async {
    final connection = ref.read(navidromeConnectionProvider);
    if (connection == null) {
      return;
    }
    await _loadBrowserPage(
      title: folder.title,
      loader: () => ref
          .read(navidromeServiceProvider)
          .albumList(
            connection,
            'alphabeticalByName',
            musicFolderId: folder.id,
          ),
    );
  }

  Future<void> _loadGenreSongs(NavidromeBrowserItem genre) async {
    final connection = ref.read(navidromeConnectionProvider);
    if (connection == null) {
      return;
    }
    await _loadSongPage(
      title: genre.title,
      loader: () =>
          ref.read(navidromeServiceProvider).songsByGenre(connection, genre.id),
    );
  }

  Future<void> _showScanStatus(
    NavidromeConnection connection, {
    required bool startScan,
  }) async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _statusText = startScan
          ? 'Starting library scan...'
          : 'Checking scan status...';
      _errorText = null;
    });
    try {
      final message = startScan
          ? await ref.read(navidromeServiceProvider).startScan(connection)
          : await ref.read(navidromeServiceProvider).scanStatus(connection);
      if (!mounted) {
        return;
      }
      setState(() {
        _isBusy = false;
        _statusText = message;
      });
    } on NavidromeServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Navidrome scan request failed.');
    }
  }

  Future<void> _loadBrowserPage({
    required String title,
    required Future<List<NavidromeBrowserItem>> Function() loader,
  }) async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _statusText = 'Loading $title...';
      _errorText = null;
    });

    try {
      final items = await loader();
      if (!mounted) {
        return;
      }
      setState(() {
        _isBusy = false;
        _pageStack.add(
          _NavidromePage(title: title, items: [_backItem, ...items]),
        );
        _statusText = items.isEmpty ? null : '${items.length} items';
        _errorText = items.isEmpty ? 'No Navidrome items found.' : null;
        selectedDisplayItem = items.isEmpty ? 0 : 1;
      });
    } on NavidromeServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Navidrome request failed.');
    }
  }

  Future<void> _loadSongPage({
    required String title,
    required Future<List<MusicMetadata>> Function() loader,
    VoidCallback? onLoaded,
  }) async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _statusText = 'Loading $title...';
      _errorText = null;
    });

    try {
      final songs = await loader();
      if (!mounted) {
        return;
      }
      onLoaded?.call();
      setState(() {
        _isBusy = false;
        _pageStack.add(
          _NavidromePage(
            title: title,
            items: [
              _backItem,
              for (final song in songs)
                NavidromeBrowserItem.song(
                  id: song.filePath ?? song.getTrackName,
                  title: song.getTrackName,
                  subtitle: song.getTrackArtistNames,
                  song: song,
                ),
            ],
          ),
        );
        _statusText = songs.isEmpty ? null : '${songs.length} songs';
        _errorText = songs.isEmpty ? 'No Navidrome songs found.' : null;
        selectedDisplayItem = songs.isEmpty ? 0 : 1;
      });
    } on NavidromeServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Navidrome request failed.');
    }
  }

  NavidromeBrowserItem get _backItem =>
      const NavidromeBrowserItem.action(id: _backAction, title: '< Back');

  Future<void> _playSong(int displayIndex) async {
    final songItems = _currentItems
        .where((item) => item.type == NavidromeBrowserItemType.song)
        .toList(growable: false);
    final selectedItem = _currentItems[displayIndex];
    final selectedSong = selectedItem.song;
    if (selectedSong == null) {
      return;
    }
    final songs = songItems
        .map((item) => item.song)
        .whereType<MusicMetadata>()
        .toList(growable: false);
    final songIndex = songs.indexWhere(
      (song) => song.filePath == selectedSong.filePath,
    );
    final didStart = await ref
        .read(audioPlayerServiceProvider.notifier)
        .playMetadataListAtIndex(metadataList: songs, index: songIndex);
    if (didStart && mounted) {
      unawaited(_scrobble(selectedSong));
      await context.pushNamed(Routes.nowPlaying.name);
    } else if (mounted) {
      setState(() => _errorText = 'Navidrome playback failed.');
    }
  }

  Future<void> _scrobble(MusicMetadata song) async {
    final connection = ref.read(navidromeConnectionProvider);
    if (connection == null) {
      return;
    }
    try {
      await ref.read(navidromeServiceProvider).scrobble(connection, song);
    } catch (_) {
      // Playback should not fail just because server history failed.
    }
  }

  Future<void> _showSongActions(NavidromeBrowserItem item) async {
    final song = item.song;
    final connection = ref.read(navidromeConnectionProvider);
    if (song == null || connection == null) {
      return;
    }

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(song.getTrackName),
        message: Text(song.getTrackArtistNames ?? 'Unknown Artist'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('star'),
            child: const Text('Star Song'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('unstar'),
            child: const Text('Unstar Song'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('rate5'),
            child: const Text('Rate 5 Stars'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('lyrics'),
            child: const Text('Show Lyrics'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }

    try {
      switch (action) {
        case 'star':
          await ref.read(navidromeServiceProvider).starSong(connection, song);
          _setStatus('Song starred.');
          break;
        case 'unstar':
          await ref.read(navidromeServiceProvider).unstarSong(connection, song);
          _setStatus('Song unstarred.');
          break;
        case 'rate5':
          await ref
              .read(navidromeServiceProvider)
              .setSongRating(connection, song, 5);
          _setStatus('Song rated 5 stars.');
          break;
        case 'lyrics':
          await _showLyrics(connection, song);
          break;
      }
    } on NavidromeServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Navidrome song action failed.');
    }
  }

  Future<void> _showLyrics(
    NavidromeConnection connection,
    MusicMetadata song,
  ) async {
    final lyrics = await ref
        .read(navidromeServiceProvider)
        .lyrics(connection, song);
    if (!mounted) {
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(song.getTrackName),
        content: Text(lyrics ?? 'No lyrics found on this Navidrome server.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _setStatus(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      _errorText = null;
      _statusText = message;
    });
  }

  void _goBack() {
    if (_pageStack.isEmpty) {
      return;
    }
    setState(() {
      _pageStack.removeLast();
      _statusText = null;
      _errorText = null;
      selectedDisplayItem = 0;
    });
  }

  Future<void> _disconnectNavidrome() async {
    final shouldDisconnect = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Disconnect Server?'),
        content: const Text(
          'This removes the saved Navidrome connection from døPe.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (shouldDisconnect != true) {
      return;
    }
    await ref.read(navidromeConnectionProvider.notifier).disconnect();
    if (!mounted) {
      return;
    }
    setState(() {
      _pageStack.clear();
      _query = '';
      _statusText = null;
      _errorText = null;
      selectedDisplayItem = 0;
    });
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      _statusText = null;
      _errorText = message;
    });
  }

  Widget _buildBrowserTile(int index, NavidromeBrowserItem item) {
    final text = item.subtitle == null
        ? item.title
        : '${item.title} • ${item.subtitle}';
    return DisplayListTile(
      text: text,
      isSelected: selectedDisplayItem == index,
      onTap: () => unawaited(_onDisplayItemAction(index)),
    );
  }

  Widget _buildSongTile(int index, NavidromeBrowserItem item) {
    return SongListTile(
      songMetadata: item.song!,
      isSelected: selectedDisplayItem == index,
      isCurrentlyPlaying: false,
      onTap: () => unawaited(_onDisplayItemAction(index)),
      onLongPress: () => unawaited(_showSongActions(item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(navidromeConnectionProvider);
    final items = _pageStack.isNotEmpty
        ? _pageStack.last.items
        : _homeItems(connection);
    final title = _pageStack.isNotEmpty
        ? _pageStack.last.title
        : Routes.navidrome.title(context);

    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: title),
          if (_statusText != null || _errorText != null || _isBusy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                _isBusy
                    ? _statusText ?? 'Loading...'
                    : _errorText ?? _statusText!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _errorText == null
                      ? context.appSecondaryTextColor
                      : CupertinoColors.systemRed.resolveFrom(context),
                  fontSize: 13,
                ),
              ),
            ),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                padding: listViewPadding,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item.type == NavidromeBrowserItemType.song) {
                    return _buildSongTile(index, item);
                  }
                  return _buildBrowserTile(index, item);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
