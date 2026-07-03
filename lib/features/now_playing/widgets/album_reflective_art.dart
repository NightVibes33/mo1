import 'dart:async';
import 'dart:math';

import 'package:dope/core/constants/assets.dart';
import 'package:dope/core/utils/metadata_artwork.dart';
import 'package:flutter/cupertino.dart';

class AlbumReflectiveArt extends StatefulWidget {
  final String? thumbnailPath;
  final bool isOnDevice;
  final double reflectedImageHeight;
  final double? imageWidth;
  final String heroTag;
  final bool tiltedImage;
  final BoxFit artworkFit;

  const AlbumReflectiveArt({
    super.key,
    this.thumbnailPath,
    this.isOnDevice = true,
    this.reflectedImageHeight = 50,
    this.imageWidth,
    required this.heroTag,
    this.tiltedImage = false,
    this.artworkFit = BoxFit.cover,
  });

  @override
  State<AlbumReflectiveArt> createState() => _AlbumReflectiveArtState();
}

class _AlbumReflectiveArtState extends State<AlbumReflectiveArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    unawaited(_controller.forward());
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late final Matrix4 transform;
    if (widget.tiltedImage) {
      transform = Matrix4.identity()
        ..setEntry(3, 2, 0.003)
        ..rotateY(-0.11);
    } else {
      transform = Matrix4.identity();
    }

    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final imageWidth = widget.imageWidth ?? double.infinity;
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

    Widget artworkImage({double? height, Alignment alignment = Alignment.center}) {
      return Image(
        image: metadataArtworkProvider(widget.thumbnailPath),
        errorBuilder: (_, _, _) => Image.asset(
          Assets.defaultAlbumCoverImage,
          height: height,
          width: imageWidth,
          alignment: alignment,
          fit: widget.artworkFit,
        ),
        height: height,
        width: imageWidth,
        alignment: alignment,
        fit: widget.artworkFit,
      );
    }

    return Hero(
      tag: widget.heroTag,
      flightShuttleBuilder:
          (
            flightContext,
            animation,
            flightDirection,
            fromHeroContext,
            toHeroContext,
          ) {
            late final Widget sourceWidget;
            late final Widget destinationWidget;
            switch (flightDirection) {
              case HeroFlightDirection.push:
                sourceWidget = fromHeroContext.widget;
                destinationWidget = toHeroContext.widget;
              case HeroFlightDirection.pop:
                sourceWidget = toHeroContext.widget;
                destinationWidget = fromHeroContext.widget;
            }
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                if (animation.value < 0.01 || animation.value > 0.999) {
                  unawaited(_controller.forward());
                } else if (animation.isAnimating) {
                  _controller.reset();
                }
                return Transform(
                  transform: Matrix4.identity()..rotateY(animation.value * pi),
                  alignment: Alignment.center,
                  child: (animation.value > 0.5)
                      ? Transform.flip(flipX: true, child: destinationWidget)
                      : child,
                );
              },
              child: sourceWidget,
            );
          },
      child: Transform(
        transform: transform,
        alignment: Alignment.center,
        child: Column(
          children: [
            Flexible(child: artworkImage(height: widget.imageWidth)),
            FadeTransition(
              opacity: _animation,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Opacity(
                    opacity: reflectionOpacity,
                    child: Transform.flip(
                      flipY: true,
                      child: artworkImage(
                        height: widget.reflectedImageHeight,
                        alignment: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: widget.reflectedImageHeight,
                    width: imageWidth,
                    child: DecoratedBox(
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
