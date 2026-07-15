import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/constants/assets.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/utils/metadata_artwork.dart';
import 'package:flutter/cupertino.dart';

class _SourceLogoBadge extends StatelessWidget {
  final MusicSourceType sourceType;
  final bool isSelected;

  const _SourceLogoBadge({
    required this.sourceType,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selectedOverlay = isSelected ? 0.18 : 0.0;
    return Container(
      width: 30,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        gradient: _sourceGradient(sourceType, selectedOverlay),
        border: Border.all(
          color: CupertinoColors.white.withOpacity(isSelected ? 0.55 : 0.18),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(isSelected ? 0.12 : 0.22),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: _SourceLogoIcon(sourceType: sourceType),
    );
  }

  LinearGradient _sourceGradient(
    MusicSourceType sourceType,
    double selectedOverlay,
  ) {
    switch (sourceType) {
      case MusicSourceType.appleMusic:
        return LinearGradient(
          colors: [
            Color.lerp(const Color(0xFFFF2D55), CupertinoColors.white, selectedOverlay)!,
            Color.lerp(const Color(0xFFAF52DE), CupertinoColors.white, selectedOverlay)!,
            Color.lerp(const Color(0xFFFF9500), CupertinoColors.white, selectedOverlay)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MusicSourceType.navidrome:
        return LinearGradient(
          colors: [
            Color.lerp(const Color(0xFF00C2FF), CupertinoColors.white, selectedOverlay)!,
            Color.lerp(const Color(0xFF007AFF), CupertinoColors.white, selectedOverlay)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MusicSourceType.jellyfin:
        return LinearGradient(
          colors: [
            Color.lerp(const Color(0xFFAA5CFF), CupertinoColors.white, selectedOverlay)!,
            Color.lerp(const Color(0xFF6D36FF), CupertinoColors.white, selectedOverlay)!,
            Color.lerp(const Color(0xFF00A4DC), CupertinoColors.white, selectedOverlay)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MusicSourceType.remote:
        return LinearGradient(
          colors: [
            Color.lerp(const Color(0xFF34C759), CupertinoColors.white, selectedOverlay)!,
            Color.lerp(const Color(0xFF007AFF), CupertinoColors.white, selectedOverlay)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MusicSourceType.local:
        return LinearGradient(
          colors: [
            Color.lerp(const Color(0xFF3A3A3C), CupertinoColors.white, selectedOverlay)!,
            Color.lerp(const Color(0xFF8E8E93), CupertinoColors.white, selectedOverlay)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }
}

class _SourceLogoIcon extends StatelessWidget {
  final MusicSourceType sourceType;

  const _SourceLogoIcon({required this.sourceType});

  @override
  Widget build(BuildContext context) {
    switch (sourceType) {
      case MusicSourceType.appleMusic:
        return const Icon(CupertinoIcons.music_note_2, size: 13, color: CupertinoColors.white);
      case MusicSourceType.navidrome:
        return CustomPaint(size: const Size(18, 12), painter: _NavidromeMarkPainter());
      case MusicSourceType.jellyfin:
        return CustomPaint(size: const Size(15, 15), painter: _JellyfinMarkPainter());
      case MusicSourceType.remote:
        return const Icon(CupertinoIcons.globe, size: 13, color: CupertinoColors.white);
      case MusicSourceType.local:
        return const Icon(CupertinoIcons.doc_text_fill, size: 13, color: CupertinoColors.white);
    }
  }
}

class _NavidromeMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CupertinoColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    final centerY = size.height / 2;
    for (var index = 0; index < 3; index++) {
      final x = 2.0 + index * 6;
      final path = Path()
        ..moveTo(x, centerY)
        ..quadraticBezierTo(x + 1.5, 1.2, x + 3, centerY)
        ..quadraticBezierTo(x + 4.5, size.height - 1.2, x + 6, centerY);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _JellyfinMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outer = Paint()..color = CupertinoColors.white.withOpacity(0.95);
    final inner = Paint()..color = CupertinoColors.black.withOpacity(0.22);
    final outerPath = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final innerPath = Path()
      ..moveTo(size.width / 2, size.height * 0.34)
      ..lineTo(size.width * 0.69, size.height * 0.74)
      ..lineTo(size.width * 0.31, size.height * 0.74)
      ..close();
    canvas.drawPath(outerPath, outer);
    canvas.drawPath(innerPath, inner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ExplicitBadge extends StatelessWidget {
  final Color color;

  const _ExplicitBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      width: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'E',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _ScaledTileText extends StatelessWidget {
  final String text;
  final double height;
  final double fontSize;
  final FontWeight fontWeight;
  final Color color;

  const _ScaledTileText({
    required this.text,
    required this.height,
    required this.fontSize,
    required this.fontWeight,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
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
            height: 1,
          ),
        ),
      ),
    );
  }
}

class SongListTile extends StatelessWidget {
  final MusicMetadata songMetadata;
  final bool isSelected;
  final bool isCurrentlyPlaying;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const SongListTile({
    super.key,
    required this.songMetadata,
    required this.isSelected,
    required this.isCurrentlyPlaying,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final borderColor = isDarkTheme
        ? AppPalette.darkListTileBorderColor
        : AppPalette.lightListTileBorderColor;
    final Border? tileBorder = isSelected
        ? null
        : Border(bottom: BorderSide(color: borderColor));
    final primaryColor = isSelected
        ? context.appInverseTextColor
        : context.appPrimaryTextColor;
    final secondaryColor = isSelected
        ? context.appInverseTextColor
        : context.appSecondaryTextColor;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppPalette.selectedTileGradientColor1,
                      AppPalette.selectedTileGradientColor2,
                    ],
                  )
                : null,
            border: tileBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Image(
                  image: metadataArtworkProvider(songMetadata.thumbnailPath),
                  errorBuilder: (_, _, _) => Image.asset(
                    Assets.defaultAlbumCoverImage,
                    fit: BoxFit.fitWidth,
                  ),
                  height: 54,
                  width: 54,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ScaledTileText(
                          text: songMetadata.getTrackArtistNames ??
                              context.localization.unknownArtist,
                          height: 16,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: secondaryColor,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: _ScaledTileText(
                                text: songMetadata.trackName ??
                                    context.localization.unknownSong,
                                height: 20,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                            if (songMetadata.isExplicit) ...[
                              const SizedBox(width: 6),
                              _ExplicitBadge(color: secondaryColor),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SourceLogoBadge(
                  sourceType: songMetadata.sourceType,
                  isSelected: isSelected,
                ),
                if (isCurrentlyPlaying) ...[
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.volume_up,
                    size: 18,
                    color: primaryColor,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
