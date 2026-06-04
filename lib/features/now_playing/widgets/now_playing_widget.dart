import 'dart:math' as math;

import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/core/widgets/marquee_text.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:classipod/features/now_playing/widgets/album_reflective_art.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _LyricsPreview extends StatelessWidget {
  final String lyrics;
  final double fontSize;

  const _LyricsPreview({required this.lyrics, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CupertinoColors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Text(
          _previewText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.appPrimaryTextColor.withValues(alpha: 0.92),
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            height: 1.08,
          ),
        ),
      ),
    );
  }

  String get _previewText {
    final timestampRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]');
    for (final line in lyrics.split(RegExp(r'\r?\n'))) {
      final cleaned = line.replaceAll(timestampRegex, '').trim();
      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }
    return lyrics;
  }
}

class NowPlayingWidget extends ConsumerWidget {
  final NowPlayingModel nowPlayingDetails;

  const NowPlayingWidget({super.key, required this.nowPlayingDetails});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMetadata = nowPlayingDetails.currentMetadata;
    final heroTag =
        '${currentMetadata?.albumName}-${currentMetadata?.albumArtistName}';
    final lyrics = currentMetadata?.lyrics?.trim();
    final hasLyrics = lyrics != null && lyrics.isNotEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: LayoutBuilder(
        key: ValueKey('Now Playing-${currentMetadata?.originalSongIndex}'),
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final gap = width < 330 ? 6.0 : 9.0;
          final reflectionHeight = (height * 0.18).clamp(20.0, 36.0).toDouble();
          final maxArtForHeight = math.max(82.0, height - reflectionHeight - 6);
          final artSide = math.min(
            (width * 0.42).clamp(98.0, 164.0).toDouble(),
            maxArtForHeight,
          );
          final panelWidth = math.max(120.0, width - artSide - gap);
          final titleSize = (panelWidth * 0.16).clamp(18.0, 26.0).toDouble();
          final metaSize = (panelWidth * 0.115).clamp(13.0, 18.0).toDouble();
          final indexSize = (panelWidth * 0.13).clamp(14.0, 20.0).toDouble();
          final lyricSize = (panelWidth * 0.105).clamp(12.0, 16.0).toDouble();
          final ratingCount = (currentMetadata?.rating ?? 0).clamp(0, 5).toInt();
          final showRating = height > 122;
          final showLyricsPreview = hasLyrics && height > 152;

          return ClipRect(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedScale(
                  scale: nowPlayingDetails.isPlaying ? 1.015 : 1,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  child: SizedBox(
                    height: artSide + reflectionHeight,
                    width: artSide,
                    child: AlbumReflectiveArt(
                      imageWidth: artSide,
                      reflectedImageHeight: reflectionHeight,
                      tiltedImage: true,
                      thumbnailPath: currentMetadata?.thumbnailPath,
                      isOnDevice: currentMetadata?.isOnDevice ?? true,
                      heroTag: heroTag,
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: SizedBox(
                    height: height,
                    child: LiquidGlass(
                      borderRadius: BorderRadius.circular(13),
                      blur: 8,
                      opacity: 0.16,
                      borderColor: CupertinoColors.black.withValues(alpha: 0.16),
                      padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
                      gradientColors: [
                        CupertinoColors.white.withValues(alpha: 0.32),
                        const Color(0xFFEAEAF1).withValues(alpha: 0.22),
                        CupertinoColors.white.withValues(alpha: 0.06),
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarqueeText(
                            currentMetadata?.trackName ??
                                context.localization.unknownSong,
                            fadedBorder: true,
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.w900,
                              color: context.appPrimaryTextColor,
                              height: 1,
                            ),
                            delayBefore: const Duration(milliseconds: 900),
                            pauseBetween: const Duration(milliseconds: 900),
                            pauseOnBounce: const Duration(milliseconds: 900),
                            velocity: const Velocity(
                              pixelsPerSecond: Offset(24, 0),
                            ),
                          ),
                          SizedBox(height: height > 165 ? 5 : 3),
                          MarqueeText(
                            currentMetadata?.getTrackArtistNames ??
                                context.localization.unknownArtist,
                            fadedBorder: true,
                            style: TextStyle(
                              color: context.appSecondaryTextColor,
                              fontSize: metaSize,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                            delayBefore: const Duration(milliseconds: 900),
                            pauseBetween: const Duration(milliseconds: 900),
                            pauseOnBounce: const Duration(milliseconds: 900),
                          ),
                          SizedBox(height: height > 165 ? 4 : 2),
                          MarqueeText(
                            currentMetadata?.albumName ??
                                context.localization.unknownAlbum,
                            fadedBorder: true,
                            style: TextStyle(
                              color: context.appSecondaryTextColor,
                              fontSize: metaSize,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                            delayBefore: const Duration(milliseconds: 900),
                            pauseBetween: const Duration(milliseconds: 900),
                            pauseOnBounce: const Duration(milliseconds: 900),
                          ),
                          if (showRating)
                            Padding(
                              padding: EdgeInsets.only(
                                top: height > 165 ? 5 : 3,
                                bottom: showLyricsPreview ? 4 : 0,
                              ),
                              child: Row(
                                children: List.generate(
                                  ratingCount,
                                  (index) => const Padding(
                                    padding: EdgeInsets.only(right: 2),
                                    child: Icon(
                                      CupertinoIcons.star_fill,
                                      size: 12,
                                      color: AppPalette.selectedTileGradientColor2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (showLyricsPreview)
                            _LyricsPreview(
                              lyrics: lyrics!,
                              fontSize: lyricSize,
                            ),
                          const Spacer(),
                          Text(
                            '${nowPlayingDetails.currentIndex + 1} '
                            '${context.localization.commonOfText} '
                            '${nowPlayingDetails.metadataList.length}',
                            style: TextStyle(
                              color: context.appPrimaryTextColor,
                              fontSize: indexSize,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
