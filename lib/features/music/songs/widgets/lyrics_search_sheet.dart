import 'dart:math' as math;

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/services/lyrics_lookup_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<String?> showLyricsSearchSheet(
  BuildContext context,
  MusicMetadata metadata,
) {
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (_) => LyricsSearchSheet(metadata: metadata),
  );
}

class LyricsSearchSheet extends ConsumerStatefulWidget {
  final MusicMetadata metadata;

  const LyricsSearchSheet({super.key, required this.metadata});

  @override
  ConsumerState<LyricsSearchSheet> createState() => _LyricsSearchSheetState();
}

class _LyricsSearchSheetState extends ConsumerState<LyricsSearchSheet> {
  late final TextEditingController _queryController;
  List<LyricsSearchResult> _results = [];
  bool _isSearching = false;
  String? _errorText;

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
    if (query.isEmpty || _isSearching) {
      return;
    }

    setState(() {
      _isSearching = true;
      _errorText = null;
    });

    try {
      final results = await ref.read(lyricsLookupServiceProvider).search(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        _errorText = results.isEmpty ? 'No LRCLIB lyrics found.' : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = [];
        _errorText = 'Lyrics lookup failed. Try another search.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _autoMatch() async {
    setState(() {
      _isSearching = true;
      _errorText = null;
    });

    try {
      final lyrics = await ref
          .read(lyricsLookupServiceProvider)
          .findBestFor(widget.metadata);
      if (!mounted) {
        return;
      }
      if (lyrics == null || lyrics.trim().isEmpty) {
        setState(() {
          _errorText = 'No exact LRCLIB lyric match found.';
        });
        return;
      }
      Navigator.of(context).pop(lyrics);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = 'Exact lyrics lookup failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * 0.82, 580.0);
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
                        'Find Lyrics',
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
                CupertinoSearchTextField(
                  controller: _queryController,
                  placeholder: 'Song and artist',
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        onPressed: _isSearching ? null : _search,
                        child: _isSearching
                            ? const CupertinoActivityIndicator()
                            : const Text('Search'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        onPressed: _isSearching ? null : _autoMatch,
                        child: const Text('Exact Match'),
                      ),
                    ),
                  ],
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
    if (_isSearching && _results.isEmpty) {
      return const Center(
        key: ValueKey('lyrics-searching'),
        child: CupertinoActivityIndicator(radius: 16),
      );
    }

    if (_errorText != null && _results.isEmpty) {
      return Center(
        key: const ValueKey('lyrics-empty'),
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
      key: ValueKey('lyrics-${_results.length}'),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final result = _results[index];
        return _LyricsResultTile(
          result: result,
          onTap: () => Navigator.of(context).pop(result.bestLyrics),
        );
      },
    );
  }
}

class _LyricsResultTile extends StatelessWidget {
  final LyricsSearchResult result;
  final VoidCallback onTap;

  const _LyricsResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasSyncedLyrics = result.syncedLyrics?.trim().isNotEmpty ?? false;
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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                hasSyncedLyrics
                    ? CupertinoIcons.waveform
                    : CupertinoIcons.text_quote,
                color: CupertinoTheme.of(context).primaryColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.trackName,
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
                      result.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appSecondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasSyncedLyrics ? 'Synced lyrics' : 'Plain lyrics',
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
              const Icon(CupertinoIcons.chevron_forward, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
