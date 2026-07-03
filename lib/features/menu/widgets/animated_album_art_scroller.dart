import 'dart:async';

import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/providers/filtered_audio_files_provider.dart';
import 'package:dope/core/widgets/empty_state_widget.dart';
import 'package:dope/features/menu/models/split_screen_type.dart';
import 'package:dope/features/music/album/models/album_model.dart';
import 'package:dope/features/music/album/providers/album_details_provider.dart';
import 'package:dope/features/now_playing/widgets/album_reflective_art.dart';
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
    _pageController = PageController(viewportFraction: 0.52);
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
      final nextPage = ((_pageController.page ?? 0).round() + 1) % albums.length;
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
        return EmptyStateWidget(
          emptyDescription: context.localization.noMusicFilesFound,
        );
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
          final flowHeight = (availableHeight - 44)
              .clamp(160.0, 250.0)
              .toDouble();
          final artWidth = (flowHeight * 0.92).clamp(145.0, 232.0).toDouble();

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: flowHeight,
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
                        child: AlbumReflectiveArt(
                          imageWidth: artWidth,
                          reflectedImageHeight: 34,
                          thumbnailPath: album.albumArtPath,
                          isOnDevice: album.isOnDevice(),
                          heroTag:
                              'preview-${album.albumName}-${album.albumArtistName}',
                        ),
                      );
                    },
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
          final flowHeight = constraints.maxHeight.clamp(160.0, 250.0).toDouble();
          final artWidth = (flowHeight * 0.74).clamp(118.0, 168.0).toDouble();
          final reflectionHeight = (artWidth * 0.22).clamp(18.0, 26.0).toDouble();

          return Center(
            child: AlbumReflectiveArt(
              imageWidth: artWidth,
              reflectedImageHeight: reflectionHeight,
              thumbnailPath: null,
              heroTag: 'preview-default-album-art',
              artworkFit: BoxFit.cover,
              clipArtwork: true,
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
