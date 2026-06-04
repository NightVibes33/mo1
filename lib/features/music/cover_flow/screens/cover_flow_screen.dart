import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/widgets/empty_state_widget.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/features/custom_screen_elements/custom_page_screen.dart';
import 'package:classipod/features/music/album/models/album_model.dart';
import 'package:classipod/features/music/album/providers/album_details_provider.dart';
import 'package:classipod/features/now_playing/widgets/album_reflective_art.dart';
import 'package:classipod/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CoverFlowScreen extends ConsumerStatefulWidget {
  const CoverFlowScreen({super.key});

  @override
  ConsumerState createState() => _CoverFlowScreenState();
}

class _CoverFlowScreenState extends ConsumerState<CoverFlowScreen>
    with CustomPageScreen {
  @override
  String get routeName => Routes.coverFlow.name;

  @override
  double get viewPortFraction => 0.54;

  @override
  List<AlbumModel> get displayItems => ref.read(albumDetailsProvider);

  @override
  void onSelectPressed() => _chooseAlbum(selectedDisplayItem);

  void _chooseAlbum(int index) {
    final albumDetail = ref.read(albumDetailsProvider).elementAt(index);
    unawaited(
      context.pushNamed(Routes.coverFlowSelection.name, extra: albumDetail),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (displayItems.isEmpty) {
      return CupertinoPageScaffold(
        child: Column(
          children: [
            StatusBar(title: Routes.coverFlow.title(context)),
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
          StatusBar(title: Routes.coverFlow.title(context)),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 38,
                  height: 76,
                  child: LiquidGlass(
                    borderRadius: BorderRadius.circular(28),
                    blur: 18,
                    opacity: 0.22,
                    borderColor: CupertinoColors.white.withValues(alpha: 0.22),
                    gradientColors: [
                      const Color(0xFF45FFE6).withValues(alpha: 0.18),
                      CupertinoColors.white.withValues(alpha: 0.08),
                      const Color(0xFFFF54D6).withValues(alpha: 0.08),
                    ],
                    child: const SizedBox.expand(),
                  ),
                ),
                SizedBox(
                  height: 228,
                  child: PageView.builder(
                    controller: pageController,
                    itemCount: displayItems.length,
                    itemBuilder: (context, index) {
                      final double relativePosition = index - currentPage;
                      final double depth =
                          (1 - relativePosition.abs()).clamp(0.18, 0.7).toDouble() +
                          0.34;
                      return GestureDetector(
                        onTap: relativePosition == 0
                            ? () => _chooseAlbum(index)
                            : () async => pageController.animateToPage(
                                index,
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.easeOutCubic,
                              ),
                        child: AnimatedScale(
                          scale: relativePosition.abs() < 0.04 ? 1.03 : 1,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Transform(
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.003)
                              ..translate(0.0, relativePosition.abs() * 12)
                              ..scaleByDouble(depth, depth, depth, 1)
                              ..rotateY(relativePosition * 0.96),
                            alignment: relativePosition >= 0
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: AlbumReflectiveArt(
                              imageWidth: 230,
                              thumbnailPath: displayItems[index].albumArtPath,
                              isOnDevice: displayItems[index].isOnDevice(),
                              heroTag:
                                  '${displayItems[index].albumName}-${displayItems[index].albumArtistName}',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 12,
                  right: 12,
                  child: LiquidGlass(
                    borderRadius: BorderRadius.circular(16),
                    blur: 14,
                    opacity: 0.24,
                    borderColor: CupertinoColors.white.withValues(alpha: 0.28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayItems[selectedDisplayItem].albumName,
                          maxLines: 1,
                          style: TextStyle(
                            color: context.appPrimaryTextColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          displayItems[selectedDisplayItem].albumArtistName,
                          maxLines: 1,
                          style: TextStyle(
                            color: context.appSecondaryTextColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
