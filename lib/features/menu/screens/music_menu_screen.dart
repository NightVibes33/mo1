import 'dart:async';

import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/audio_files_service.dart';
import 'package:dope/core/services/imported_library_refresh_service.dart';
import 'package:dope/core/widgets/display_list_tile.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _MusicListDisplayItems {
  coverFlow,
  appleMusic,
  navidrome,
  jellyfin,
  importSongs,
  playlists,
  artists,
  albums,
  songs,
  genres,
  search;

  String title(BuildContext context) {
    switch (this) {
      case coverFlow:
        return context.localization.coverFlowScreenTitle;
      case appleMusic:
        return 'Apple Music';
      case navidrome:
        return 'Navidrome';
      case jellyfin:
        return 'Jellyfin';
      case importSongs:
        return '+ MP3 Import';
      case playlists:
        return context.localization.playlistsScreenTitle;
      case artists:
        return context.localization.artistsScreenTitle;
      case albums:
        return context.localization.albumsScreenTitle;
      case songs:
        return context.localization.songsScreenTitle;
      case genres:
        return context.localization.genresScreenTitle;
      case search:
        return context.localization.searchScreenTitle;
    }
  }
}

class MusicMenuScreen extends ConsumerStatefulWidget {
  const MusicMenuScreen({super.key});

  @override
  ConsumerState createState() => _MusicMenuScreenState();
}

class _MusicMenuScreenState extends ConsumerState<MusicMenuScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.musicMenu.name;

  @override
  List<_MusicListDisplayItems> get displayItems =>
      _MusicListDisplayItems.values;

  @override
  Future<void> onSelectPressed() =>
      _navigateToScreen(_MusicListDisplayItems.values[selectedDisplayItem]);

  Future<void> _navigateToScreen(
    _MusicListDisplayItems musicDisplayItem,
  ) async {
    setState(
      () => selectedDisplayItem = displayItems.indexOf(musicDisplayItem),
    );
    switch (musicDisplayItem) {
      case _MusicListDisplayItems.coverFlow:
        unawaited(ref.read(splitScreenViewControllerProvider).closeSplitView());
        await context.pushNamed(
          Routes.coverFlow.name,
          extra: Routes.musicMenu.name,
        );
        unawaited(ref.read(splitScreenViewControllerProvider).openSplitView());
        break;
      case _MusicListDisplayItems.appleMusic:
        await context.pushNamed(Routes.appleMusic.name);
        break;
      case _MusicListDisplayItems.navidrome:
        await context.pushNamed(Routes.navidrome.name);
        break;
      case _MusicListDisplayItems.jellyfin:
        await context.pushNamed(Routes.jellyfin.name);
        break;
      case _MusicListDisplayItems.importSongs:
        final importFuture = ref
            .read(audioFilesServiceProvider.notifier)
            .importLocalAudioFiles();
        unawaited(_showImportProgressUntil(importFuture));
        final importResult = await importFuture;
        if (mounted) {
          await _showImportResult(importResult);
        }
        if (importResult.hasImportedSongs && mounted) {
          await refreshImportedLibraryProviders(ref);
        }
        break;
      case _MusicListDisplayItems.playlists:
        context.goNamed(Routes.playlists.name);
        break;
      case _MusicListDisplayItems.artists:
        context.goNamed(Routes.artists.name);
        break;
      case _MusicListDisplayItems.albums:
        context.goNamed(Routes.albums.name);
        break;
      case _MusicListDisplayItems.songs:
        context.goNamed(Routes.songs.name);
        break;
      case _MusicListDisplayItems.genres:
        context.goNamed(Routes.genres.name);
        break;
      case _MusicListDisplayItems.search:
        context.goNamed(Routes.search.name);
        break;
    }
  }

  Future<void> _showImportProgressUntil(
    Future<ImportLocalAudioResult> importFuture,
  ) async {
    var completed = false;
    var dialogShown = false;
    var closed = false;
    unawaited(
      importFuture.whenComplete(() {
        completed = true;
        if (!mounted || !dialogShown || closed) {
          return;
        }
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
      }),
    );
    while (mounted &&
        !completed &&
        ref.read(localAudioImportProgressProvider) == null) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted ||
        completed ||
        ref.read(localAudioImportProgressProvider) == null) {
      return;
    }
    dialogShown = true;
    await showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ImportProgressDialog(),
    ).whenComplete(() => closed = true);
  }

  Future<void> _showImportResult(ImportLocalAudioResult result) async {
    if (!mounted || !result.hasActivity) {
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(result.title),
        content: Text(result.message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.musicMenu.title(context)),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                padding: listViewPadding,
                itemCount: displayItems.length,
                prototypeItem: const DisplayListTile(
                  text: '',
                  isSelected: false,
                ),
                itemBuilder: (context, index) => DisplayListTile(
                  text: displayItems[index].title(context),
                  isSelected: selectedDisplayItem == index,
                  onTap: () async => _navigateToScreen(displayItems[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportProgressDialog extends ConsumerWidget {
  const _ImportProgressDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(localAudioImportProgressProvider);
    final value = progress?.progressValue;
    return CupertinoAlertDialog(
      title: Text(progress?.title ?? 'Importing MP3s'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 14),
            const SizedBox(height: 12),
            if (value != null) ...[
              _ImportProgressBar(value: value),
              const SizedBox(height: 8),
            ],
            Text(
              progress?.detail ?? 'Preparing your songs...',
              textAlign: TextAlign.center,
            ),
            if (progress?.countText != null) ...[
              const SizedBox(height: 6),
              Text(
                progress!.countText!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              'Keep døPe open while artwork and metadata are saved.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportProgressBar extends StatelessWidget {
  const _ImportProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey4.resolveFrom(context),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.antiAlias,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0, 1).toDouble(),
        child: Container(
          decoration: BoxDecoration(
            color: CupertinoColors.activeBlue.resolveFrom(context),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}
