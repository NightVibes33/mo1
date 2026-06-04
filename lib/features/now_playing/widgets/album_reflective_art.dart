import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/constants/assets.dart';
import 'package:flutter/cupertino.dart';

class AlbumReflectiveArt extends StatefulWidget {
  final String? thumbnailPath;
  final bool isOnDevice;
  final double reflectedImageHeight;
  final double? imageWidth;
  final String heroTag;
  final bool tiltedImage;

  const AlbumReflectiveArt({
    super.key,
    this.thumbnailPath,
    this.isOnDevice = true,
    this.reflectedImageHeight = 50,
    this.imageWidth,
    required this.heroTag,
    this.tiltedImage = false,
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
      duration: const Duration(milliseconds: 360),
    );
    unawaited(_controller.forward());
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ImageProvider<Object> _imageProvider() {
    if (widget.thumbnailPath == null) {
      return const AssetImage(Assets.defaultAlbumCoverImage);
    }
    if (widget.isOnDevice) {
      return FileImage(File(widget.thumbnailPath!));
    }
    return NetworkImage(widget.thumbnailPath!);
  }

  Widget _albumImage({
    required double? height,
    required double width,
    required BoxFit fit,
    Alignment alignment = Alignment.center,
  }) {
    return Image(
      image: _imageProvider(),
      errorBuilder: (_, _, _) => Image.asset(
        Assets.defaultAlbumCoverImage,
        height: height,
        width: width,
        alignment: alignment,
        fit: fit,
      ),
      height: height,
      width: width,
      alignment: alignment,
      fit: fit,
    );
  }

  @override
  Widget build(BuildContext context) {
    late final Matrix4 transform;
    if (widget.tiltedImage) {
      transform = Matrix4.identity()
        ..setEntry(3, 2, 0.003)
        ..rotateY(-0.12);
    } else {
      transform = Matrix4.identity();
    }

    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final overlayTopColor = isDarkTheme
        ? AppPalette.darkReflectionOverlayColor1
        : const Color(0x66FFFFFF);
    final overlayBottomColor = isDarkTheme
        ? AppPalette.darkReflectionOverlayColor2
        : const Color(0xFFFFFFFF);
    final overlayBorderColor = isDarkTheme
        ? CupertinoColors.black
        : CupertinoColors.white;
    final imageWidth = widget.imageWidth ?? double.infinity;
    final reflectionWidth = widget.imageWidth != null
        ? (widget.imageWidth! - widget.reflectedImageHeight)
        : double.infinity;
    final artRadius = BorderRadius.circular(14);

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
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: artRadius,
                  border: Border.all(
                    color: CupertinoColors.white.withValues(alpha: 0.52),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: CupertinoColors.white.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(-1, -1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: artRadius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _albumImage(
                        height: widget.imageWidth,
                        width: imageWidth,
                        fit: (widget.imageWidth == null)
                            ? BoxFit.fitWidth
                            : BoxFit.scaleDown,
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.center,
                            colors: [
                              CupertinoColors.white.withValues(alpha: 0.28),
                              CupertinoColors.white.withValues(alpha: 0.02),
                              AppPalette.transparentColor,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: _animation,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(artRadius.bottomLeft.x),
                    ),
                    child: Transform.flip(
                      flipY: true,
                      child: _albumImage(
                        height: widget.reflectedImageHeight,
                        width: reflectionWidth,
                        alignment: Alignment.bottomCenter,
                        fit: BoxFit.fitWidth,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: widget.reflectedImageHeight,
                    width: reflectionWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: overlayBorderColor, width: 0),
                          right: BorderSide(
                            color: overlayBorderColor,
                            width: 0,
                          ),
                          bottom: BorderSide(
                            color: overlayBorderColor,
                            width: 0,
                          ),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [overlayTopColor, overlayBottomColor],
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
