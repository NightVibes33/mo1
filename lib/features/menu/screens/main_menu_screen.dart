import 'dart:async';

import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/core/widgets/display_list_tile.dart';
import 'package:dope/core/widgets/marquee_text.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/menu/controller/split_screen_controller.dart';
import 'package:dope/features/menu/models/split_screen_type.dart';
import 'package:dope/features/menu/widgets/animated_album_art_scroller.dart';
import 'package:dope/features/menu/widgets/now_playing_preview_widget.dart';
import 'package:dope/features/menu/widgets/settings_preview_widget.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:dope/features/tutorial/controller/tutorial_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _MainMenuDisplayItems {
  music,
  settings,
  shuffleSongs,
  nowPlaying;

  String title(BuildContext context) {
    switch (this) {
      case music:
        return context.localization.musicMenuScreenTitle;
      case settings:
        return context.localization.settingsScreenTitle;
      case shuffleSongs:
        return context.localization.shuffleSongsMenuTitle;
      case nowPlaying:
        return context.localization.nowPlayingScreenTitle;
    }
  }
}

class MainMenuScreen extends ConsumerStatefulWidget {
  final bool showTutorial;

  const MainMenuScreen({super.key, this.showTutorial = false});

  @override
  ConsumerState createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends ConsumerState<MainMenuScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.menu.name;

  @override
  List<_MainMenuDisplayItems> get displayItems => _MainMenuDisplayItems.values;

  @override
  void onMenuButtonPressed() {
    return;
  }

  @override
  Future<void> onSelectPressed() =>
      _navigateToScreen(_MainMenuDisplayItems.values[selectedDisplayItem]);

  Future<void> _navigateToScreen(_MainMenuDisplayItems menuItem) async {
    setState(() => selectedDisplayItem = displayItems.indexOf(menuItem));
    switch (menuItem) {
      case _MainMenuDisplayItems.music:
        context.goNamed(Routes.musicMenu.name);
        break;
      case _MainMenuDisplayItems.nowPlaying:
        await _navigateToNowPlayingScreen();
        break;
      case _MainMenuDisplayItems.settings:
        context.goNamed(Routes.settings.name);
        break;
      case _MainMenuDisplayItems.shuffleSongs:
        await ref.read(audioPlayerServiceProvider.notifier).shuffleAllSongs();
        await _navigateToNowPlayingScreen();
        break;
    }
  }

  Future<void> _navigateToNowPlayingScreen() async {
    unawaited(ref.read(splitScreenViewControllerProvider).closeSplitView());
    await context.pushNamed(Routes.nowPlaying.name, extra: Routes.menu.name);
    unawaited(ref.read(splitScreenViewControllerProvider).openSplitView());
  }

  Future<void> _changeSplitScreenType() async {
    await Future.delayed(const Duration(milliseconds: 150));
    switch (displayItems[selectedDisplayItem]) {
      case _MainMenuDisplayItems.music:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.albumArt;
        break;
      case _MainMenuDisplayItems.settings:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.settings;
        break;
      case _MainMenuDisplayItems.shuffleSongs:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.shuffle;
        break;
      case _MainMenuDisplayItems.nowPlaying:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.nowPlaying;
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tutorialControllerProvider.notifier).playMenuTutorial();
    });
  }

  @override
  void didUpdateWidget(covariant MainMenuScreen oldWidget) {
    if (widget.showTutorial) {
      ref.read(tutorialControllerProvider.notifier).playMenuTutorial();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    unawaited(_changeSplitScreenType());
    if (!ref.read(splitScreenViewControllerProvider).isScreenVisible) {
      unawaited(ref.read(splitScreenViewControllerProvider).openSplitView());
    }

    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.menu.title(context)),
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
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 50,
                        child: Column(
                          children: [
                            _HybridSectionHeader(
                              title: Routes.menu.title(context),
                              subtitle: 'Library · playback · settings',
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
                                  itemBuilder: (context, index) {
                                    return DisplayListTile(
                                      key: ValueKey(displayItems[index]),
                                      text: displayItems[index].title(context),
                                      isSelected: selectedDisplayItem == index,
                                      onTap: () async => _navigateToScreen(displayItems[index]),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, color: const Color(0x22FFFFFF)),
                      Expanded(
                        flex: 50,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Column(
                            children: [
                              const Expanded(
                                flex: 50,
                                child: AnimatedAlbumArtScroller(),
                              ),
                              const SizedBox(height: 12),
                              const Expanded(
                                flex: 26,
                                child: NowPlayingPreviewWidget(),
                              ),
                              const SizedBox(height: 12),
                              const Expanded(
                                flex: 24,
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
