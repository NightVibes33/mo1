import 'dart:async';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/features/music/album/models/album_model.dart';
import 'package:classipod/features/music/album/providers/album_details_provider.dart';
import 'package:classipod/features/music/playlist/models/playlist_model.dart';
import 'package:classipod/features/music/playlist/providers/playlists_provider.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CarPlaySync extends ConsumerStatefulWidget {
  final Widget child;

  const CarPlaySync({super.key, required this.child});

  @override
  ConsumerState<CarPlaySync> createState() => _CarPlaySyncState();
}

class _CarPlaySyncState extends ConsumerState<CarPlaySync> {
  static const MethodChannel _channel = MethodChannel('mo1/carplay');

  Timer? _heartbeat;
  String? _lastSnapshotSignature;

  bool get _canUseCarPlay {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    if (!_canUseCarPlay) {
      return;
    }

    _channel.setMethodCallHandler(_handleNativeCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_pushSnapshot(force: true));
    });
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_pushSnapshot());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_canUseCarPlay) {
      ref.listen(nowPlayingDetailsProvider, (_, _) {
        unawaited(_pushSnapshot(force: true));
      });
      ref.listen(filteredAudioFilesProvider, (_, _) {
        unawaited(_pushSnapshot(force: true));
      });
    }

    return widget.child;
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    if (_canUseCarPlay) {
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'librarySnapshot':
        return _librarySnapshot();
      case 'playSong':
        final originalIndex = _intArgument(call.arguments, 'originalIndex');
        if (originalIndex == null) {
          return _librarySnapshot();
        }
        await ref
            .read(audioPlayerServiceProvider.notifier)
            .playSongFromOriginalList(originalIndex);
        await _pushSnapshot(force: true);
        return _librarySnapshot();
      case 'playPause':
        await ref.read(audioPlayerServiceProvider.notifier).togglePlayback();
        await _pushSnapshot(force: true);
        return null;
      case 'play':
        await ref.read(audioPlayerServiceProvider.notifier).play();
        await _pushSnapshot(force: true);
        return null;
      case 'pause':
        await ref.read(audioPlayerServiceProvider.notifier).pause();
        await _pushSnapshot(force: true);
        return null;
      case 'next':
        await ref.read(audioPlayerServiceProvider.notifier).nextSong();
        await _pushSnapshot(force: true);
        return null;
      case 'previous':
        await ref.read(audioPlayerServiceProvider.notifier).seekBackwards();
        await _pushSnapshot(force: true);
        return null;
      case 'shuffleAll':
        await ref.read(audioPlayerServiceProvider.notifier).shuffleAllSongs();
        await _pushSnapshot(force: true);
        return null;
      default:
        throw MissingPluginException('Unknown CarPlay method ${call.method}');
    }
  }

  int? _intArgument(dynamic arguments, String key) {
    if (arguments is! Map) {
      return null;
    }
    final value = arguments[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _pushSnapshot({bool force = false}) async {
    if (!_canUseCarPlay) {
      return;
    }

    try {
      final snapshot = await _librarySnapshot();
      final signature = _snapshotSignature(snapshot);
      if (!force && signature == _lastSnapshotSignature) {
        return;
      }
      _lastSnapshotSignature = signature;
      await _channel.invokeMethod<void>('updateSnapshot', snapshot);
    } on MissingPluginException {
      // CarPlay bridge is only present in iOS builds.
    } on PlatformException catch (error) {
      debugPrint('mo1 CarPlay sync failed: ${error.message}');
    } catch (error) {
      debugPrint('mo1 CarPlay snapshot failed: $error');
    }
  }

  String _snapshotSignature(Map<String, Object?> snapshot) {
    final current = snapshot['current'];
    final currentId = current is Map ? current['originalIndex'] : null;
    return [
      snapshot['songCount'],
      snapshot['albumCount'],
      snapshot['artistCount'],
      snapshot['playlistCount'],
      currentId,
      snapshot['isPlaying'],
      snapshot['elapsed'],
      snapshot['duration'],
    ].join('|');
  }

  Future<Map<String, Object?>> _librarySnapshot() async {
    final songs = await _songs();
    final albums = _albums(songs);
    final artists = _artists(songs);
    final playlists = _playlists();
    final nowPlaying = ref.read(nowPlayingDetailsProvider);
    final player = ref.read(audioPlayerProvider);
    final metadata = nowPlaying.currentMetadata;
    final duration = player.duration ??
        (metadata?.trackDuration == null
            ? null
            : Duration(milliseconds: metadata!.trackDuration!));
    final durationSeconds = duration?.inSeconds ?? 0;
    final elapsedSeconds = durationSeconds <= 0
        ? player.position.inSeconds
        : player.position.inSeconds.clamp(0, durationSeconds).toInt();

    return <String, Object?>{
      'songCount': songs.length,
      'albumCount': albums.length,
      'artistCount': artists.length,
      'playlistCount': playlists.length,
      'isPlaying': nowPlaying.isPlaying,
      'currentIndex': nowPlaying.currentIndex,
      'elapsed': elapsedSeconds,
      'duration': durationSeconds,
      'current': metadata == null ? null : _songMap(metadata),
      'songs': songs.map(_songMap).toList(growable: false),
      'recentlyAdded': songs.reversed
          .take(40)
          .map(_songMap)
          .toList(growable: false),
      'albums': albums.map(_albumMap).toList(growable: false),
      'artists': artists.map(_artistMap).toList(growable: false),
      'playlists': playlists.map(_playlistMap).toList(growable: false),
    };
  }

  Future<List<MusicMetadata>> _songs() async {
    final cached = ref.read(filteredAudioFilesProvider).valueOrNull;
    if (cached != null) {
      return cached.toList(growable: false);
    }

    try {
      final loaded = await ref
          .read(filteredAudioFilesProvider.future)
          .timeout(const Duration(seconds: 4));
      return loaded.toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<AlbumModel> _albums(List<MusicMetadata> songs) {
    try {
      final providerAlbums = ref.read(albumDetailsProvider);
      if (providerAlbums.isNotEmpty || songs.isEmpty) {
        return providerAlbums;
      }
    } catch (_) {}

    final byKey = <String, AlbumModel>{};
    for (final song in songs) {
      final key = '${song.getAlbumArtistName}\u0000${song.getAlbumName}';
      final album = byKey[key];
      if (album == null) {
        byKey[key] = AlbumModel(
          albumName: song.getAlbumName,
          albumArtistName: song.getAlbumArtistName,
          albumArtPath: song.thumbnailPath,
          albumSongs: [song],
        );
      } else {
        album.albumSongs.add(song);
      }
    }
    final albums = byKey.values.toList();
    albums.sort((a, b) {
      final artistCompare = a.albumArtistName.compareTo(b.albumArtistName);
      if (artistCompare != 0) {
        return artistCompare;
      }
      return a.albumName.compareTo(b.albumName);
    });
    return albums;
  }

  List<_CarPlayArtist> _artists(List<MusicMetadata> songs) {
    final byArtist = <String, List<MusicMetadata>>{};
    for (final song in songs) {
      byArtist.putIfAbsent(song.getMainArtistName, () => []).add(song);
    }
    final artists = byArtist.entries
        .map((entry) => _CarPlayArtist(entry.key, entry.value))
        .toList();
    artists.sort((a, b) => a.name.compareTo(b.name));
    return artists;
  }

  List<PlaylistModel> _playlists() {
    try {
      return ref
          .read(playlistsProvider)
          .where((playlist) => playlist.songs.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Map<String, Object?> _songMap(MusicMetadata song) {
    return <String, Object?>{
      'originalIndex': song.originalSongIndex,
      'title': song.getTrackName,
      'artist': song.getTrackArtistNames ?? song.getAlbumArtistName,
      'album': song.getAlbumName,
      'duration': (song.trackDuration ?? 0) ~/ 1000,
      'rating': song.rating,
      'artworkPath': song.thumbnailPath,
    };
  }

  Map<String, Object?> _albumMap(AlbumModel album) {
    return <String, Object?>{
      'id': '${album.albumArtistName}\u0000${album.albumName}',
      'title': album.albumName,
      'subtitle': album.albumArtistName,
      'count': album.albumSongs.length,
      'artworkPath': album.albumArtPath,
      'songs': album.albumSongs.map(_songMap).toList(growable: false),
    };
  }

  Map<String, Object?> _artistMap(_CarPlayArtist artist) {
    return <String, Object?>{
      'id': artist.name,
      'title': artist.name,
      'count': artist.songs.length,
      'songs': artist.songs.map(_songMap).toList(growable: false),
    };
  }

  Map<String, Object?> _playlistMap(PlaylistModel playlist) {
    return <String, Object?>{
      'id': playlist.key?.toString() ?? 'on-the-go',
      'title': playlist.name,
      'count': playlist.songs.length,
      'songs': playlist.songs.map(_songMap).toList(growable: false),
    };
  }
}

class _CarPlayArtist {
  final String name;
  final List<MusicMetadata> songs;

  const _CarPlayArtist(this.name, this.songs);
}
