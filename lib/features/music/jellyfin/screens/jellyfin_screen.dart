import 'dart:async';

import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/core/widgets/display_list_tile.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/music/jellyfin/models/jellyfin_browser_item.dart';
import 'package:dope/features/music/jellyfin/models/jellyfin_connection.dart';
import 'package:dope/features/music/jellyfin/providers/jellyfin_connection_provider.dart';
import 'package:dope/features/music/jellyfin/providers/jellyfin_service_provider.dart';
import 'package:dope/features/music/jellyfin/services/jellyfin_service.dart';
import 'package:dope/features/music/songs/widgets/song_list_tile.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class JellyfinScreen extends ConsumerStatefulWidget {
  const JellyfinScreen({super.key});

  @override
  ConsumerState<JellyfinScreen> createState() => _JellyfinScreenState();
}

class _JellyfinPage {
  final String title;
  final List<JellyfinBrowserItem> items;

  const _JellyfinPage({required this.title, required this.items});
}

class _JellyfinScreenState extends ConsumerState<JellyfinScreen>
    with CustomScreen {
  static const String _connectAction = 'connect';
  static const String _searchAction = 'search';
  static const String _songsAction = 'songs';
  static const String _albumsAction = 'albums';
  static const String _artistsAction = 'artists';
  static const String _playlistsAction = 'playlists';
  static const String _favoritesAction = 'favorites';
  static const String _recentlyAddedAction = 'recentlyAdded';
  static const String _librariesAction = 'libraries';
  static const String _serverInfoAction = 'serverInfo';
  static const String _disconnectAction = 'disconnect';
  static const String _backAction = 'back';

  final List<_JellyfinPage> _pageStack = [];
  bool _isBusy = false;
  String _query = '';
  String? _statusText;
  String? _errorText;

  @override
  double get displayTileHeight => 54;

  @override
  String get routeName => Routes.jellyfin.name;

  @override
  List<JellyfinBrowserItem> get displayItems => _currentItems;

  List<JellyfinBrowserItem> get _currentItems {
    final connection = ref.read(jellyfinConnectionProvider);
    if (_pageStack.isNotEmpty) {
      return _pageStack.last.items;
    }
    return _homeItems(connection);
  }

  List<JellyfinBrowserItem> _homeItems(JellyfinConnection? connection) {
    if (connection == null) {
      return const [
        JellyfinBrowserItem.action(
          id: _connectAction,
          title: 'Connect Jellyfin',
        ),
      ];
    }

    return const [
      JellyfinBrowserItem.action(
        id: _connectAction,
        title: 'Connect Jellyfin',
        subtitle: 'Update server or login',
      ),
      JellyfinBrowserItem.action(id: _searchAction, title: 'Search Library'),
      JellyfinBrowserItem.action(id: _songsAction, title: 'Songs'),
      JellyfinBrowserItem.action(id: _albumsAction, title: 'Albums'),
      JellyfinBrowserItem.action(id: _artistsAction, title: 'Artists'),
      JellyfinBrowserItem.action(id: _playlistsAction, title: 'Playlists'),
      JellyfinBrowserItem.action(id: _favoritesAction, title: 'Favorites'),
      JellyfinBrowserItem.action(
        id: _recentlyAddedAction,
        title: 'Recently Added',
      ),
      JellyfinBrowserItem.action(id: _librariesAction, title: 'Music Libraries'),
      JellyfinBrowserItem.action(id: _serverInfoAction, title: 'Server Info'),
      JellyfinBrowserItem.action(
        id: _disconnectAction,
        title: 'Disconnect Server',
      ),
    ];
  }

  @override
  Future<void> onSelectPressed() => _onDisplayItemAction(selectedDisplayItem);

  @override
  void onMenuButtonPressed() {
    if (_pageStack.isNotEmpty) {
      _goBack();
      return;
    }
    context.pop();
  }

  Future<void> _onDisplayItemAction(int displayIndex) async {
    final items = _currentItems;
    if (displayIndex < 0 || displayIndex >= items.length) {
      return;
    }
    setState(() => selectedDisplayItem = displayIndex);
    final item = items[displayIndex];

    switch (item.type) {
      case JellyfinBrowserItemType.action:
        await _handleAction(item.id);
        break;
      case JellyfinBrowserItemType.artist:
        await _loadArtistSongs(item);
        break;
      case JellyfinBrowserItemType.album:
        await _loadAlbumSongs(item);
        break;
      case JellyfinBrowserItemType.playlist:
        await _loadPlaylistSongs(item);
        break;
      case JellyfinBrowserItemType.folder:
        await _loadLibrarySongs(item);
        break;
      case JellyfinBrowserItemType.song:
        await _playSong(displayIndex);
        break;
    }
  }

  Future<void> _handleAction(String action) async {
    final connection = ref.read(jellyfinConnectionProvider);
    switch (action) {
      case _connectAction:
        await _connectJellyfin(existingConnection: connection);
        break;
      case _searchAction:
        if (connection != null) {
          await _promptAndSearch(connection);
        }
        break;
      case _songsAction:
        if (connection != null) {
          await _loadSongPage(
            title: 'Jellyfin Songs',
            loader: () => ref.read(jellyfinServiceProvider).songs(connection),
          );
        }
        break;
      case _albumsAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Jellyfin Albums',
            loader: () => ref.read(jellyfinServiceProvider).albums(connection),
          );
        }
        break;
      case _artistsAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Jellyfin Artists',
            loader: () => ref.read(jellyfinServiceProvider).artists(connection),
          );
        }
        break;
      case _playlistsAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Jellyfin Playlists',
            loader: () => ref.read(jellyfinServiceProvider).playlists(connection),
          );
        }
        break;
      case _favoritesAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Jellyfin Favorites',
            loader: () => ref.read(jellyfinServiceProvider).favorites(connection),
          );
        }
        break;
      case _recentlyAddedAction:
        if (connection != null) {
          await _loadSongPage(
            title: 'Recently Added',
            loader: () => ref.read(jellyfinServiceProvider).recentlyAdded(connection),
          );
        }
        break;
      case _librariesAction:
        if (connection != null) {
          await _loadBrowserPage(
            title: 'Music Libraries',
            loader: () => ref.read(jellyfinServiceProvider).musicLibraries(connection),
          );
        }
        break;
      case _serverInfoAction:
        if (connection != null) {
          await _showServerInfo(connection);
        }
        break;
      case _disconnectAction:
        await _disconnectJellyfin();
        break;
      case _backAction:
        _goBack();
        break;
    }
  }

  Future<void> _connectJellyfin({JellyfinConnection? existingConnection}) async {
    final form = await _promptForConnection(existingConnection);
    if (!mounted || form == null) {
      return;
    }
    final serverUrl = form.serverUrl.trim();
    final username = form.username.trim();
    if (serverUrl.isEmpty || username.isEmpty || form.password.isEmpty) {
      setState(() => _errorText = 'Enter server URL, username, and password.');
      return;
    }

    setState(() {
      _isBusy = true;
      _statusText = 'Connecting to Jellyfin...';
      _errorText = null;
    });

    try {
      final connection = await ref.read(jellyfinServiceProvider).authenticate(
            serverUrl: serverUrl,
            username: username,
            password: form.password,
            deviceId: existingConnection?.deviceId ?? _newDeviceId(),
          );
      await ref.read(jellyfinConnectionProvider.notifier).save(connection);
      if (!mounted) {
        return;
      }
      setState(() {
        _isBusy = false;
        _pageStack.clear();
        _statusText = 'Connected to ${connection.serverName}.';
        selectedDisplayItem = 1;
      });
    } on JellyfinServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Could not connect to Jellyfin.');
    }
  }

  Future<_JellyfinConnectionForm?> _promptForConnection(
    JellyfinConnection? existingConnection,
  ) async {
    final serverController = TextEditingController(
      text: existingConnection?.serverUrl ?? '',
    );
    final usernameController = TextEditingController(
      text: existingConnection?.username ?? '',
    );
    final passwordController = TextEditingController();

    final form = await showCupertinoDialog<_JellyfinConnectionForm>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Connect Jellyfin'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              CupertinoTextField(
                controller: serverController,
                autofocus: existingConnection == null,
                clearButtonMode: OverlayVisibilityMode.editing,
                keyboardType: TextInputType.url,
                placeholder: 'https://jellyfin.example.com',
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
                  _JellyfinConnectionForm(
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
              _JellyfinConnectionForm(
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
    return form;
  }

  Future<void> _promptAndSearch(JellyfinConnection connection) async {
    final query = await _promptForSearchQuery();
    if (!mounted || query == null) {
      return;
    }
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() => _errorText = 'Enter a song, artist, album, or playlist.');
      return;
    }
    await _loadBrowserPage(
      title: 'Search: $cleanQuery',
      loader: () => ref.read(jellyfinServiceProvider).searchResults(connection, cleanQuery),
    );
  }

  Future<String?> _promptForSearchQuery() async {
    final controller = TextEditingController(text: _query);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Search Jellyfin'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            clearButtonMode: OverlayVisibilityMode.editing,
            placeholder: 'Song, artist, album, playlist',
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
    if (result != null) {
      _query = result;
    }
    return result;
  }

  Future<void> _loadArtistSongs(JellyfinBrowserItem artist) async {
    final connection = ref.read(jellyfinConnectionProvider);
    if (connection == null) {
      return;
    }
    await _loadSongPage(
      title: artist.title,
      loader: () => ref.read(jellyfinServiceProvider).artistSongs(connection, artist.id),
    );
  }

  Future<void> _loadAlbumSongs(JellyfinBrowserItem album) async {
    final connection = ref.read(jellyfinConnectionProvider);
    if (connection == null) {
      return;
    }
    await _loadSongPage(
      title: album.title,
      loader: () => ref.read(jellyfinServiceProvider).albumSongs(connection, album.id),
    );
  }

  Future<void> _loadPlaylistSongs(JellyfinBrowserItem playlist) async {
    final connection = ref.read(jellyfinConnectionProvider);
    if (connection == null) {
      return;
    }
    await _loadSongPage(
      title: playlist.title,
      loader: () => ref.read(jellyfinServiceProvider).playlistSongs(connection, playlist.id),
    );
  }

  Future<void> _loadLibrarySongs(JellyfinBrowserItem folder) async {
    final connection = ref.read(jellyfinConnectionProvider);
    if (connection == null) {
      return;
    }
    await _loadSongPage(
      title: folder.title,
      loader: () => ref.read(jellyfinServiceProvider).librarySongs(connection, folder.id),
    );
  }

  Future<void> _showServerInfo(JellyfinConnection connection) async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _statusText = 'Checking Jellyfin server...';
      _errorText = null;
    });
    try {
      final info = await ref.read(jellyfinServiceProvider).serverInfo(connection);
      if (!mounted) {
        return;
      }
      setState(() {
        _isBusy = false;
        _statusText = info;
      });
    } on JellyfinServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Jellyfin server info failed.');
    }
  }

  Future<void> _loadBrowserPage({
    required String title,
    required Future<List<JellyfinBrowserItem>> Function() loader,
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
        _pageStack.add(_JellyfinPage(title: title, items: [_backItem, ...items]));
        _statusText = items.isEmpty ? null : '${items.length} items';
        _errorText = items.isEmpty ? 'No Jellyfin items found.' : null;
        selectedDisplayItem = items.isEmpty ? 0 : 1;
      });
    } on JellyfinServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Jellyfin request failed.');
    }
  }

  Future<void> _loadSongPage({
    required String title,
    required Future<List<MusicMetadata>> Function() loader,
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
      setState(() {
        _isBusy = false;
        _pageStack.add(
          _JellyfinPage(
            title: title,
            items: [
              _backItem,
              for (final song in songs)
                JellyfinBrowserItem.song(
                  id: song.filePath ?? song.getTrackName,
                  title: song.getTrackName,
                  subtitle: song.getTrackArtistNames,
                  song: song,
                ),
            ],
          ),
        );
        _statusText = songs.isEmpty ? null : '${songs.length} songs';
        _errorText = songs.isEmpty ? 'No Jellyfin songs found.' : null;
        selectedDisplayItem = songs.isEmpty ? 0 : 1;
      });
    } on JellyfinServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Jellyfin request failed.');
    }
  }

  JellyfinBrowserItem get _backItem =>
      const JellyfinBrowserItem.action(id: _backAction, title: '< Back');

  Future<void> _playSong(int displayIndex) async {
    final songItems = _currentItems
        .where((item) => item.type == JellyfinBrowserItemType.song)
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
      unawaited(_reportPlaybackStart(selectedSong));
      await context.pushNamed(Routes.nowPlaying.name);
    } else if (mounted) {
      setState(() => _errorText = 'Jellyfin playback failed.');
    }
  }

  Future<void> _reportPlaybackStart(MusicMetadata song) async {
    final connection = ref.read(jellyfinConnectionProvider);
    if (connection == null) {
      return;
    }
    try {
      await ref.read(jellyfinServiceProvider).reportPlaybackStart(connection, song);
    } catch (_) {
      // Playback should not fail just because Jellyfin history failed.
    }
  }

  Future<void> _showSongActions(JellyfinBrowserItem item) async {
    final song = item.song;
    final connection = ref.read(jellyfinConnectionProvider);
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
            onPressed: () => Navigator.of(context).pop('favorite'),
            child: const Text('Favorite Song'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('unfavorite'),
            child: const Text('Unfavorite Song'),
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
        case 'favorite':
          await ref.read(jellyfinServiceProvider).favoriteSong(connection, song);
          _setStatus('Song favorited.');
          break;
        case 'unfavorite':
          await ref.read(jellyfinServiceProvider).unfavoriteSong(connection, song);
          _setStatus('Song unfavorited.');
          break;
      }
    } on JellyfinServiceException catch (error) {
      _setError(error.message);
    } catch (_) {
      _setError('Jellyfin action failed.');
    }
  }

  Future<void> _disconnectJellyfin() async {
    await ref.read(jellyfinConnectionProvider.notifier).disconnect();
    if (!mounted) {
      return;
    }
    setState(() {
      _pageStack.clear();
      selectedDisplayItem = 0;
      _statusText = 'Disconnected from Jellyfin.';
      _errorText = null;
    });
  }

  void _goBack() {
    if (_pageStack.isEmpty) {
      return;
    }
    setState(() {
      _pageStack.removeLast();
      selectedDisplayItem = 0;
      _errorText = null;
      _statusText = _pageStack.isEmpty ? null : _pageStack.last.title;
    });
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      _errorText = message;
      _statusText = null;
    });
  }

  void _setStatus(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      _statusText = message;
      _errorText = null;
    });
  }

  String _newDeviceId() {
    return 'dope-ios-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(jellyfinConnectionProvider);
    final title = _pageStack.isEmpty ? Routes.jellyfin.title(context) : _pageStack.last.title;
    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: title),
          if (_statusText != null || _errorText != null || _isBusy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                _isBusy ? 'Loading...' : (_errorText ?? _statusText ?? ''),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _errorText == null
                      ? CupertinoColors.systemGrey.resolveFrom(context)
                      : CupertinoColors.systemRed.resolveFrom(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                padding: listViewPadding,
                itemCount: _currentItems.length,
                itemBuilder: (context, index) {
                  final item = _currentItems[index];
                  if (item.type == JellyfinBrowserItemType.song && item.song != null) {
                    return SongListTile(
                      songMetadata: item.song!,
                      isSelected: selectedDisplayItem == index,
                      isCurrentlyPlaying: false,
                      onTap: () => unawaited(_onDisplayItemAction(index)),
                      onLongPress: () => unawaited(_showSongActions(item)),
                    );
                  }
                  final text = item.subtitle == null
                      ? item.title
                      : '${item.title} • ${item.subtitle}';
                  return DisplayListTile(
                    text: text,
                    isSelected: selectedDisplayItem == index,
                    onTap: () => unawaited(_onDisplayItemAction(index)),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JellyfinConnectionForm {
  final String serverUrl;
  final String username;
  final String password;

  const _JellyfinConnectionForm({
    required this.serverUrl,
    required this.username,
    required this.password,
  });
}
