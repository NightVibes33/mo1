import 'dart:async';
import 'dart:io';

import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/providers/device_directory_provider.dart';
import 'package:dope/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:dope/core/services/app_documents_service.dart';
import 'package:dope/core/services/crash_log_service.dart';
import 'package:dope/features/music/playlist/models/playlist_model.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/exclude_directory_model.dart';
import 'package:dope/hive/hive_registrar.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

final appStartupControllerProvider = FutureProvider<void>((ref) async {
  await Future.wait([
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
      JustAudioBackground.init(
        androidNotificationChannelId: 'classipod.audio.playback',
        androidNotificationChannelName: 'døPe Audio playback',
        androidNotificationChannelDescription:
            'Notification to control the currently playing music files',
        androidNotificationOngoing: true,
        androidNotificationIcon: 'drawable/ic_stat_name',
      ),
    ],
    if (!kIsWeb) ref.watch(deviceDirectoryProvider.future),
    ref.watch(sharedPreferencesWithCacheProvider.future),
  ]);
  if (!kIsWeb) {
    await ref.read(appDocumentsServiceProvider).migrateLegacyStorage();
    final crashLogService = ref.read(crashLogServiceProvider);
    await crashLogService.initialize();
    crashLogService.installFlutterErrorHandlers();
  }
  await Hive.initFlutter(Constants.appDocumentsFolderName);
  Hive.registerAdapters();
  await _openBoxWithRecovery<MusicMetadata>(Constants.metadataBoxName);
  await _openBoxWithRecovery<PlaylistModel>(Constants.playlistBoxName);
  await _openBoxWithRecovery<ExcludeDirectoryModel>(
    Constants.excludedDirectoriesBoxName,
  );
  if (!kIsWeb) {
    await _migrateStoredLegacyPaths(ref, ref.read(appDocumentsServiceProvider));
  }
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    JustAudioMediaKit.ensureInitialized();
    JustAudioMediaKit.title = 'døPe';
  }
  ref
      .read(settingsPreferencesControllerProvider.notifier)
      .setAudioSource(isOnlineAudioSource: kIsWeb);
  unawaited(
    ref.read(settingsPreferencesControllerProvider.notifier).setSystemUiMode(),
  );
});

Future<void> _migrateStoredLegacyPaths(
  Ref ref,
  AppDocumentsService appDocumentsService,
) async {
  final metadataBox = Hive.box<MusicMetadata>(Constants.metadataBoxName);
  for (var index = 0; index < metadataBox.length; index++) {
    final metadata = metadataBox.getAt(index);
    if (metadata == null) {
      continue;
    }
    final migratedFilePath = appDocumentsService.migrateLegacyPath(
      metadata.filePath,
    );
    final migratedThumbnailPath = appDocumentsService.migrateLegacyPath(
      metadata.thumbnailPath,
    );
    if (migratedFilePath != metadata.filePath ||
        migratedThumbnailPath != metadata.thumbnailPath) {
      await metadataBox.putAt(
        index,
        metadata.copyWith(
          filePath: migratedFilePath,
          thumbnailPath: migratedThumbnailPath,
        ),
      );
    }
  }

  final playlistBox = Hive.box<PlaylistModel>(Constants.playlistBoxName);
  for (var index = 0; index < playlistBox.length; index++) {
    final playlist = playlistBox.getAt(index);
    if (playlist == null) {
      continue;
    }
    var changed = false;
    final migratedSongs = <MusicMetadata>[];
    for (final song in playlist.songs) {
      final migratedFilePath = appDocumentsService.migrateLegacyPath(
        song.filePath,
      );
      final migratedThumbnailPath = appDocumentsService.migrateLegacyPath(
        song.thumbnailPath,
      );
      if (migratedFilePath != song.filePath ||
          migratedThumbnailPath != song.thumbnailPath) {
        changed = true;
        migratedSongs.add(
          song.copyWith(
            filePath: migratedFilePath,
            thumbnailPath: migratedThumbnailPath,
          ),
        );
      } else {
        migratedSongs.add(song);
      }
    }
    if (changed) {
      await playlistBox.putAt(index, playlist.copyWith(songs: migratedSongs));
    }
  }

  final excludedDirectoriesBox = Hive.box<ExcludeDirectoryModel>(
    Constants.excludedDirectoriesBoxName,
  );
  for (var index = 0; index < excludedDirectoriesBox.length; index++) {
    final directory = excludedDirectoriesBox.getAt(index);
    if (directory == null) {
      continue;
    }
    final migratedPath = appDocumentsService.migrateLegacyPath(
      directory.directoryPath,
    );
    if (migratedPath != directory.directoryPath) {
      await excludedDirectoriesBox.putAt(
        index,
        directory.copyWith(directoryPath: migratedPath),
      );
    }
  }
}

Future<Box<T>> _openBoxWithRecovery<T>(String boxName) async {
  try {
    return await Hive.openBox<T>(boxName);
  } catch (error, stackTrace) {
    debugPrint('Hive box recovery for $boxName after open failure: $error');
    debugPrintStack(stackTrace: stackTrace);
    await Hive.deleteBoxFromDisk(boxName);
    return Hive.openBox<T>(boxName);
  }
}
