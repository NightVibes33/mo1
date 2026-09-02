import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/navigation/routes.dart';
import 'package:dopi/core/services/audio_player_service.dart';
import 'package:dopi/core/widgets/album_art_song_list_tile.dart';
import 'package:dopi/features/custom_screen_elements/custom_screen.dart';
import 'package:dopi/features/music/genres/providers/genre_songs_provider.dart';
import 'package:dopi/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dopi/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class GenreSongsScreen extends ConsumerStatefulWidget {
  final String genreName;

  const GenreSongsScreen({super.key, required this.genreName});

  @override
  ConsumerState createState() => _GenreSongsScreenState();
}

class _GenreSongsScreenState extends ConsumerState<GenreSongsScreen>
    with CustomScreen {
  @override
  double get displayTileHeight => 54;

  @override
  String get routeName => Uri.encodeComponent(widget.genreName);

  @override
  List<MusicMetadata> get displayItems =>
      ref.read(genreSongsMetadataListProvider(widget.genreName));

  @override
  Future<void> onSelectPressed() => _playSong(selectedDisplayItem);

  @override
  void onSelectLongPress() =>
      _navigateToGenreMoreOptionsModal(selectedDisplayItem);

  void _navigateToGenreMoreOptionsModal(int index) {
    setState(() {
      selectedDisplayItem = index;
    });
    context.goNamed(
      Routes.genresSongsMoreOptions.name,
      pathParameters: {"genreName": widget.genreName},
      extra: displayItems[index],
    );
  }

  Future<void> _playSong(int index) async {
    setState(() => selectedDisplayItem = index);
    final didStart = await ref
        .read(audioPlayerServiceProvider.notifier)
        .playMetadataListAtIndex(
          metadataList: displayItems,
          index: index,
        );
    if (didStart && mounted) {
      await context.pushNamed(Routes.nowPlaying.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayItems = ref.watch(
      genreSongsMetadataListProvider(widget.genreName),
    );
    final currentMetadata = ref.watch(
      nowPlayingDetailsProvider.select((e) => e.currentMetadata),
    );
    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: widget.genreName),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                padding: listViewPadding,
                itemCount: displayItems.length,
                prototypeItem: AlbumArtSongListTile(
                  songMetadata: MusicMetadata(),
                  isSelected: false,
                  isCurrentlyPlaying: false,
                  onTap: () {},
                  onLongPress: () {},
                ),
                itemBuilder: (context, index) => AlbumArtSongListTile(
                  songMetadata: displayItems[index],
                  isSelected: selectedDisplayItem == index,
                  isCurrentlyPlaying:
                      currentMetadata?.hasSameSourceIdentity(displayItems[index]) ?? false,
                  onTap: () async => _playSong(index),
                  onLongPress: () => _navigateToGenreMoreOptionsModal(index),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
