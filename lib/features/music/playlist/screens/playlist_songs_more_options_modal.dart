import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/widgets/options_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/music/songs/services/song_metadata_actions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _PlaylistSongsMoreOptions {
  editSong,
  matchMetadata,
  findLyrics,
  removeSongFromPlaylist,
  cancel;

  String title(BuildContext context) {
    switch (this) {
      case editSong:
        return context.localization.editSongOption;
      case matchMetadata:
        return 'Match Metadata';
      case findLyrics:
        return 'Find Lyrics';
      case removeSongFromPlaylist:
        return context.localization.removeSongFromThePlaylist;
      case cancel:
        return context.localization.cancelText;
    }
  }
}

class PlaylistSongsMoreOptionsModal extends ConsumerStatefulWidget {
  final MusicMetadata? songMetadata;

  const PlaylistSongsMoreOptionsModal({super.key, this.songMetadata});

  @override
  ConsumerState createState() => _PlaylistSongsMoreOptionsModalState();
}

class _PlaylistSongsMoreOptionsModalState
    extends ConsumerState<PlaylistSongsMoreOptionsModal>
    with CustomScreen {
  @override
  String get routeName => Routes.playlistSongsMoreOptions.name;

  @override
  List<_PlaylistSongsMoreOptions> get displayItems =>
      _PlaylistSongsMoreOptions.values;

  @override
  Future<void> onSelectPressed() =>
      _performAction(displayItems[selectedDisplayItem]);

  Future<void> _performAction(_PlaylistSongsMoreOptions optionItem) async {
    setState(() => selectedDisplayItem = displayItems.indexOf(optionItem));
    final songMetadata = widget.songMetadata;
    switch (optionItem) {
      case _PlaylistSongsMoreOptions.editSong:
        if (songMetadata == null) {
          context.pop(false);
          return;
        }
        final result = await editSongMetadata(context, songMetadata);
        if (result != null && mounted) {
          context.pop(false);
        }
        break;
      case _PlaylistSongsMoreOptions.matchMetadata:
        if (songMetadata == null) {
          context.pop(false);
          return;
        }
        final result = await matchSongMetadata(context, ref, songMetadata);
        if (result != null && mounted) {
          context.pop(false);
        }
        break;
      case _PlaylistSongsMoreOptions.findLyrics:
        if (songMetadata == null) {
          context.pop(false);
          return;
        }
        final result = await findLyricsForSong(context, ref, songMetadata);
        if (result != null && mounted) {
          context.pop(false);
        }
        break;
      case _PlaylistSongsMoreOptions.removeSongFromPlaylist:
        context.pop(true);
        break;
      case _PlaylistSongsMoreOptions.cancel:
        context.pop(false);
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
            onTap: () async => _performAction(displayItems[index]),
          );
        },
      ),
    );
  }
}
