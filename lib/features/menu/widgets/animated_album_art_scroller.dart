import 'dart:async';

import 'package:dope/core/constants/assets.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/providers/filtered_audio_files_provider.dart';
import 'package:dope/core/utils/metadata_artwork.dart';
import 'package:dope/core/widgets/empty_state_widget.dart';
import 'package:dope/features/menu/models/split_screen_type.dart';
import 'package:dope/features/music/album/models/album_model.dart';
import 'package:dope/features/music/album/providers/album_details_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnimatedAlbumArtScroller extends ConsumerStatefulWidget {
  const AnimatedAlbumArtScroller({super.key});

  @override
  ConsumerState createState() => _AnimatedAlbumArtScrollerState();
}

class _AnimatedAlbumArtScrollerState
    extends ConsumerState<AnimatedAlbumArtScroller> {
  Timer? _rotationTimer;
  late final PageController _pageController;
  double _currentPage = 0;
  String _albumSignature = '';

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.56);
    _pageController.addListener(_updateCurrentPage);
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _pageController
      ..removeListener(_updateCurrentPage)
      ..dispose();
    super.dispose();
  }

  void _updateCurrentPage() {
    final nextPage = _pageController.page ?? _currentPage;
    if ((nextPage - _currentPage).abs() < 0.001) {
      return;
    }
    setState(() {
      _currentPage = nextPage;
    });
  }

  void _stopAlbumRotation() {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _albumSignature = '';
    _currentPage = 0;
  }

  void _syncAlbumRotation(List<AlbumModel> albums) {
    final signature = albums
        .map((album) => '${album.albumName}::${album.albumArtistName}')
        .join('||');
    if (_albumSignature == signature) {
      return;
    }

    _albumSignature = signature;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _currentPage = 0;
    if (_pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) {
          return;
        }
        _pageController.jumpToPage(0);
      });
    }

    if (albums.length <= 1) {
      return;
    }

    _rotationTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || !_pageController.hasClients) {
        return;
      }
      final nextPage =
          ((_pageController.page ?? 0).round() + 1) % albums.length;
      await _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final metadataState = ref.watch(filteredAudioFilesProvider);

    return metadataState.when(
      data: (_) {
        final albums = ref.watch(albumDetailsProvider);
        _syncAlbumRotation(albums);

        if (albums.isEmpty) {
          return EmptyStateWidget(
            emptyDescription: context.localization.noMusicFilesFound,
          );
        }

        return _AlbumArtCarousel(
          albums: albums,
          currentPage: _currentPage,
          pageController: _pageController,
        );
      },
      loading: () {
        _stopAlbumRotation();
        return const _AlbumArtFallback();
      },
      error: (_, _) {
        _stopAlbumRotation();
        return const _AlbumArtFallback();
      },
    );
  }
}

class _AlbumArtCarousel extends StatelessWidget {
  final List<AlbumModel> albums;
  final double currentPage;
  final PageController pageController;

