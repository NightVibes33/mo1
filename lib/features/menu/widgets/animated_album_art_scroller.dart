import 'dart:io';
import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/widgets/empty_state_widget.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/features/menu/models/split_screen_type.dart';
import 'package:classipod/features/music/album/providers/album_details_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnimatedAlbumArtScroller extends ConsumerStatefulWidget {
  const AnimatedAlbumArtScroller({super.key});

  @override
  ConsumerState createState() => _AnimatedAlbumArtScrollerState();
}

class _AnimatedAlbumArtScrollerState
    extends ConsumerState<AnimatedAlbumArtScroller> {
  ImageProvider _albumArtImage = const AssetImage(
    Assets.defaultAlbumCoverImage,
  );
  bool _isEmptyState = false;

  void _setPreviewAlbumArt() {
    final albumDetails = ref
        .read(albumDetailsProvider)
        .where((album) => album.albumArtPath != null)
        .toList();
    if (albumDetails.isEmpty) {
      setState(() {
        _isEmptyState = true;
      });
      return;
    }

    final previewAlbum = albumDetails.first;
    setState(() {
      _isEmptyState = false;
      _albumArtImage = previewAlbum.isOnDevice()
          ? FileImage(File(previewAlbum.albumArtPath!))
          : NetworkImage(previewAlbum.albumArtPath!);
    });
  }

  @override
  void initState() {
    super.initState();
    _setPreviewAlbumArt();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEmptyState) {
      return EmptyStateWidget(
        emptyDescription: context.localization.noMusicFilesFound,
      );
    }

    return RepaintBoundary(
      key: const ValueKey(SplitScreenType.albumArt),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              context.appDeviceScreenBackgroundColor.withValues(alpha: 0.96),
              const Color(0xFF101215).withValues(alpha: 0.92),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LiquidGlass(
                borderRadius: BorderRadius.circular(18),
                blur: 10,
                opacity: 0.18,
                borderColor: CupertinoColors.white.withValues(alpha: 0.28),
                padding: const EdgeInsets.all(8),
                shadows: [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: 0.34),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CupertinoColors.black.withValues(alpha: 0.18),
                    ),
                    child: Image(
                      key: ValueKey(_albumArtImage),
                      image: _albumArtImage,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      errorBuilder: (_, _, _) => Image.asset(
                        Assets.defaultAlbumCoverImage,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
