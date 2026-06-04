import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/widgets/options_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/music/album/providers/album_details_provider.dart';
import 'package:classipod/features/music/playlist/providers/playlists_provider.dart';
import 'package:classipod/features/music/songs/services/song_metadata_actions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _SongsMoreOptions {
  addToOnTheGo,
  editSong,
  matchMetadata,
  findLyrics,
  browseAlbum,
  browseArtist,
  cancel;

  String title(BuildContext context) {
    switch (this) {
      case addToOnTheGo:
        return context.localization.addToOnTheGoPlaylist;
      case editSong:
        return context.localization.editSongOption;
      case matchMetadata:
        return 'Match Metadata';
      case findLyrics:
        return 'Find Lyrics';
      case browseAlbum:
        return context.localization.browseAlbum;
      case browseArtist:
        return context.localization.browseArtist;
      case cancel:
        return context.localization.cancelText;
    }
  }
}

class SongsMoreOptionsModal extends ConsumerStatefulWidget {
  final String routeName;
  final MusicMetadata currentSongMetadata;
  final bool showAdditionalOptions;

  const SongsMoreOptionsModal({
    super.key,
    required this.routeName,
    required this.currentSongMetadata,
    this.showAdditionalOptions = true,
  });

  @override
  ConsumerState createState() => _SongsMoreOptionsModalState();
}

class _SongsMoreOptionsModalState extends ConsumerState<SongsMoreOptionsModal>
    with CustomScreen {
  @override
  String get routeName => widget.routeName;

  @override
  List<_SongsMoreOptions> get displayItems => [
    _SongsMoreOptions.addToOnTheGo,
    _SongsMoreOptions.editSong,
    _SongsMoreOptions.matchMetadata,
    _SongsMoreOptions.findLyrics,
    if (widget.showAdditionalOptions) _SongsMoreOptions.browseAlbum,
    if (widget.showAdditionalOptions) _SongsMoreOptions.browseArtist,
    _SongsMoreOptions.cancel,
  ];

  @override
  Future<void> onSelectPressed() =>
      _navigateToScreen(displayItems[selectedDisplayItem]);

  Future<void> _navigateToScreen(_SongsMoreOptions optionItem) async {
    setState(() => selectedDisplayItem = displayItems.indexOf(optionItem));
    switch (optionItem) {
      case _SongsMoreOptions.addToOnTheGo:
        ref
            .read(playlistsProvider.notifier)
            .addSongToPlaylist(widget.currentSongMetadata);
        context.pop();
        break;
      case _SongsMoreOptions.editSong:
        final result = await editSongMetadata(
          context,
          widget.currentSongMetadata,
        );
        if (result != null && mounted) {
          context.pop();
        }
        break;
      case _SongsMoreOptions.matchMetadata:
        final result = await matchSongMetadata(
          context,
          ref,
          widget.currentSongMetadata,
        );
        if (result != null && mounted) {
          context.pop();
        }
        break;
      case _SongsMoreOptions.findLyrics:
        final result = await findLyricsForSong(
          context,
          ref,
          widget.currentSongMetadata,
        );
        if (result != null && mounted) {
          context.pop();
        }
        break;
      case _SongsMoreOptions.browseAlbum:
        final albumDetailIndex = ref
            .read(albumDetailsProvider)
            .indexWhere((e) => e == widget.currentSongMetadata.getAlbumDetail);
        if (albumDetailIndex != -1) {
          context.pushReplacementNamed(
            Routes.albumSongs.name,
            extra: ref.read(albumDetailsProvider)[albumDetailIndex],
          );
        }
        break;
      case _SongsMoreOptions.browseArtist:
        context.pushReplacementNamed(
          Routes.artistAlbums.name,
          pathParameters: {
            'artistName': widget.currentSongMetadata.getMainArtistName,
          },
        );
        break;
      case _SongsMoreOptions.cancel:
        context.pop();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appSurfaceColor,
        border: Border.all(color: context.appOutlineColor),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        controller: scrollController,
        padding: listViewPadding,
        itemCount: displayItems.length,
        prototypeItem: const OptionsListTile(text: '', isSelected: false),
        itemBuilder: (context, index) {
          return OptionsListTile(
            text: displayItems[index].title(context),
            isSelected: index == selectedDisplayItem,
            onTap: () async => _navigateToScreen(displayItems[index]),
          );
        },
      ),
    );
  }
}
