import 'dart:async';

import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/audio_files_service.dart';
import 'package:dope/core/services/imported_library_refresh_service.dart';
import 'package:dope/core/widgets/display_list_tile.dart';
import 'package:dope/core/widgets/marquee_text.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/menu/widgets/animated_album_art_scroller.dart';
import 'package:dope/features/menu/widgets/now_playing_preview_widget.dart';
import 'package:dope/features/menu/widgets/settings_preview_widget.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _MusicListDisplayItems {
  coverFlow,
  appleMusic,
  importSongs,
  playlists,
  artists,
  albums,
  songs,
  genres,
  search;

  String title(BuildContext context) {
    switch (this) {
      case coverFlow:
        return context.localization.coverFlowScreenTitle;
      case appleMusic:
        return 'Apple Music';
      case importSongs:
        return '+ MP3 Import';
      case playlists:
        return context.localization.playlistsScreenTitle;
      case artists:
        return context.localization.artistsScreenTitle;
      case albums:
        return context.localization.albumsScreenTitle;
      case songs:
        return context.localization.songsScreenTitle;
      case genres:
        return context.localization.genresScreenTitle;
      case search:
        return context.localization.searchScreenTitle;
    }
  }
}

class MusicMenuScreen extends ConsumerStatefulWidget {
  const MusicMenuScreen({super.key});

  @override
  ConsumerState createState() => _MusicMenuScreenState();
}

class _MusicMenuScreenState extends ConsumerState<MusicMenuScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.musicMenu.name;

  @override
  List<_MusicListDisplayItems> get displayItems =>
      _MusicListDisplayItems.values;

  @override
  Future<void> onSelectPressed() =>
      _navigateToScreen(_MusicListDisplayItems.values[selectedDisplayItem]);

  Future<void> _navigateToScreen(
    _MusicListDisplayItems musicDisplayItem,
  ) async {
    setState(
      () => selectedDisplayItem = displayItems.indexOf(musicDisplayItem),
    );
    switch (musicDisplayItem) {
      case _MusicListDisplayItems.coverFlow:
        unawaited(ref.read(splitScreenViewControllerProvider).closeSplitView());
        await context.pushNamed(
          Routes.coverFlow.name,
          extra: Routes.musicMenu.name,
        );
        unawaited(ref.read(splitScreenViewControllerProvider).openSplitView());
        break;
      case _MusicListDisplayItems.appleMusic:
        await context.pushNamed(Routes.appleMusic.name);
        break;
      case _MusicListDisplayItems.importSongs:
        final importResult = await ref
            .read(audioFilesServiceProvider.notifier)
            .importLocalAudioFiles();
        if (mounted) {
          await _showImportResult(importResult);
        }
        if (importResult.hasImportedSongs && mounted) {
          await refreshImportedLibraryProviders(ref);
        }
        break;
      case _MusicListDisplayItems.playlists:
        context.goNamed(Routes.playlists.name);
        break;
      case _MusicListDisplayItems.artists:
        context.goNamed(Routes.artists.name);
        break;
      case _MusicListDisplayItems.albums:
        context.goNamed(Routes.albums.name);
        break;
      case _MusicListDisplayItems.songs:
        context.goNamed(Routes.songs.name);
        break;
      case _MusicListDisplayItems.genres:
        context.goNamed(Routes.genres.name);
        break;
      case _MusicListDisplayItems.search:
        context.goNamed(Routes.search.name);
        break;
    }
  }

  Future<void> _showImportResult(ImportLocalAudioResult result) async {
    if (!mounted || !result.hasActivity) {
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(result.title),
        content: Text(result.message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.musicMenu.title(context)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppPalette.darkScreenBackgroundGradient1,
                      AppPalette.darkScreenBackgroundGradient2,
                    ],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 22,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 47,
                        child: Column(
                          children: [
                            _HybridSectionHeader(
                              title: context.localization.musicMenuScreenTitle,
                              subtitle: context.localization.coverFlowScreenTitle,
                            ),
                            Expanded(
                              child: CupertinoScrollbar(
                                controller: scrollController,
                                child: ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                                  itemCount: displayItems.length,
                                  prototypeItem: const DisplayListTile(
                                    text: '',
                                    isSelected: false,
                                  ),
                                  itemBuilder: (context, index) => DisplayListTile(
                                    text: displayItems[index].title(context),
                                    isSelected: selectedDisplayItem == index,
                                    onTap: () async => _navigateToScreen(displayItems[index]),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, color: const Color(0x22FFFFFF)),
                      Expanded(
                        flex: 53,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Column(
                            children: [
                              const Expanded(
                                flex: 52,
                                child: AnimatedAlbumArtScroller(),
                              ),
                              const SizedBox(height: 12),
                              const Expanded(
                                flex: 26,
                                child: NowPlayingPreviewWidget(),
                              ),
                              const SizedBox(height: 12),
                              const Expanded(
                                flex: 22,
                                child: SettingsPreviewWidget(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HybridSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HybridSectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x22FFFFFF)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          MarqueeText(
            subtitle,
            mode: TextScrollMode.bouncing,
            intervalSpaces: 6,
            delayBefore: const Duration(milliseconds: 600),
            pauseBetween: const Duration(milliseconds: 900),
            pauseOnBounce: const Duration(milliseconds: 900),
            fadedBorder: true,
            fadedBorderWidth: 0.16,
            style: TextStyle(
              color: CupertinoColors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