  const _AlbumArtCarousel({
    required this.albums,
    required this.currentPage,
    required this.pageController,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = currentPage
        .round()
        .clamp(0, albums.length - 1)
        .toInt();
    final selectedAlbum = albums[selectedIndex];

    return _AlbumArtBackdrop(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          final availableWidth = constraints.maxWidth;
          const textBlockHeight = 52.0;
          const bottomTextGap = 8.0;
          final previewHeight =
              (availableHeight - textBlockHeight - bottomTextGap)
                  .clamp(148.0, 250.0)
                  .toDouble();
          final pageWidth = availableWidth * 0.56;
          final flowHeight = previewHeight.clamp(148.0, 250.0).toDouble();
          final artWidth = (flowHeight * 0.92)
              .clamp(136.0, pageWidth * 0.82)
              .toDouble();
          final reflectionHeight = (artWidth * 0.18)
              .clamp(24.0, 34.0)
              .toDouble();
          final artStackHeight = artWidth + reflectionHeight;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: textBlockHeight + bottomTextGap,
                child: Center(
                  child: SizedBox(
                    height: artStackHeight,
                    child: PageView.builder(
                      controller: pageController,
                      itemCount: albums.length,
                      padEnds: true,
                      allowImplicitScrolling: true,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        final relativePosition = (index - currentPage)
                            .clamp(-1.5, 1.5)
                            .toDouble();
                        final distance = relativePosition.abs();
                        final scale = (1 - distance * 0.16)
                            .clamp(0.74, 1.0)
                            .toDouble();
                        final album = albums[index];

                        return Transform(
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
                          child: Center(
                            child: _PreviewAlbumReflectiveArt(
                              imageWidth: artWidth,
                              reflectedImageHeight: reflectionHeight,
                              thumbnailPath: album.albumArtPath,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Column(
                    key: ValueKey(
                      '${selectedAlbum.albumName}-${selectedAlbum.albumArtistName}',
                    ),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedAlbum.albumName,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appPrimaryTextColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedAlbum.albumArtistName,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appPrimaryTextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
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
    );
  }
}

class _AlbumArtFallback extends StatelessWidget {
  const _AlbumArtFallback();

  @override
  Widget build(BuildContext context) {
    return _AlbumArtBackdrop(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final flowHeight = constraints.maxHeight
              .clamp(160.0, 250.0)
              .toDouble();
          final artWidth = (flowHeight * 0.78).clamp(126.0, 178.0).toDouble();
          final reflectionHeight = (artWidth * 0.18)
              .clamp(20.0, 28.0)
              .toDouble();

          return Center(
            child: _PreviewAlbumReflectiveArt(
              imageWidth: artWidth,
              reflectedImageHeight: reflectionHeight,
              thumbnailPath: null,
            ),
          );
        },
      ),
    );
  }
}

class _AlbumArtBackdrop extends StatelessWidget {
  final Widget child;

  const _AlbumArtBackdrop({required this.child});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey(SplitScreenType.albumArt),
      child: ClipRect(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                context.appDeviceScreenBackgroundColor.withValues(alpha: 0.96),
                const Color(0xFF101215).withValues(alpha: 0.92),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PreviewAlbumReflectiveArt extends StatelessWidget {
  final String? thumbnailPath;
  final double imageWidth;
  final double reflectedImageHeight;

  const _PreviewAlbumReflectiveArt({
    required this.thumbnailPath,
    required this.imageWidth,
    required this.reflectedImageHeight,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final reflectionOpacity = isDarkTheme ? 0.42 : 0.32;
    final overlayTopColor = CupertinoColors.black.withValues(
      alpha: isDarkTheme ? 0.10 : 0.06,
    );
    final overlayMidColor = CupertinoColors.black.withValues(
      alpha: isDarkTheme ? 0.54 : 0.42,
    );
    final overlayBottomColor = CupertinoColors.black.withValues(
      alpha: isDarkTheme ? 0.94 : 0.84,
    );

    Widget artworkImage({
      required double height,
      Alignment alignment = Alignment.center,
    }) {
      return Image(
        image: metadataArtworkProvider(thumbnailPath),
        errorBuilder: (_, _, _) => Image.asset(
          Assets.defaultAlbumCoverImage,
          height: height,
          width: imageWidth,
          alignment: alignment,
          fit: BoxFit.cover,
        ),
        height: height,
        width: imageWidth,
        alignment: alignment,
        fit: BoxFit.cover,
      );
    }

    return SizedBox(
      width: imageWidth,
      height: imageWidth + reflectedImageHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: SizedBox(
              width: imageWidth,
              height: imageWidth,
              child: artworkImage(height: imageWidth),
            ),
          ),
          SizedBox(
            width: imageWidth,
            height: reflectedImageHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: reflectionOpacity,
                  child: Transform.flip(
                    flipY: true,
                    child: artworkImage(
                      height: reflectedImageHeight,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.38, 1.0],
                      colors: [
                        overlayTopColor,
                        overlayMidColor,
                        overlayBottomColor,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
