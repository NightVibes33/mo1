import 'dart:math' as math;

import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
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
        color: CupertinoColors.black.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: CupertinoColors.black.withValues(alpha: 0.07),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          _previewText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.appPrimaryTextColor.withValues(alpha: 0.9),
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1.06,
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
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: LayoutBuilder(
        key: ValueKey('Now Playing-${currentMetadata?.originalSongIndex}'),
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final gap = width < 330 ? 7.0 : 10.0;
          final reflectionHeight = (height * 0.12).clamp(14.0, 24.0).toDouble();
          final artSide = math.min(
            (width * 0.38).clamp(92.0, 138.0).toDouble(),
            math.max(82.0, height - reflectionHeight - 2),
          );
          final panelWidth = math.max(118.0, width - artSide - gap);
          final titleSize = (panelWidth * 0.105).clamp(16.0, 22.0).toDouble();
          final metaSize = (panelWidth * 0.075).clamp(12.5, 16.0).toDouble();
          final lyricSize = (panelWidth * 0.068).clamp(11.5, 14.0).toDouble();
          final indexSize = (panelWidth * 0.082).clamp(14.0, 18.0).toDouble();
          final ratingCount = (currentMetadata?.rating ?? 0).clamp(0, 5).toInt();
          final showRating = ratingCount > 0 && height > 118;
          final showLyricsPreview = hasLyrics && height > 132;

          return ClipRect(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedScale(
                    scale: nowPlayingDetails.isPlaying ? 1.01 : 1,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    child: SizedBox(
                      height: artSide + reflectionHeight,
                      width: artSide,
                      child: AlbumReflectiveArt(
                        imageWidth: artSide,
                        reflectedImageHeight: reflectionHeight,
                        tiltedImage: false,
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
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(2, 1, 2, 0),
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
                                height: 0.98,
                              ),
                              delayBefore: const Duration(milliseconds: 700),
                              pauseBetween: const Duration(milliseconds: 900),
                              pauseOnBounce: const Duration(milliseconds: 900),
                              velocity: const Velocity(
                                pixelsPerSecond: Offset(26, 0),
                              ),
                            ),
                            const SizedBox(height: 4),
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
                              delayBefore: const Duration(milliseconds: 700),
                              pauseBetween: const Duration(milliseconds: 900),
                              pauseOnBounce: const Duration(milliseconds: 900),
                            ),
                            const SizedBox(height: 3),
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
                              delayBefore: const Duration(milliseconds: 700),
                              pauseBetween: const Duration(milliseconds: 900),
                              pauseOnBounce: const Duration(milliseconds: 900),
                            ),
                            if (showRating)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Row(
                                  children: List.generate(
                                    ratingCount,
                                    (index) => const Padding(
                                      padding: EdgeInsets.only(right: 2),
                                      child: Icon(
                                        CupertinoIcons.star_fill,
                                        size: 10,
                                        color: AppPalette.selectedTileGradientColor2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (showLyricsPreview) ...[
                              const SizedBox(height: 5),
                              _LyricsPreview(
                                lyrics: lyrics!,
                                fontSize: lyricSize,
                              ),
                            ],
                            const Spacer(),
                            Text(
                              '${nowPlayingDetails.currentIndex + 1} '
                              '${context.localization.commonOfText} '
                              '${nowPlayingDetails.metadataList.length}',
                              maxLines: 1,
                              softWrap: false,
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
            ),
          );
        },
      ),
    );
  }
}
