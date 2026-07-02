import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/constants/assets.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/utils/metadata_artwork.dart';
import 'package:flutter/cupertino.dart';

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
                        _ScaledTileText(
                          text: songMetadata.trackName ??
                              context.localization.unknownSong,
                          height: 20,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isCurrentlyPlaying)
                  Icon(
                    CupertinoIcons.volume_up,
                    size: 18,
                    color: primaryColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
