import 'dart:math' as math;

import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/services/native_eq_player_service.dart';
import 'package:dope/features/now_playing/models/now_playing_model.dart';
import 'package:dope/features/now_playing/widgets/album_reflective_art.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String? _eqStatusText({
  required MusicMetadata? currentMetadata,
  required bool eqRequested,
  required bool nativeEqActive,
  required String title,
}) {
  if (!eqRequested) {
    return null;
  }
  if (currentMetadata == null) {
    return null;
  }
  if (currentMetadata.isAppleMusicCatalogTrack) {
    return 'EQ unavailable: Apple Music';
  }
  if (nativeEqActive) {
    return 'EQ active: $title';
  }
  return 'EQ unavailable for this track';
}

class _EqStatusPill extends StatelessWidget {
  final String text;

  const _EqStatusPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBlue.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: CupertinoColors.systemBlue.withValues(alpha: 0.32),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: CupertinoColors.systemBlue,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ScaledLineText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final Color color;

  const _ScaledLineText({
    required this.text,
    required this.fontSize,
    required this.fontWeight,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: fontSize * 1.18,
      child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: 1.02,
          ),
        ),
      ),
    );
  }
}

class NowPlayingWidget extends ConsumerWidget {
  final NowPlayingModel nowPlayingDetails;

  const NowPlayingWidget({super.key, required this.nowPlayingDetails});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMetadata = nowPlayingDetails.currentMetadata;
    final settings = ref.watch(settingsPreferencesControllerProvider);
    final nativeEqActive = ref.watch(nativeEqPlaybackActiveProvider);
    final eqStatus = _eqStatusText(
      currentMetadata: currentMetadata,
      eqRequested: !settings.activeEqualizerHasNeutralCurve,
      nativeEqActive: nativeEqActive,
      title: settings.equalizerDisplayTitle,
    );
    final heroTag =
        '${currentMetadata?.albumName}-${currentMetadata?.albumArtistName}';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: LayoutBuilder(
        key: ValueKey('Now Playing-${currentMetadata?.sourceIdentityKey}'),
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final gap = width < 330 ? 14.0 : 20.0;
          final tentativeArtSide = (width * 0.47).clamp(136.0, 214.0).toDouble();
          final reflectionHeight =
              (tentativeArtSide * 0.34).clamp(34.0, 70.0).toDouble();
          final maxArtForHeight = math.max(108.0, height - reflectionHeight - 6);
          final artSide = math.min(tentativeArtSide, maxArtForHeight);
          final infoWidth = math.max(112.0, width - artSide - gap);
          final titleSize = (infoWidth * 0.18).clamp(20.0, 30.0).toDouble();
          final metaSize = (infoWidth * 0.14).clamp(14.0, 21.0).toDouble();
          final countSize = (infoWidth * 0.135).clamp(14.0, 20.0).toDouble();

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
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
              SizedBox(width: gap),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: math.max(10.0, height * 0.11),
                    bottom: math.max(10.0, height * 0.11),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ScaledLineText(
                        text: currentMetadata?.trackName ??
                            context.localization.unknownSong,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        color: context.appPrimaryTextColor,
                      ),
                      const SizedBox(height: 8),
                      _ScaledLineText(
                        text: currentMetadata?.getTrackArtistNames ??
                            context.localization.unknownArtist,
                        fontSize: metaSize,
                        fontWeight: FontWeight.w500,
                        color: context.appSecondaryTextColor,
                      ),
                      const SizedBox(height: 6),
                      _ScaledLineText(
                        text: currentMetadata?.albumName ??
                            context.localization.unknownAlbum,
                        fontSize: metaSize,
                        fontWeight: FontWeight.w500,
                        color: context.appSecondaryTextColor,
                      ),
                      if (eqStatus != null) ...[
                        const SizedBox(height: 8),
                        _EqStatusPill(text: eqStatus),
                      ],
                      const Spacer(),
                      Text(
                        '${nowPlayingDetails.currentIndex + 1} / '
                        '${nowPlayingDetails.metadataList.length}',
                        style: TextStyle(
                          color: context.appSecondaryTextColor,
                          fontSize: countSize,
                          fontWeight: FontWeight.w500,
                          height: 1,
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
