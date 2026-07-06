import 'dart:async';
import 'dart:io';

import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/constants/assets.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/audio_files_service.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/core/services/imported_library_refresh_service.dart';
import 'package:dope/core/services/music_metadata_lookup_service.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/music/songs/models/music_metadata_match.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppleMusicSearchScreen extends ConsumerStatefulWidget {
  const AppleMusicSearchScreen({super.key});

  @override
  ConsumerState<AppleMusicSearchScreen> createState() =>
      _AppleMusicSearchScreenState();
}

class _AppleMusicSearchScreenState extends ConsumerState<AppleMusicSearchScreen>
    with CustomScreen {
  static const int _initialSearchLimit = 100;
  static const int _maxSearchLimit = 300;

  final List<MusicMetadataMatch> _matches = [];
  bool _isSearching = false;
  bool _isLibraryMode = false;
  String _searchQuery = '';
  String? _searchErrorText;
  String? _libraryStatusText;
  String? _statusText;
  AppleMusicSubscriptionStatus _subscriptionStatus =
      const AppleMusicSubscriptionStatus.unsupported();
  int? _addingToLibraryDisplayIndex;
  int _searchLimit = _initialSearchLimit;
  bool _hasMoreSearchResults = false;

  @override
  int get extraDisplayItems => 2;

  @override
  double get displayTileHeight => 54;

  @override
  String get routeName => Routes.appleMusic.name;

  @override
  List<MusicMetadataMatch> get displayItems => _matches;

  int? get _loadMoreDisplayIndex =>
      _hasMoreSearchResults ? _matches.length + extraDisplayItems : null;

  @override
  Future<void> onSelectPressed() =>
      _onAppleMusicResultAction(selectedDisplayItem);

  Future<void> _onAppleMusicResultAction(int displayIndex) async {
    setState(() => selectedDisplayItem = displayIndex);
    if (displayIndex == 0) {
      await _onSearchDefaultTileAction();
      return;
    }
    if (displayIndex == 1) {
      unawaited(_loadAppleMusicLibrary());
      return;
    }
    if (_loadMoreDisplayIndex == displayIndex) {
      unawaited(_loadMoreAppleMusicResults());
      return;
    }

    final matchIndex = displayIndex - extraDisplayItems;
    if (matchIndex < 0 || matchIndex >= _matches.length) {
      return;
    }

    final metadataList = [
      for (var index = 0; index < _matches.length; index++)
        _matches[index].toAppleMusicMetadata(originalSongIndex: -index - 1),
    ];
    final didStart = await ref
        .read(audioPlayerServiceProvider.notifier)
        .playAppleMusicMetadata(
          metadataList[matchIndex],
          metadataList: metadataList,
          currentIndex: matchIndex,
        );

    if (!mounted) {
      return;
    }
    if (!didStart) {
      setState(() {
        if (_isLibraryMode) {
          _libraryStatusText = 'Apple Music playback failed. Check Debug Logs.';
        } else {
          _searchErrorText = 'Apple Music playback failed. Check Debug Logs.';
        }
      });
      return;
    }
    await context.pushNamed(Routes.nowPlaying.name);
  }

  Future<void> _onSearchDefaultTileAction() async {
    final query = await _promptForSearchQuery();
    if (!mounted || query == null) {
      return;
    }

    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() {
        selectedDisplayItem = 0;
        _searchErrorText = 'Enter a song, artist, or album.';
      });
      return;
    }

    setState(() => _searchQuery = cleanQuery);
    unawaited(_searchAppleMusic(cleanQuery, limit: _initialSearchLimit));
  }

  Future<String?> _promptForSearchQuery() async {
    final controller = TextEditingController(text: _searchQuery);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Search Apple Music'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              clearButtonMode: OverlayVisibilityMode.editing,
              placeholder: 'Song, artist, or album',
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _searchAppleMusic(String query, {required int limit}) async {
    if (_isSearching) {
      return;
    }

    final requestedLimit = limit.clamp(1, _maxSearchLimit);
    final isLoadingMore =
        !_isLibraryMode &&
        _matches.isNotEmpty &&
        requestedLimit > _searchLimit &&
        query.trim() == _searchQuery.trim();

    setState(() {
      _isSearching = true;
      _searchErrorText = null;
      _statusText = isLoadingMore
          ? 'Loading more Apple Music results...'
          : null;
      if (!isLoadingMore) {
        _hasMoreSearchResults = false;
        selectedDisplayItem = 0;
      }
    });

    final lookupService = ref.read(musicMetadataLookupServiceProvider);
    final authorizationStatus = await lookupService
        .requestAppleMusicAuthorization();
    if (!mounted) {
      return;
    }
    if (authorizationStatus != AppleMusicAuthorizationStatus.unsupported &&
        !authorizationStatus.canSearchCatalog) {
      setState(() {
        _isSearching = false;
        _matches.clear();
        _searchErrorText = authorizationStatus.message;
      });
      return;
    }

    final subscriptionStatus = await lookupService
        .appleMusicSubscriptionStatus();
    if (!mounted) {
      return;
    }

    final matches = await lookupService.search(
      source: MusicMetadataSource.appleMusic,
      query: query,
      limit: requestedLimit,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _isSearching = false;
      _searchLimit = requestedLimit;
      _subscriptionStatus = subscriptionStatus;
      _matches
        ..clear()
        ..addAll(matches);
      _isLibraryMode = false;
      _hasMoreSearchResults =
          matches.length >= requestedLimit && requestedLimit < _maxSearchLimit;
      _searchErrorText = matches.isEmpty ? 'No Apple Music results.' : null;
      _statusText = matches.isEmpty
          ? null
          : _hasMoreSearchResults
          ? 'Showing ${matches.length} results. Load more for a deeper catalog search.'
          : 'Showing ${matches.length} Apple Music results.';
      selectedDisplayItem = matches.isEmpty ? 0 : extraDisplayItems;
    });
  }

  Future<void> _loadMoreAppleMusicResults() async {
    if (_isSearching || !_hasMoreSearchResults) {
      return;
    }
    final nextLimit = (_searchLimit + _initialSearchLimit).clamp(
      _initialSearchLimit,
      _maxSearchLimit,
    );
    setState(() => selectedDisplayItem = _loadMoreDisplayIndex ?? 0);
    await _searchAppleMusic(_searchQuery, limit: nextLimit);
  }

  Future<void> _loadAppleMusicLibrary() async {
    if (_isSearching) {
      return;
    }

    setState(() {
      _isSearching = true;
      _searchErrorText = null;
      _statusText = null;
      _libraryStatusText = null;
      selectedDisplayItem = 1;
    });

    final lookupService = ref.read(musicMetadataLookupServiceProvider);
    final authorizationStatus = await lookupService
        .requestAppleMusicAuthorization();
    if (!mounted) {
      return;
    }
    if (authorizationStatus != AppleMusicAuthorizationStatus.unsupported &&
        !authorizationStatus.canSearchCatalog) {
      setState(() {
        _isSearching = false;
        _isLibraryMode = true;
        _matches.clear();
        _libraryStatusText = authorizationStatus.message;
      });
      return;
    }
    if (authorizationStatus == AppleMusicAuthorizationStatus.unsupported) {
      setState(() {
        _isSearching = false;
        _isLibraryMode = true;
        _matches.clear();
        _libraryStatusText =
            'Apple Music library import is only available on iOS.';
      });
      return;
    }

    final subscriptionStatus = await lookupService
        .appleMusicSubscriptionStatus();
    if (!mounted) {
      return;
    }
    final matches = await lookupService.appleMusicLibrarySongs();
    if (!mounted) {
      return;
    }

    final metadataToImport = [
      for (var index = 0; index < matches.length; index++)
        matches[index].toAppleMusicMetadata(originalSongIndex: -index - 1),
    ];
    final importResult = await ref
        .read(audioFilesServiceProvider.notifier)
        .importAppleMusicMetadata(metadataToImport);
    if (!mounted) {
      return;
    }
    await refreshImportedLibraryProviders(ref);
    if (!mounted) {
      return;
    }

    final String? playbackStatusText;
    if (subscriptionStatus.isSupported &&
        !subscriptionStatus.canPlayCatalogContent) {
      playbackStatusText = subscriptionStatus.playbackMessage;
    } else {
      playbackStatusText = null;
    }

    final importStatusText = importResult.changedCount > 0
        ? 'Imported ${importResult.importedCount}, refreshed ${importResult.updatedCount}.'
        : 'Apple Music library loaded.';

    setState(() {
      _isSearching = false;
      _subscriptionStatus = subscriptionStatus;
      _isLibraryMode = true;
      _searchLimit = _initialSearchLimit;
      _hasMoreSearchResults = false;
      _matches
        ..clear()
        ..addAll(matches);
      _libraryStatusText = matches.isEmpty
          ? playbackStatusText ?? 'No Apple Music library songs.'
          : playbackStatusText ?? importStatusText;
      selectedDisplayItem = matches.isEmpty ? 1 : extraDisplayItems;
    });
  }

  bool _canAddAppleMusicResult(MusicMetadataMatch match) {
    return !_isLibraryMode &&
        match.source == MusicMetadataSource.appleMusic &&
        _subscriptionStatus.canAddToLibrary &&
        match.id.trim().isNotEmpty;
  }

  Future<void> _addAppleMusicResultToLibrary(int displayIndex) async {
    final matchIndex = displayIndex - extraDisplayItems;
    if (matchIndex < 0 || matchIndex >= _matches.length) {
      return;
    }

    final match = _matches[matchIndex];
    if (!_canAddAppleMusicResult(match)) {
      setState(() {
        _statusText = _subscriptionStatus.canAddToLibrary
            ? 'This result cannot be added to your Apple Music library.'
            : 'Apple Music library add requires an active subscription and cloud library.';
      });
      return;
    }

    setState(() {
      selectedDisplayItem = displayIndex;
      _addingToLibraryDisplayIndex = displayIndex;
      _statusText = null;
    });

    final lookupService = ref.read(musicMetadataLookupServiceProvider);
    final result = await lookupService.addAppleMusicSongToLibrary(match.id);
    if (!mounted) {
      return;
    }

    setState(() {
      _addingToLibraryDisplayIndex = null;
      _statusText = result.message;
    });
  }

  String _resultDescription(MusicMetadataMatch match) {
    final subtitle = match.subtitle.isEmpty
        ? match.source.label
        : match.subtitle;
    if (_canAddAppleMusicResult(match)) {
      return '$subtitle  |  Tap to play or add to library';
    }
    return subtitle;
  }

  @override
  Widget build(BuildContext context) {
    final statusBarTitle = _isSearching
        ? selectedDisplayItem == 1
              ? 'Importing'
              : 'Searching'
        : _matches.isEmpty
        ? Routes.appleMusic.title(context)
        : _isLibraryMode
        ? 'Library ${_matches.length}'
        : 'Apple Music ${_matches.length}';

    return CupertinoPageScaffold(
      resizeToAvoidBottomInset: false,
      child: Column(
        children: [
          StatusBar(title: statusBarTitle),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                padding: listViewPadding,
                itemCount:
                    _matches.length +
                    extraDisplayItems +
                    (_hasMoreSearchResults ? 1 : 0),
                prototypeItem: const SizedBox(height: 54),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _AppleMusicListTile(
                      title: _searchQuery.trim().isEmpty
                          ? 'Search Apple Music'
                          : 'Search "${_searchQuery.trim()}"',
                      description:
                          _statusText ??
                          _searchErrorText ??
                          (_isSearching && selectedDisplayItem == 0
                              ? 'Searching catalog'
                              : 'Catalog search'),
                      isSelected: selectedDisplayItem == 0,
                      isLoading: _isSearching && selectedDisplayItem == 0,
                      onTap: () => unawaited(_onSearchDefaultTileAction()),
                    );
                  }
                  if (index == 1) {
                    return _AppleMusicListTile(
                      title: 'Import Music Library',
                      description:
                          _libraryStatusText ??
                          (_isSearching && selectedDisplayItem == 1
                              ? 'Loading saved songs'
                              : 'Saved Apple Music songs'),
                      isSelected: selectedDisplayItem == 1,
                      isLoading: _isSearching && selectedDisplayItem == 1,
                      onTap: () => unawaited(_loadAppleMusicLibrary()),
                    );
                  }

                  if (_loadMoreDisplayIndex == index) {
                    return _AppleMusicListTile(
                      title: 'Load More Results',
                      description: _isSearching
                          ? 'Expanding Apple Music catalog results'
                          : 'Show up to ${(_searchLimit + _initialSearchLimit).clamp(_initialSearchLimit, _maxSearchLimit)} results',
                      isSelected: selectedDisplayItem == index,
                      isLoading: _isSearching && selectedDisplayItem == index,
                      onTap: () => unawaited(_loadMoreAppleMusicResults()),
                    );
                  }

                  final match = _matches[index - extraDisplayItems];
                  return _AppleMusicListTile(
                    title: match.title.isEmpty ? 'Unknown Song' : match.title,
                    description: _resultDescription(match),
                    artworkUrl: match.artworkUrl,
                    isSelected: selectedDisplayItem == index,
                    isAddLoading: _addingToLibraryDisplayIndex == index,
                    onTap: () => unawaited(_onAppleMusicResultAction(index)),
                    onAddToLibrary: _canAddAppleMusicResult(match)
                        ? () => unawaited(_addAppleMusicResultToLibrary(index))
                        : null,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppleMusicListTile extends StatelessWidget {
  final String title;
  final String description;
  final String? artworkUrl;
  final bool isSelected;
  final bool isLoading;
  final bool isAddLoading;
  final VoidCallback onTap;
  final VoidCallback? onAddToLibrary;

  const _AppleMusicListTile({
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
    this.artworkUrl,
    this.isLoading = false,
    this.isAddLoading = false,
    this.onAddToLibrary,
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

    final canAddToLibrary = onAddToLibrary != null;
    final trailingColor = isSelected
        ? context.appInverseTextColor
        : context.appPrimaryTextColor;

    return GestureDetector(
      onTap: onTap,
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
          child: Row(
            children: [
              _AppleMusicArtwork(artworkUrl: artworkUrl, isLoading: isLoading),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CupertinoTheme.of(context).textTheme.textStyle
                          .copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? context.appInverseTextColor
                                : context.appPrimaryTextColor,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: CupertinoTheme.of(context).textTheme.textStyle
                          .copyWith(
                            color: isSelected
                                ? context.appInverseTextColor
                                : context.appSecondaryTextColor,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (canAddToLibrary)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minSize: 0,
                  onPressed: isAddLoading ? null : onAddToLibrary,
                  child: isAddLoading
                      ? const CupertinoActivityIndicator(radius: 9)
                      : Icon(
                          CupertinoIcons.add_circled_solid,
                          size: 26,
                          color: trailingColor,
                        ),
                ),
              if (!canAddToLibrary && isSelected)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    CupertinoIcons.right_chevron,
                    color: trailingColor,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleMusicArtwork extends StatelessWidget {
  final String? artworkUrl;
  final bool isLoading;

  const _AppleMusicArtwork({this.artworkUrl, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final url = artworkUrl;
    if (isLoading) {
      return const SizedBox(
        height: 54,
        width: 54,
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (url == null || url.isEmpty) {
      return Image.asset(
        Assets.defaultAlbumCoverImage,
        fit: BoxFit.cover,
        height: 54,
        width: 54,
      );
    }
    final file = File(url);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        height: 54,
        width: 54,
        errorBuilder: (_, __, ___) => Image.asset(
          Assets.defaultAlbumCoverImage,
          fit: BoxFit.cover,
          height: 54,
          width: 54,
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      height: 54,
      width: 54,
      errorBuilder: (_, __, ___) => Image.asset(
        Assets.defaultAlbumCoverImage,
        fit: BoxFit.cover,
        height: 54,
        width: 54,
      ),
    );
  }
}
