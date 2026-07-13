import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/providers/filtered_audio_files_provider.dart';
import 'package:dope/core/services/audio_files_service.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/core/widgets/empty_state_widget.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/music/playlist/providers/playlists_provider.dart';
import 'package:dope/features/music/songs/provider/songs_provider.dart';
import 'package:dope/features/music/songs/widgets/song_list_tile.dart';
import 'package:dope/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> with CustomScreen {
  @override
  double get displayTileHeight => 54;

  @override
  String get routeName => Routes.songs.name;

  @override
  List<MusicMetadata> get displayItems => ref.read(songsProvider);

  @override
  Future<void> onSelectPressed() => _playSong(selectedDisplayItem);

  @override
  void onSelectLongPress() =>
      _navigateToSongMoreOptionsModal(selectedDisplayItem);

  void _navigateToSongMoreOptionsModal(int index) {
    setState(() => selectedDisplayItem = index);
    context.goNamed(Routes.songsMoreOptions.name, extra: displayItems[index]);
  }

  Future<void> _playSong(int displayIndex) async {
    setState(() => selectedDisplayItem = displayIndex);
    final didStart = await ref
        .read(audioPlayerServiceProvider.notifier)
        .playMetadataListAtIndex(
          metadataList: displayItems,
          index: displayIndex,
        );

    if (didStart && mounted) {
      await context.pushNamed(
        Routes.nowPlaying.name,
        extra: Routes.songs.name,
      );
    }
  }

  Future<bool> _confirmDeleteSong(MusicMetadata songMetadata) async {
    final currentMetadata = ref.read(nowPlayingDetailsProvider).currentMetadata;
    final isCurrentSong =
        currentMetadata != null &&
        (currentMetadata.originalSongIndex == songMetadata.originalSongIndex ||
            currentMetadata.filePath == songMetadata.filePath);
    final message =
        songMetadata.isOnDevice && !songMetadata.isAppleMusicCatalogTrack
        ? 'This will remove the song from døPe and delete the local file from your device.'
        : 'This will remove the song from døPe.';

    return await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete Song?'),
        content: Text(
          isCurrentSong
              ? '$message\n\nThe current song will stop playing.'
              : message,
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.localization.cancelText),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  Future<bool> _deleteSong(MusicMetadata songMetadata) async {
    final previousLength = ref.read(songsProvider).length;
    final deleted = await ref
        .read(audioFilesServiceProvider.notifier)
        .deleteSong(songMetadata);
    if (!deleted || !mounted) {
      return false;
    }

    await ref
        .read(nowPlayingDetailsProvider.notifier)
        .removeSongFromLibrary(songMetadata);
    await ref
        .read(playlistsProvider.notifier)
        .removeSongFromAllPlaylists(songMetadata);
    ref.invalidate(audioFilesServiceProvider);
    ref.invalidate(filteredAudioFilesProvider);
    ref.invalidate(songsProvider);

    if (previousLength <= 1) {
      if (mounted) {
        setState(() => selectedDisplayItem = 0);
      }
      return true;
    }

    if (mounted) {
      setState(() {
        selectedDisplayItem = selectedDisplayItem.clamp(0, previousLength - 2);
      });
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final displayItems = ref.watch(songsProvider);
    final int? currentlyPlayingOriginalIndex = ref
        .watch(nowPlayingDetailsProvider.select((e) => e.currentMetadata))
        ?.originalSongIndex;
    if (displayItems.isEmpty) {
      return CupertinoPageScaffold(
        child: Column(
          children: [
            StatusBar(title: Routes.songs.title(context)),
            Expanded(
              child: EmptyStateWidget(
                emptyDescription: context.localization.noMusicFilesFound,
              ),
            ),
          ],
        ),
      );
    }

    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.songs.title(context)),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                padding: listViewPadding,
                itemCount: displayItems.length,
                prototypeItem: SongListTile(
                  songMetadata: displayItems.first,
                  isSelected: false,
                  isCurrentlyPlaying: false,
                  onTap: () {},
                  onLongPress: () {},
                ),
                itemBuilder: (context, index) {
                  final songMetadata = displayItems[index];
                  final dismissKey = ValueKey(
                    '${songMetadata.filePath ?? songMetadata.originalSongIndex}',
                  );
                  return Dismissible(
                    key: dismissKey,
                    direction: DismissDirection.endToStart,
                    background: const SizedBox.shrink(),
                    secondaryBackground: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      color: CupertinoColors.systemRed,
                      child: const Icon(
                        CupertinoIcons.trash_fill,
                        color: CupertinoColors.white,
                      ),
                    ),
                    confirmDismiss: (_) async {
                      final confirmed = await _confirmDeleteSong(songMetadata);
                      if (!confirmed) {
                        return false;
                      }
                      return _deleteSong(songMetadata);
                    },
                    child: SongListTile(
                      songMetadata: songMetadata,
                      isSelected: selectedDisplayItem == index,
                      isCurrentlyPlaying:
                          currentlyPlayingOriginalIndex ==
                          songMetadata.originalSongIndex,
                      onTap: () async => _playSong(index),
                      onLongPress: () => _navigateToSongMoreOptionsModal(index),
                    ),
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
