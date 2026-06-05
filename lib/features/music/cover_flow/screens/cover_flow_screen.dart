import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/widgets/empty_state_widget.dart';
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
  double get viewPortFraction => 0.5;

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
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final flowHeight = (constraints.maxHeight - 34)
                    .clamp(198.0, 252.0)
                    .toDouble();
                final artWidth = (flowHeight * 0.92).clamp(190.0, 232.0).toDouble();

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(
                      height: flowHeight,
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: displayItems.length,
                        padEnds: true,
                        allowImplicitScrolling: true,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          final relativePosition =
                              (index - currentPage).clamp(-1.5, 1.5).toDouble();
                          final distance = relativePosition.abs();
                          final scale = (1 - distance * 0.16)
                              .clamp(0.74, 1.0)
                              .toDouble();
                          return GestureDetector(
                            onTap: distance < 0.08
                                ? () => _chooseAlbum(index)
                                : () async => pageController.animateToPage(
                                    index,
                                    duration: const Duration(milliseconds: 360),
                                    curve: Curves.easeOutCubic,
                                  ),
                            child: Transform(
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0022)
                                ..translate(
                                  relativePosition * -10,
                                  0.0,
                                  -distance * 72,
                                )
                                ..scaleByDouble(scale, scale, scale, 1)
                                ..rotateY(relativePosition * 0.72),
                              alignment: relativePosition >= 0
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              child: AlbumReflectiveArt(
                                imageWidth: artWidth,
                                thumbnailPath: displayItems[index].albumArtPath,
                                isOnDevice: displayItems[index].isOnDevice(),
                                heroTag:
                                    "${displayItems[index].albumName}-${displayItems[index].albumArtistName}",
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            Text(
                              displayItems[selectedDisplayItem].albumName,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              displayItems[selectedDisplayItem].albumArtistName,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
