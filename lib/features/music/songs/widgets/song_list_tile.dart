import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/constants/assets.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/utils/metadata_artwork.dart';
import 'package:flutter/cupertino.dart';

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
                  child: Text(
                    songMetadata.trackName ?? context.localization.unknownSong,
                    style: CupertinoTheme.of(context).textTheme.textStyle
                        .copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? context.appInverseTextColor
                              : context.appPrimaryTextColor,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCurrentlyPlaying)
                  Icon(
                    CupertinoIcons.volume_up,
                    size: 18,
                    color: isSelected
                        ? context.appInverseTextColor
                        : context.appPrimaryTextColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
