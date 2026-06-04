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

  const _LyricsPreview({required this.lyrics});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.white.withValues(alpha: 0.16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          _previewText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.appPrimaryTextColor.withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.18,
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
      child: Row(
        key: ValueKey('Now Playing-${currentMetadata?.originalSongIndex}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedScale(
            scale: nowPlayingDetails.isPlaying ? 1.02 : 1,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            child: SizedBox(
              height: 198,
              width: 146,
              child: AlbumReflectiveArt(
                imageWidth: 196,
                tiltedImage: true,
                thumbnailPath: currentMetadata?.thumbnailPath,
                isOnDevice: currentMetadata?.isOnDevice ?? true,
                heroTag: heroTag,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: LiquidGlass(
              borderRadius: BorderRadius.circular(18),
              blur: 12,
              opacity: 0.22,
              borderColor: CupertinoColors.white.withValues(alpha: 0.32),
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
              gradientColors: [
                CupertinoColors.white.withValues(alpha: 0.34),
                const Color(0xFFFF4FD8).withValues(alpha: 0.08),
                CupertinoColors.white.withValues(alpha: 0.08),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarqueeText(
                    currentMetadata?.trackName ??
                        context.localization.unknownSong,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.appPrimaryTextColor,
                    ),
                    delayBefore: const Duration(seconds: 2),
                    pauseBetween: const Duration(seconds: 2),
                    pauseOnBounce: const Duration(seconds: 2),
                  ),
                  const SizedBox(height: 5),
                  MarqueeText(
                    currentMetadata?.getTrackArtistNames ??
                        context.localization.unknownArtist,
                    style: TextStyle(
                      color: context.appSecondaryTextColor,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    delayBefore: const Duration(seconds: 2),
                    pauseBetween: const Duration(seconds: 2),
                    pauseOnBounce: const Duration(seconds: 2),
                  ),
                  const SizedBox(height: 4),
                  MarqueeText(
                    currentMetadata?.albumName ?? context.localization.unknownAlbum,
                    style: TextStyle(
                      color: context.appSecondaryTextColor,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    delayBefore: const Duration(seconds: 2),
                    pauseBetween: const Duration(seconds: 2),
                    pauseOnBounce: const Duration(seconds: 2),
                  ),
                  if ((currentMetadata?.rating ?? 0) != 0)
                    Row(
                      children: List.generate(
                        currentMetadata?.rating ?? 0,
                        (index) => const Padding(
                          padding: EdgeInsets.only(
                            right: 2,
                            top: 3,
                            bottom: 2,
                          ),
                          child: Icon(
                            CupertinoIcons.star_fill,
                            size: 13,
                            color: AppPalette.selectedTileGradientColor2,
                          ),
                        ),
                      ),
                    ),
                  if ((currentMetadata?.rating ?? 0) == 0)
                    const SizedBox(height: 18),
                  if (hasLyrics) ...[
                    const SizedBox(height: 7),
                    _LyricsPreview(lyrics: lyrics!),
                    const SizedBox(height: 6),
                  ] else
                    const SizedBox(height: 16),
                  Text(
                    '${nowPlayingDetails.currentIndex + 1} '
                    '${context.localization.commonOfText} '
                    '${nowPlayingDetails.metadataList.length}',
                    style: TextStyle(
                      color: context.appPrimaryTextColor,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
