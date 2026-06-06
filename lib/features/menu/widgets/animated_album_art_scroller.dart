import 'dart:async';

import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/utils/metadata_artwork.dart';
import 'package:classipod/core/widgets/empty_state_widget.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/features/menu/models/split_screen_type.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnimatedAlbumArtScroller extends ConsumerStatefulWidget {
  const AnimatedAlbumArtScroller({super.key});

  @override
  ConsumerState createState() => _AnimatedAlbumArtScrollerState();
}

class _AnimatedAlbumArtScrollerState
    extends ConsumerState<AnimatedAlbumArtScroller> {
  Timer? _rotationTimer;
  int _artworkIndex = 0;
  String _artworkSignature = '';

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  void _syncArtworkRotation(List<String> artworkPaths) {
    final signature = artworkPaths.join('\u0001');
    if (_artworkSignature == signature) {
      return;
    }

    _artworkSignature = signature;
    _artworkIndex = 0;
    _rotationTimer?.cancel();
    _rotationTimer = null;

    if (artworkPaths.length <= 1) {
      return;
    }

    _rotationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _artworkIndex = (_artworkIndex + 1) % artworkPaths.length;
      });
    });
  }

  List<String> _artworkPathsFrom(Iterable<MusicMetadata> metadataList) {
    final seenPaths = <String>{};
    final artworkPaths = <String>[];
    for (final metadata in metadataList) {
      final path = metadata.thumbnailPath?.trim();
      if (path == null || path.isEmpty || !seenPaths.add(path)) {
        continue;
      }
      artworkPaths.add(path);
    }
    return artworkPaths;
  }

  @override
  Widget build(BuildContext context) {
    final metadataState = ref.watch(filteredAudioFilesProvider);

    return metadataState.when(
      data: (metadataList) {
        final artworkPaths = _artworkPathsFrom(metadataList);
        _syncArtworkRotation(artworkPaths);

        if (metadataList.isEmpty) {
          return EmptyStateWidget(
            emptyDescription: context.localization.noMusicFilesFound,
          );
        }

        final artworkPath = artworkPaths.isEmpty
            ? null
            : artworkPaths[_artworkIndex % artworkPaths.length];
        return _AlbumArtPreview(artworkPath: artworkPath);
      },
      loading: () => const _AlbumArtPreview(artworkPath: null),
      error: (_, _) => EmptyStateWidget(
        emptyDescription: context.localization.noMusicFilesFound,
      ),
    );
  }
}

class _AlbumArtPreview extends StatelessWidget {
  final String? artworkPath;

  const _AlbumArtPreview({required this.artworkPath});

  @override
  Widget build(BuildContext context) {
    final image = metadataArtworkProvider(artworkPath);
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
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 520),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: Image(
                        key: ValueKey(artworkPath ?? 'default-album-art'),
                        image: image,
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
      ),
    );
  }
}
