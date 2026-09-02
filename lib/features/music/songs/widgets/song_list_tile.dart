import 'package:dopi/core/constants/app_palette.dart';
import 'package:dopi/core/constants/assets.dart';
import 'package:dopi/core/extensions/build_context_extensions.dart';
import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/utils/metadata_artwork.dart';
import 'package:flutter/cupertino.dart';

const _appleMusicSourceIcon =
    'assets/images/source_icons/apple_music.png';
const _navidromeSourceIcon = 'assets/images/source_icons/navidrome.png';
const _jellyfinSourceIcon = 'assets/images/source_icons/jellyfin.png';

class _SourceLogoBadge extends StatelessWidget {
  final MusicSourceType sourceType;
  final bool isSelected;

  const _SourceLogoBadge({
    required this.sourceType,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final backgroundColor = isSelected
        ? CupertinoColors.white.withOpacity(0.16)
        : isDarkTheme
        ? CupertinoColors.white.withOpacity(0.08)
        : CupertinoColors.black.withOpacity(0.05);
    final borderColor = isSelected
        ? CupertinoColors.white.withOpacity(0.45)
        : isDarkTheme
        ? CupertinoColors.white.withOpacity(0.14)
        : CupertinoColors.black.withOpacity(0.10);

    return Container(
      width: 30,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: backgroundColor,
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: _SourceLogoIcon(
        sourceType: sourceType,
        isSelected: isSelected,
      ),
    );
  }
}

class _BrandedSourceImage extends StatelessWidget {
  final String assetPath;
  final double size;
  final IconData fallbackIcon;
  final Color fallbackColor;

  const _BrandedSourceImage({
    required this.assetPath,
    required this.size,
    required this.fallbackIcon,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => Icon(
        fallbackIcon,
        size: size - 1,
        color: fallbackColor,
      ),
    );
  }
}

class _SourceLogoIcon extends StatelessWidget {
  final MusicSourceType sourceType;
  final bool isSelected;

  const _SourceLogoIcon({
    required this.sourceType,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    switch (sourceType) {
      case MusicSourceType.appleMusic:
        return const _BrandedSourceImage(
          assetPath: _appleMusicSourceIcon,
          size: 16,
          fallbackIcon: CupertinoIcons.music_note_2,
          fallbackColor: Color(0xFFFF2D55),
        );
      case MusicSourceType.navidrome:
        return const _BrandedSourceImage(
          assetPath: _navidromeSourceIcon,
          size: 17,
          fallbackIcon: CupertinoIcons.music_note_2,
          fallbackColor: Color(0xFF0084FF),
        );
      case MusicSourceType.jellyfin:
        return const _BrandedSourceImage(
          assetPath: _jellyfinSourceIcon,
          size: 16,
          fallbackIcon: CupertinoIcons.play_rectangle_fill,
          fallbackColor: Color(0xFF7C63C7),
        );
      case MusicSourceType.remote:
        return Icon(
          CupertinoIcons.globe,
          size: 14,
          color: isSelected
              ? context.appInverseTextColor
              : context.appSecondaryTextColor,
        );
      case MusicSourceType.local:
        return Icon(
          CupertinoIcons.music_note_2,
          size: 14,
          color: isSelected
              ? context.appInverseTextColor
              : context.appSecondaryTextColor,
        );
    }
  }
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
