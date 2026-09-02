import 'dart:io';

import 'package:dopi/core/constants/assets.dart';
import 'package:dopi/core/constants/constants.dart';
import 'package:dopi/core/extensions/build_context_extensions.dart';
import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/utils/metadata_artwork.dart';
import 'package:dopi/core/services/music_metadata_lookup_service.dart';
import 'package:dopi/features/music/songs/models/music_metadata_match.dart';
import 'package:dopi/features/music/songs/widgets/lyrics_search_sheet.dart';
import 'package:dopi/features/music/songs/widgets/metadata_match_sheet.dart';
import 'package:dopi/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dopi/features/status_bar/widgets/status_bar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class SongEditScreen extends ConsumerStatefulWidget {
  final MusicMetadata songMetadata;

  const SongEditScreen({super.key, required this.songMetadata});

  @override
  ConsumerState<SongEditScreen> createState() => _SongEditScreenState();
}

class _SongEditScreenState extends ConsumerState<SongEditScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;
  late final TextEditingController _trackNumberController;
  late final TextEditingController _discNumberController;
  late final TextEditingController _lyricsController;

  late final String _initialTitle;
  late final String _initialArtists;
  late final String _initialAlbum;
  late final String _initialGenre;
  late final String _initialYear;
  late final String _initialTrackNumber;
  late final String _initialDiscNumber;
  late final String _initialLyrics;

  String? _pendingThumbnailPath;
  int? _pendingAlbumLength;
  int? _pendingTrackDuration;
  bool _isSaving = false;
  bool _isApplyingLookup = false;
  late bool _isExplicit;

  @override
  void initState() {
    super.initState();
    final metadata = widget.songMetadata;
    _initialTitle = metadata.trackName ?? '';
    _initialArtists = (metadata.trackArtistNames ?? []).join(', ');
    _initialAlbum = metadata.albumName ?? '';
    _initialGenre = metadata.genres.join(', ');
    _initialYear = metadata.year?.toString() ?? '';
    _initialTrackNumber = metadata.trackNumber?.toString() ?? '';
    _initialDiscNumber = metadata.discNumber?.toString() ?? '';
    _initialLyrics = metadata.lyrics ?? '';
    _isExplicit = metadata.isExplicit;

    _titleController = TextEditingController(text: _initialTitle);
    _artistController = TextEditingController(text: _initialArtists);
    _albumController = TextEditingController(text: _initialAlbum);
    _genreController = TextEditingController(text: _initialGenre);
    _yearController = TextEditingController(text: _initialYear);
    _trackNumberController = TextEditingController(text: _initialTrackNumber);
    _discNumberController = TextEditingController(text: _initialDiscNumber);
    _lyricsController = TextEditingController(text: _initialLyrics);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _trackNumberController.dispose();
    _discNumberController.dispose();
    _lyricsController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });

    final titleInput = _titleController.text.trim();
    final albumInput = _albumController.text.trim();
    final genreInput = _genreController.text.trim();
    final lyricsInput = _lyricsController.text.trim();
    final artistInput = _artistController.text.trim();
    final yearInput = _yearController.text.trim();
    final trackNumberInput = _trackNumberController.text.trim();
    final discNumberInput = _discNumberController.text.trim();

    final artistNames = _splitInput(artistInput);

    final updatedMetadata = MusicMetadata(
      trackName: _nonEmpty(titleInput),
      trackArtistNames: artistNames.isEmpty ? null : artistNames,
      albumName: _nonEmpty(albumInput),
      albumArtistName: artistNames.isEmpty ? null : artistNames.first,
      trackNumber: _parseInteger(trackNumberInput),
      albumLength: _pendingAlbumLength ?? widget.songMetadata.albumLength,
      year: _parseInteger(yearInput),
      genres: _splitInput(genreInput),
      discNumber: _parseInteger(discNumberInput),
      mimeType: widget.songMetadata.mimeType,
      trackDuration: _pendingTrackDuration ?? widget.songMetadata.trackDuration,
      bitrate: widget.songMetadata.bitrate,
      filePath: widget.songMetadata.filePath,
      thumbnailPath: _pendingThumbnailPath ?? widget.songMetadata.thumbnailPath,
      originalSongIndex: widget.songMetadata.originalSongIndex,
      isOnDevice: widget.songMetadata.isOnDevice,
      rating: widget.songMetadata.rating,
      isExplicit: _isExplicit,
      lyrics: _nonEmpty(lyricsInput),
    );

    await ref
        .read(nowPlayingDetailsProvider.notifier)
        .updateMetadata(updatedMetadata);

    if (mounted) {
      Navigator.of(context).pop(updatedMetadata);
    }
  }

  Future<void> _showMetadataSearch() async {
    final match = await showMetadataMatchSheet(context, _draftMetadata());
    if (match == null) {
      return;
    }
    await _applyMetadataMatch(match);
  }

  Future<void> _applyMetadataMatch(MusicMetadataMatch match) async {
    setState(() {
      _isApplyingLookup = true;
    });

    String? thumbnailPath;
    try {
      thumbnailPath = await ref
          .read(musicMetadataLookupServiceProvider)
          .cacheArtworkForMatch(match, widget.songMetadata);
    } catch (_) {
      thumbnailPath = null;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      if (match.title.trim().isNotEmpty) {
        _titleController.text = match.title;
      }
      if (match.artist.trim().isNotEmpty) {
        _artistController.text = match.artist;
      }
      if (match.album.trim().isNotEmpty) {
        _albumController.text = match.album;
      }
      if (match.genres.isNotEmpty) {
        _genreController.text = match.genres.join(', ');
      }
      if (match.releaseDate != null) {
        _yearController.text = match.releaseDate!.year.toString();
      }
      if (match.trackNumber != null) {
        _trackNumberController.text = match.trackNumber.toString();
      }
      if (match.discNumber != null) {
        _discNumberController.text = match.discNumber.toString();
      }
      _pendingThumbnailPath = thumbnailPath ?? _pendingThumbnailPath;
      _pendingAlbumLength = match.trackCount ?? _pendingAlbumLength;
      _pendingTrackDuration = match.durationMs ?? _pendingTrackDuration;
      _isExplicit = match.isExplicit;
      _isApplyingLookup = false;
    });
  }

  Future<void> _showLyricsSearch() async {
    final selection = await showLyricsSearchSheet(context, _draftMetadata());
    if (selection == null || !mounted) {
      return;
    }
    setState(() {
      _lyricsController.text = selection.lyrics;
      if (selection.isExplicit) {
        _isExplicit = true;
      }
    });
  }

  Future<void> _pickArtwork() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.image,
      withData: false,
      allowCompression: false,
    );
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      return;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final artworkDirectory = Directory(
      '${documentsDirectory.path}/${Constants.appDocumentsFolderName}/${Constants.artworkDirectoryName}',
    );
    await artworkDirectory.create(recursive: true);

    final extension = _imageExtension(sourcePath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destination = File(
      '${artworkDirectory.path}/manual_'
      '${widget.songMetadata.originalSongIndex}_$timestamp.$extension',
    );
    await File(sourcePath).copy(destination.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingThumbnailPath = destination.path;
    });
  }

  MusicMetadata _draftMetadata() {
    final artists = _splitInput(_artistController.text.trim());
    return widget.songMetadata.copyWith(
      trackName: _nonEmpty(_titleController.text) ?? widget.songMetadata.trackName,
      trackArtistNames: artists.isEmpty ? widget.songMetadata.trackArtistNames : artists,
      albumName: _nonEmpty(_albumController.text) ?? widget.songMetadata.albumName,
      genres: _splitInput(_genreController.text.trim()),
      thumbnailPath: _pendingThumbnailPath,
      year: _parseInteger(_yearController.text.trim()),
      trackNumber: _parseInteger(_trackNumberController.text.trim()),
      discNumber: _parseInteger(_discNumberController.text.trim()),
      isExplicit: _isExplicit,
      lyrics: _nonEmpty(_lyricsController.text) ?? widget.songMetadata.lyrics,
    );
  }

  List<String> _splitInput(String value) {
    if (value.isEmpty) {
      return [];
    }
    return value
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  int? _parseInteger(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    return int.tryParse(value.trim());
  }

  String? _nonEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _imageExtension(String path) {
    final extension = path.split('.').last.toLowerCase();
    if (extension == 'png' || extension == 'jpg' || extension == 'jpeg') {
      return extension;
    }
    return 'jpg';
  }

  @override
  Widget build(BuildContext context) {
    final thumbnailPath = _pendingThumbnailPath ?? widget.songMetadata.thumbnailPath;
    return SafeArea(
      child: CupertinoPageScaffold(
        child: Column(
          children: [
            StatusBar(title: context.localization.editSongScreenTitle),
            Expanded(
              child: CupertinoScrollbar(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ArtworkEditor(
                      thumbnailPath: thumbnailPath,
                      isApplyingLookup: _isApplyingLookup,
                      onPickArtwork: _pickArtwork,
                    ),
                    const SizedBox(height: 12),
                    _LookupActions(
                      isApplyingLookup: _isApplyingLookup,
                      onSearchMetadata: _showMetadataSearch,
                      onFindLyrics: _showLyricsSearch,
                    ),
                    const SizedBox(height: 18),
                    _SongEditField(
                      label: context.localization.editSongNameLabel,
                      controller: _titleController,
                    ),
                    _SongEditField(
                      label: context.localization.editSongArtistLabel,
                      controller: _artistController,
                    ),
                    _SongEditField(
                      label: context.localization.editSongAlbumLabel,
                      controller: _albumController,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _SongEditField(
                            label: 'Year',
                            controller: _yearController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SongEditField(
                            label: 'Track',
                            controller: _trackNumberController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SongEditField(
                            label: 'Disc',
                            controller: _discNumberController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    _SongEditField(
                      label: context.localization.editSongGenreLabel,
                      controller: _genreController,
                    ),
                    _ExplicitToggle(
                      isExplicit: _isExplicit,
                      onChanged: (value) {
                        setState(() {
                          _isExplicit = value;
                        });
                      },
                    ),
                    _SongEditField(
                      label: context.localization.editSongLyricsLabel,
                      controller: _lyricsController,
                      maxLines: 6,
                    ),
                    const SizedBox(height: 24),
                    CupertinoButton.filled(
                      onPressed: _isSaving || _isApplyingLookup
                          ? null
                          : _saveChanges,
                      child: _isSaving
                          ? const CupertinoActivityIndicator()
                          : Text(context.localization.saveChangesButton),
                    ),
                    const SizedBox(height: 12),
                    CupertinoButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(context.localization.cancelText),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkEditor extends StatelessWidget {
  final String? thumbnailPath;
  final bool isApplyingLookup;
  final VoidCallback onPickArtwork;

  const _ArtworkEditor({
    required this.thumbnailPath,
    required this.isApplyingLookup,
    required this.onPickArtwork,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.resolveFrom(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CupertinoColors.separator.resolveFrom(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: _ArtworkPreview(
                  key: ValueKey(thumbnailPath),
                  thumbnailPath: thumbnailPath,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Artwork',
                    style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use matched art or pick a local cover image.',
                    style: TextStyle(
                      color: context.appSecondaryTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: isApplyingLookup ? null : onPickArtwork,
                    child: const Text('Pick Artwork'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkPreview extends StatelessWidget {
  final String? thumbnailPath;

  const _ArtworkPreview({super.key, this.thumbnailPath});

  @override
  Widget build(BuildContext context) {
    return Image(
      image: _imageProvider(),
      height: 86,
      width: 86,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Image.asset(
        Assets.defaultAlbumCoverImage,
        height: 86,
        width: 86,
        fit: BoxFit.cover,
      ),
    );
  }

  ImageProvider<Object> _imageProvider() {
    return metadataArtworkProvider(thumbnailPath);
  }
}

class _LookupActions extends StatelessWidget {
  final bool isApplyingLookup;
  final VoidCallback onSearchMetadata;
  final VoidCallback onFindLyrics;

  const _LookupActions({
    required this.isApplyingLookup,
    required this.onSearchMetadata,
    required this.onFindLyrics,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(vertical: 11),
            onPressed: isApplyingLookup ? null : onSearchMetadata,
            child: isApplyingLookup
                ? const CupertinoActivityIndicator()
                : const Text('Search Metadata'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 11),
            onPressed: isApplyingLookup ? null : onFindLyrics,
            child: const Text('Find Lyrics'),
          ),
        ),
      ],
    );
  }
}


class _ExplicitToggle extends StatelessWidget {
  final bool isExplicit;
  final ValueChanged<bool> onChanged;

  const _ExplicitToggle({
    required this.isExplicit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6.resolveFrom(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: CupertinoColors.separator.resolveFrom(context),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                height: 22,
                width: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isExplicit
                      ? CupertinoColors.systemRed.resolveFrom(context)
                      : CupertinoColors.systemGrey3.resolveFrom(context),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'E',
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        color: CupertinoColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explicit',
                      style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Show the E badge for this song.',
                      style: TextStyle(
                        color: context.appSecondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoSwitch(
                value: isExplicit,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongEditField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;

  const _SongEditField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            minLines: maxLines,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 16,
                ),
          ),
        ],
      ),
    );
  }
}
