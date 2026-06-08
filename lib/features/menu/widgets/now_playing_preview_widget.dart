import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/widgets/marquee_text.dart';
import 'package:classipod/features/menu/models/split_screen_type.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/now_playing/widgets/album_reflective_art.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NowPlayingPreviewWidget extends ConsumerWidget {
  const NowPlayingPreviewWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMetadata = ref.watch(
      nowPlayingDetailsProvider.select((e) => e.currentMetadata),
    );

    return SizedBox(
      key: const ValueKey(SplitScreenType.nowPlaying),
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppPalette.darkScreenBackgroundGradient1,
              AppPalette.darkScreenBackgroundGradient2,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: currentMetadata == null
              ? const _NoMusicPreview()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final artSize = (constraints.maxHeight * 0.54)
                        .clamp(112.0, 174.0)
                        .toDouble();
                    final reflectionHeight = (artSize * 0.22)
                        .clamp(24.0, 38.0)
                        .toDouble();

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: artSize + reflectionHeight,
                          child: AlbumReflectiveArt(
                            imageWidth: artSize,
                            reflectedImageHeight: reflectionHeight,
                            thumbnailPath: currentMetadata.thumbnailPath,
                            isOnDevice: currentMetadata.isOnDevice,
                            heroTag:
                                'now-playing-preview-${currentMetadata.originalSongIndex}',
                          ),
                        ),
                        const SizedBox(height: 8),
                        _PreviewMarqueeText(
                          text: currentMetadata.getTrackArtistNames ??
                              context.localization.unknownArtist,
                          fontSize: 14,
                          opacity: 0.82,
                        ),
                        const SizedBox(height: 4),
                        _PreviewMarqueeText(
                          text: currentMetadata.getTrackName,
                          fontSize: 17,
                          opacity: 1,
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _NoMusicPreview extends StatelessWidget {
  const _NoMusicPreview();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          CupertinoIcons.music_note_2,
          size: 65,
          color: CupertinoColors.white,
        ),
        SizedBox(height: 14),
        Text(
          'No Music',
          style: TextStyle(
            color: CupertinoColors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _PreviewMarqueeText extends StatelessWidget {
  final String text;
  final double fontSize;
  final double opacity;

  const _PreviewMarqueeText({
    required this.text,
    required this.fontSize,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: fontSize + 6,
      child: MarqueeText(
        text,
        mode: TextScrollMode.bouncing,
        intervalSpaces: null,
        delayBefore: const Duration(seconds: 1),
        pauseBetween: const Duration(seconds: 2),
        pauseOnBounce: const Duration(seconds: 2),
        fadedBorder: true,
        fadedBorderWidth: 0.18,
        style: TextStyle(
          color: CupertinoColors.white.withValues(alpha: opacity),
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
