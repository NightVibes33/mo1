import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/core/widgets/marquee_text.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:classipod/features/now_playing/widgets/accurate_waveform_visualizer.dart';
import 'package:classipod/features/now_playing/widgets/album_reflective_art.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NowPlayingWidget extends ConsumerWidget {
  final NowPlayingModel nowPlayingDetails;

  const NowPlayingWidget({super.key, required this.nowPlayingDetails});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMetadata = nowPlayingDetails.currentMetadata;
    final heroTag =
        '${currentMetadata?.albumName}-${currentMetadata?.albumArtistName}';
    final audioPlayer = ref.watch(audioPlayerProvider);
    final waveformDuration = currentMetadata?.trackDuration == null
        ? audioPlayer.duration
        : Duration(milliseconds: currentMetadata!.trackDuration!);

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
                  SizedBox(
                    height: 42,
                    width: double.infinity,
                    child: AccurateWaveformVisualizer(
                      metadata: currentMetadata,
                      positionStream: audioPlayer.positionStream,
                      duration: waveformDuration,
                    ),
                  ),
                  const SizedBox(height: 4),
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
