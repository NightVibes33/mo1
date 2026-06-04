import 'dart:async';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/music/album/models/album_model.dart';
import 'package:classipod/features/music/songs/widgets/condensed_song_list_tile.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AlbumSongsScreen extends ConsumerStatefulWidget {
  final AlbumModel albumDetail;

  const AlbumSongsScreen({super.key, required this.albumDetail});

  @override
  ConsumerState createState() => _AlbumSongsScreenState();
}

class _AlbumSongsScreenState extends ConsumerState<AlbumSongsScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.albumSongs.name;

  @override
  List<MusicMetadata> get displayItems => _currentAlbumSongs(
    ref.read(filteredAudioFilesProvider).requireValue,
  );

  List<MusicMetadata> _currentAlbumSongs(Iterable<MusicMetadata> source) {
    final originalIndexes = widget.albumDetail.albumSongs
        .map((song) => song.originalSongIndex)
        .toSet();
    final songs = source
        .where((song) => originalIndexes.contains(song.originalSongIndex))
        .toList(growable: false);
    if (songs.isEmpty) {
      return widget.albumDetail.albumSongs;
    }
    return songs;
  }

  String _screenTitle(List<MusicMetadata> songs) {
    if (songs.isEmpty || widget.albumDetail.albumSongs.length != songs.length) {
      return widget.albumDetail.albumName;
    }
    final originalAlbumNames = widget.albumDetail.albumSongs
        .map((song) => song.getAlbumName)
        .toSet();
    if (originalAlbumNames.length != 1 ||
        originalAlbumNames.single != widget.albumDetail.albumName) {
      return widget.albumDetail.albumName;
    }
    final currentAlbumNames = songs.map((song) => song.getAlbumName).toSet();
    return currentAlbumNames.length == 1
        ? currentAlbumNames.single
        : widget.albumDetail.albumName;
  }

  String _screenAlbumArtist(List<MusicMetadata> songs) {
    final originalAlbumNames = widget.albumDetail.albumSongs
        .map((song) => song.getAlbumName)
        .toSet();
    if (songs.isEmpty ||
        originalAlbumNames.length != 1 ||
        originalAlbumNames.single != widget.albumDetail.albumName) {
      return widget.albumDetail.albumArtistName;
    }
    final currentAlbumArtists = songs
        .map((song) => song.getAlbumArtistName)
        .toSet();
    return currentAlbumArtists.length == 1
        ? currentAlbumArtists.single
        : widget.albumDetail.albumArtistName;
  }

  @override
  Future<void> onSelectPressed() => _playSongFromAlbum(selectedDisplayItem);

  Future<void> _playSongFromAlbum(int index) async {
    setState(() => selectedDisplayItem = index);
    final liveSongs = displayItems;
    await ref.read(audioPlayerServiceProvider.notifier).playAlbum(
          albumDetail: AlbumModel(
            albumName: _screenTitle(liveSongs),
            albumArtistName: _screenAlbumArtist(liveSongs),
            albumSongs: liveSongs,
          ),
          songIndex: index,
        );

    if (mounted) {
      await context.pushNamed(Routes.nowPlaying.name);
    }
  }

  @override
  Future<void> onSelectLongPress() async {
    await context.pushNamed(
      Routes.albumSongsMoreOptions.name,
      extra: displayItems[selectedDisplayItem],
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayItems = _currentAlbumSongs(
      ref.watch(filteredAudioFilesProvider).requireValue,
    );
    final int? currentlyPlayingOriginalIndex = ref
        .watch(nowPlayingDetailsProvider.select((e) => e.currentMetadata))
        ?.originalSongIndex;
    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: _screenTitle(displayItems)),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                itemCount: displayItems.length,
                prototypeItem: const CondensedSongListTile(
                  songName: '',
                  isSelected: false,
                  isCurrentlyPlaying: false,
                ),
                itemBuilder: (context, index) => CondensedSongListTile(
                  songName: displayItems[index].getTrackName,
                  isSelected: selectedDisplayItem == index,
                  isCurrentlyPlaying:
                      currentlyPlayingOriginalIndex ==
                      displayItems[index].originalSongIndex,
                  onTap: () async => _playSongFromAlbum(index),
                  onLongPress: () async {
                    setState(() => selectedDisplayItem = index);
                    await context.pushNamed(
                      Routes.albumSongsMoreOptions.name,
                      extra: displayItems[index],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
