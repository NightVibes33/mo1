import 'dart:async';
import 'dart:io';

import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/services/audio_files_service.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/services/music_metadata_lookup_service.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/music/songs/models/music_metadata_match.dart';
import 'package:classipod/features/status_bar/widgets/status_bar.dart';
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
  final List<MusicMetadataMatch> _matches = [];
  bool _isSearching = false;
  bool _isLibraryMode = false;
  String _searchQuery = '';
  String? _searchErrorText;
  String? _libraryStatusText;

  @override
  int get extraDisplayItems => 2;

  @override
  double get displayTileHeight => 54;

  @override
  String get routeName => Routes.appleMusic.name;

  @override
  List<MusicMetadataMatch> get displayItems => _matches;

  @override
  Future<void> onSelectPressed() => _onAppleMusicResultAction(
        selectedDisplayItem,
      );

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
    unawaited(_searchAppleMusic(cleanQuery));
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

  Future<void> _searchAppleMusic(String query) async {
    if (_isSearching) {
      return;
    }

    setState(() {
      _isSearching = true;
      _searchErrorText = null;
      selectedDisplayItem = 0;
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

    final matches = await lookupService.search(
      source: MusicMetadataSource.appleMusic,
      query: query,
      limit: 25,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _isSearching = false;
      _matches
        ..clear()
        ..addAll(matches);
      _isLibraryMode = false;
      _searchErrorText = matches.isEmpty ? 'No Apple Music results.' : null;
      selectedDisplayItem = matches.isEmpty ? 0 : extraDisplayItems;
    });
  }

  Future<void> _loadAppleMusicLibrary() async {
    if (_isSearching) {
      return;
    }

    setState(() {
      _isSearching = true;
      _searchErrorText = null;
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
        _libraryStatusText = 'Apple Music library import is only available on iOS.';
      });
      return;
    }

    final subscriptionStatus = await lookupService.appleMusicSubscriptionStatus();
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
    ref.invalidate(filteredAudioFilesProvider);

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
      _isLibraryMode = true;
      _matches
        ..clear()
        ..addAll(matches);
      _libraryStatusText = matches.isEmpty
          ? playbackStatusText ?? 'No Apple Music library songs.'
          : playbackStatusText ?? importStatusText;
      selectedDisplayItem = matches.isEmpty ? 1 : extraDisplayItems;
    });
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
                itemCount: _matches.length + extraDisplayItems,
                prototypeItem: const SizedBox(height: 54),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _AppleMusicListTile(
                      title: _searchQuery.trim().isEmpty
                          ? 'Search Apple Music'
                          : 'Search "${_searchQuery.trim()}"',
                      description: _searchErrorText ??
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
                      description: _libraryStatusText ??
                          (_isSearching && selectedDisplayItem == 1
                              ? 'Loading saved songs'
                              : 'Saved Apple Music songs'),
                      isSelected: selectedDisplayItem == 1,
                      isLoading: _isSearching && selectedDisplayItem == 1,
                      onTap: () => unawaited(_loadAppleMusicLibrary()),
                    );
                  }

                  final match = _matches[index - extraDisplayItems];
                  return _AppleMusicListTile(
                    title: match.title.isEmpty ? 'Unknown Song' : match.title,
                    description: match.subtitle.isEmpty
                        ? match.source.label
                        : match.subtitle,
                    artworkUrl: match.artworkUrl,
                    isSelected: selectedDisplayItem == index,
                    onTap: () async => _onAppleMusicResultAction(index),
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
  final VoidCallback onTap;

  const _AppleMusicListTile({
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
    this.artworkUrl,
    this.isLoading = false,
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
              if (isSelected)
                Icon(
                  CupertinoIcons.right_chevron,
                  color: context.appInverseTextColor,
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
