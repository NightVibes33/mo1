import 'dart:io';

import 'package:dopi/core/navigation/routes.dart';
import 'package:dopi/core/providers/filtered_audio_files_provider.dart';
import 'package:dopi/features/music/album/providers/album_details_provider.dart';
import 'package:dopi/features/music/artists/providers/artist_names_provider.dart';
import 'package:dopi/features/music/genres/providers/genres_provider.dart';
import 'package:dopi/features/music/playlist/providers/playlists_provider.dart';
import 'package:dopi/features/music/songs/provider/songs_provider.dart';
import 'package:dopi/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dopi/features/settings/controller/settings_preferences_controller.dart';
import 'package:dopi/features/tutorial/controller/tutorial_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final splashControllerProvider =
    AsyncNotifierProvider<SplashControllerNotifier, void>(
      SplashControllerNotifier.new,
    );

class SplashControllerNotifier extends AsyncNotifier<void> {
  bool _hasCompletedLaunch = false;

  bool get hasCompletedLaunch => _hasCompletedLaunch;

  @override
  Future<void> build() async {
    await requestStoragePermissions();
  }

  Future<void> refreshImportedLibrary() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(initializeApp);
    _hasCompletedLaunch = !state.hasError;
  }

  Future<void> requestStoragePermissions() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final PermissionStatus audioPermission = await Permission.audio
            .request();
        final PermissionStatus genericStoragePermission = await Permission
            .storage
            .request();
        if (audioPermission.isDenied && genericStoragePermission.isDenied) {
          throw const AudioPermissionDeniedException();
        }
        if (audioPermission.isPermanentlyDenied &&
            genericStoragePermission.isPermanentlyDenied) {
          throw const AudioPermissionPermanentlyDeniedException();
        }
      }

      await initializeApp();
    });
    _hasCompletedLaunch = !state.hasError;
  }

  Future<void> initializeApp() async {
    // Load the filtered audio files metadata
    final filteredAudioFilesMetadata = await ref
        .read(filteredAudioFilesProvider.future)
        .then((value) => value.toList());

    // Keep startup lightweight: only hydrate metadata here. The audio engine
    // prepares the queue when playback starts so a bad imported MP3 cannot
    // brick app launch.
    ref.read(nowPlayingDetailsProvider.notifier).setNewMetadataList(
          newMetadataList: filteredAudioFilesMetadata,
        );

    // Set the initial loop mode
    await ref
        .read(settingsPreferencesControllerProvider.notifier)
        .setInitialRepeatMode();
    await ref
        .read(settingsPreferencesControllerProvider.notifier)
        .initializeVolume();

    // Invalidate the providers that depend on the audio files metadata
    ref.invalidate(albumDetailsProvider);
    ref.invalidate(artistNamesProvider);
    ref.invalidate(songsProvider);
    ref.invalidate(playlistsProvider);
    ref.invalidate(genresProvider);
    ref.invalidate(tutorialControllerProvider);

    // Load the playlists
    ref.read(playlistsProvider.notifier).refreshProvider();

    // Navigate to the menu screen
    ref.read(routerProvider).goNamed(Routes.menu.name);
  }
}

class AudioPermissionDeniedException implements Exception {
  const AudioPermissionDeniedException();
}

class AudioPermissionPermanentlyDeniedException implements Exception {
  const AudioPermissionPermanentlyDeniedException();
}
