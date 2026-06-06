import 'dart:math' as math;

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/services/music_metadata_lookup_service.dart';
import 'package:classipod/features/music/songs/models/music_metadata_match.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<MusicMetadataMatch?> showMetadataMatchSheet(
  BuildContext context,
  MusicMetadata metadata,
) {
  return showCupertinoModalPopup<MusicMetadataMatch>(
    context: context,
    builder: (_) => MetadataMatchSheet(metadata: metadata),
  );
}

class MetadataMatchSheet extends ConsumerStatefulWidget {
  final MusicMetadata metadata;

  const MetadataMatchSheet({super.key, required this.metadata});

  @override
  ConsumerState<MetadataMatchSheet> createState() => _MetadataMatchSheetState();
}

class _MetadataMatchSheetState extends ConsumerState<MetadataMatchSheet> {
  late final TextEditingController _queryController;
  MusicMetadataSource _source = MusicMetadataSource.appleMusic;
  List<MusicMetadataMatch> _matches = [];
  bool _isSearching = false;
  AppleMusicAuthorizationStatus? _appleMusicStatus;
  String? _errorText;
  int _searchSerial = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: _initialQuery());
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  String _initialQuery() {
    final parts = [
      widget.metadata.trackName,
      widget.metadata.getTrackArtistNames,
    ]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && !value.startsWith('Unknown'))
        .toList(growable: false);
    return parts.join(' ');
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      return;
    }

    final source = _source;
    final requestId = ++_searchSerial;
    setState(() {
      _isSearching = true;
      _matches = [];
      _errorText = null;
    });

    try {
      final lookupService = ref.read(musicMetadataLookupServiceProvider);
      if (source == MusicMetadataSource.appleMusic) {
        final status = await lookupService.requestAppleMusicAuthorization();
        if (!mounted || requestId != _searchSerial) {
          return;
        }
        _appleMusicStatus = status;
        if (status != AppleMusicAuthorizationStatus.unsupported &&
            !status.canSearchCatalog) {
          setState(() {
            _matches = [];
            _errorText = status.message;
            _isSearching = false;
          });
          return;
        }
      }

      final matches = await lookupService.search(
            source: source,
            query: query,
          );
      if (!mounted || requestId != _searchSerial) {
        return;
      }
      setState(() {
        _matches = matches;
        _errorText = matches.isEmpty
            ? _emptyMessageForSource(source)
            : null;
      });
    } catch (error) {
      if (!mounted || requestId != _searchSerial) {
        return;
      }
      setState(() {
        _matches = [];
        _errorText = '${source.label} lookup failed. Try another source.';
      });
    } finally {
      if (mounted && requestId == _searchSerial) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  String _emptyMessageForSource(MusicMetadataSource source) {
    if (source == MusicMetadataSource.appleMusic &&
        _appleMusicStatus == AppleMusicAuthorizationStatus.unsupported) {
      return 'No Apple Music catalog matches found. iTunes fallback also returned no results.';
    }
    return 'No ${source.label} matches found for this search.';
  }

  void _changeSource(MusicMetadataSource? source) {
    if (source == null || source == _source) {
      return;
    }
    setState(() {
      _source = source;
      _matches = [];
      _errorText = null;
    });
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * 0.86, 620.0);
    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Match Metadata',
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .navLargeTitleTextStyle
                            .copyWith(fontSize: 24),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CupertinoSlidingSegmentedControl<MusicMetadataSource>(
                  groupValue: _source,
                  onValueChanged: _changeSource,
                  children: {
                    for (final source in MusicMetadataSource.values)
                      source: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          source.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  },
                ),
                const SizedBox(height: 12),
                CupertinoSearchTextField(
                  controller: _queryController,
                  placeholder: 'Song, artist, or album',
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 10),
                CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onPressed: _isSearching ? null : _search,
                  child: _isSearching
                      ? const CupertinoActivityIndicator()
                      : const Text('Search'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _buildResults(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_isSearching && _matches.isEmpty) {
      return const Center(
        key: ValueKey('metadata-searching'),
        child: CupertinoActivityIndicator(radius: 16),
      );
    }

    if (_errorText != null && _matches.isEmpty) {
      return Center(
        key: const ValueKey('metadata-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorText!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.appSecondaryTextColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      key: ValueKey('metadata-${_source.name}-${_matches.length}'),
      itemCount: _matches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final match = _matches[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.96, end: 1),
          duration: Duration(milliseconds: 150 + index * 24),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: _MetadataMatchTile(
            match: match,
            onTap: () => Navigator.of(context).pop(match),
          ),
        );
      },
    );
  }
}

class _MetadataMatchTile extends StatelessWidget {
  final MusicMetadataMatch match;
  final VoidCallback onTap;

  const _MetadataMatchTile({required this.match, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6.resolveFrom(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: CupertinoColors.separator.resolveFrom(context),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _ArtworkImage(url: match.artworkUrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.title.isEmpty ? 'Untitled' : match.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      match.subtitle.isEmpty ? match.source.label : match.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appSecondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        match.source.label,
                        if (match.releaseDate != null)
                          match.releaseDate!.year.toString(),
                        if (match.trackNumber != null)
                          'Track ${match.trackNumber}',
                        if (match.catalogUrl != null) 'Catalog',
                      ].join(' / '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appSecondaryTextColor.withValues(
                          alpha: 0.72,
                        ),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(CupertinoIcons.chevron_forward, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtworkImage extends StatelessWidget {
  final String? url;

  const _ArtworkImage({this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const SizedBox(
        height: 58,
        width: 58,
        child: ColoredBox(
          color: CupertinoColors.systemGrey4,
          child: Icon(CupertinoIcons.music_note_2),
        ),
      );
    }

    return Image.network(
      url!,
      height: 58,
      width: 58,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const SizedBox(
        height: 58,
        width: 58,
        child: ColoredBox(
          color: CupertinoColors.systemGrey4,
          child: Icon(CupertinoIcons.music_note_2),
        ),
      ),
    );
  }
}
