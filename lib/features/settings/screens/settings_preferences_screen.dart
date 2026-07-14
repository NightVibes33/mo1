import 'dart:async';

import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/audio_files_service.dart';
import 'package:dope/core/services/imported_library_refresh_service.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/core/services/app_data_reset_service.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/menu/controller/split_screen_controller.dart';
import 'package:dope/features/menu/models/split_screen_type.dart';
import 'package:dope/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/settings_preferences_model.dart';
import 'package:dope/features/settings/widgets/settings_list_tile.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _SettingsDisplayItems {
  about,
  shuffle,
  repeat,
  equalizer,
  songSortOrder,
  songTransitions,
  crossfadeDuration,
  language,
  appTheme,
  textSize,
  deviceColor,
  gradientTextures,
  clickWheelSize,
  wheelStyle,
  clickWheelSensitivity,
  isTouchScreenEnabled,
  vibrate,
  clickWheelSound,
  volumeMode,
  splitScreenEnabled,
  immersiveMode,
  showAppTutorial,
  importSongs,
  rescanMusicFiles,
  excludeDirectories,
  debugLogs,
  resetDatabase,
  resetSettings;

  String title(BuildContext context) {
    switch (this) {
      case about:
        return context.localization.aboutScreenTitle;
      case shuffle:
        return context.localization.shuffleSettingTitle;
      case repeat:
        return context.localization.repeatModeSettingTitle;
      case equalizer:
        return 'EQ';
      case songSortOrder:
        return 'Sort By';
      case songTransitions:
        return 'Song Transitions';
      case crossfadeDuration:
        return 'Crossfade';
      case language:
        return context.localization.languageScreenTitle;
      case appTheme:
        return context.localization.themeSettingTitle;
      case textSize:
        return 'Text Size';
      case isTouchScreenEnabled:
        return context.localization.touchScreenSettingTitle;
      case deviceColor:
        return context.localization.deviceColorSettingTitle;
      case gradientTextures:
        return "Gradient Textures";
      case clickWheelSize:
        return context.localization.clickWheelSizeSettingTitle;
      case wheelStyle:
        return 'Wheel Style';
      case clickWheelSensitivity:
        return context.localization.clickWheelSensitivitySettingTitle;
      case volumeMode:
        return context.localization.volumeModeSettingTitle;
      case vibrate:
        return context.localization.vibrateSettingTitle;
      case clickWheelSound:
        return context.localization.clickWheelSettingTitle;
      case splitScreenEnabled:
        return context.localization.splitScreenSettingTitle;
      case immersiveMode:
        return context.localization.immersiveModeSettingTitle;
      case showAppTutorial:
        return context.localization.showAppTutorialSettingTitle;
      case importSongs:
        return 'Import Songs';
      case rescanMusicFiles:
        return context.localization.rescanMusicFilesSettingTitle;
      case excludeDirectories:
        return context.localization.excludeDirectoriesScreenTitle;
      case debugLogs:
        return 'Debug Logs';
      case resetDatabase:
        return 'Reset Database';
      case resetSettings:
        return context.localization.resetSettingsTitle;
    }
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.settings.name;

  @override
  List<_SettingsDisplayItems> get displayItems => _SettingsDisplayItems.values;

  @override
  Future<void> onSelectPressed() =>
      _settingAction(displayItems[selectedDisplayItem]);

  Future<void> _settingAction(_SettingsDisplayItems settingItem) async {
    setState(() => selectedDisplayItem = displayItems.indexOf(settingItem));
    switch (settingItem) {
      case _SettingsDisplayItems.about:
        context.goNamed(Routes.about.name);
        break;
      case _SettingsDisplayItems.language:
        context.goNamed(Routes.language.name);
        break;
      case _SettingsDisplayItems.shuffle:
        await ref.read(audioPlayerServiceProvider.notifier).toggleShuffleMode();
        break;
      case _SettingsDisplayItems.repeat:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleRepeatMode();
        break;
      case _SettingsDisplayItems.equalizer:
        context.goNamed(Routes.equalizer.name);
        break;
      case _SettingsDisplayItems.songSortOrder:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleSongSortOrder();
        break;
      case _SettingsDisplayItems.songTransitions:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleSongTransitionStyle();
        break;
      case _SettingsDisplayItems.crossfadeDuration:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .increaseCrossfadeDuration();
        break;
      case _SettingsDisplayItems.appTheme:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleAppTheme();
        break;
      case _SettingsDisplayItems.textSize:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleTextSize();
        break;
      case _SettingsDisplayItems.deviceColor:
        context.goNamed(Routes.deviceColor.name);
        break;
      case _SettingsDisplayItems.gradientTextures:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleColorTextures();
        break;
      case _SettingsDisplayItems.clickWheelSize:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleClickWheelSize();
        break;
      case _SettingsDisplayItems.wheelStyle:
        context.goNamed(Routes.wheelStyle.name);
        break;
      case _SettingsDisplayItems.clickWheelSensitivity:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleClickWheelSensitivity();
        break;
      case _SettingsDisplayItems.isTouchScreenEnabled:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleTouchScreen();
        break;
      case _SettingsDisplayItems.vibrate:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleVibrate();
        break;
      case _SettingsDisplayItems.clickWheelSound:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleClickWheelSound(context);
        break;
      case _SettingsDisplayItems.volumeMode:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleVolumeMode();
        break;
      case _SettingsDisplayItems.splitScreenEnabled:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleSplitScreen();
        break;
      case _SettingsDisplayItems.immersiveMode:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .toggleImmersiveMode();
        break;
      case _SettingsDisplayItems.showAppTutorial:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .showAppTutorial();
        break;
      case _SettingsDisplayItems.importSongs:
        final importResult = await ref
            .read(audioFilesServiceProvider.notifier)
            .importLocalAudioFiles();
        if (mounted) {
          await _showImportResult(importResult);
        }
        if (importResult.hasImportedSongs && mounted) {
          await refreshImportedLibraryProviders(ref);
        }
        break;
      case _SettingsDisplayItems.rescanMusicFiles:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .rescanMusicFiles();
        break;
      case _SettingsDisplayItems.excludeDirectories:
        context.goNamed(Routes.excludeDirectories.name);
        break;
      case _SettingsDisplayItems.debugLogs:
        context.goNamed(Routes.debugLogs.name);
        break;
      case _SettingsDisplayItems.resetDatabase:
        final shouldReset = await _confirmResetDatabase();
        if (!shouldReset || !mounted) {
          return;
        }
        await ref.read(appDataResetServiceProvider).resetDatabase();
        if (mounted) {
          await _showResetDatabaseComplete();
        }
        break;
      case _SettingsDisplayItems.resetSettings:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .resetSettings();
        break;
    }
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

  Future<bool> _confirmResetDatabase() async {
    if (!mounted) {
      return false;
    }
    final shouldReset = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Reset Database?'),
        content: const Text(
          'This deletes imported songs, Apple Music library entries, playlists, album artwork, thumbnails, excluded folders, debug logs, and crash logs.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    return shouldReset ?? false;
  }

  Future<void> _showResetDatabaseComplete() async {
    if (!mounted) {
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Database Reset'),
        content: const Text('Your local library data has been cleared.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool? _isOn(
    SettingsPreferencesModel settingsState,
    _SettingsDisplayItems settingsItem,
  ) {
    switch (settingsItem) {
      case _SettingsDisplayItems.shuffle:
        return ref.watch(nowPlayingDetailsProvider).isShuffleEnabled;
      case _SettingsDisplayItems.isTouchScreenEnabled:
        return settingsState.isTouchScreenEnabled;
      case _SettingsDisplayItems.gradientTextures:
        return settingsState.useColorTextures;
      case _SettingsDisplayItems.vibrate:
        return settingsState.vibrate;
      case _SettingsDisplayItems.clickWheelSound:
        return settingsState.clickWheelSound;
      case _SettingsDisplayItems.splitScreenEnabled:
        return settingsState.splitScreenEnabled;
      case _SettingsDisplayItems.immersiveMode:
        return settingsState.immersiveMode;
      default:
        return null;
    }
  }

  String? _getSubtitle(_SettingsDisplayItems settingsItem) {
    switch (settingsItem) {
      case _SettingsDisplayItems.equalizer:
        return 'Supports MP3, Navidrome, and Jellyfin. Apple Music is not affected.';
      default:
        return null;
    }
  }

  String? _getValue(
    SettingsPreferencesModel settingsState,
    _SettingsDisplayItems settingsItem,
  ) {
    switch (settingsItem) {
      case _SettingsDisplayItems.deviceColor:
        return settingsState.activeCustomDeviceTheme?.name ??
            settingsState.deviceColor.title(context);
      case _SettingsDisplayItems.gradientTextures:
        return settingsState.useColorTextures
            ? context.localization.tileValueOn
            : context.localization.tileValueOff;
      case _SettingsDisplayItems.clickWheelSize:
        return settingsState.clickWheelSize.title(context);
      case _SettingsDisplayItems.wheelStyle:
        return settingsState.wheelStyle.title(context);
      case _SettingsDisplayItems.clickWheelSensitivity:
        return settingsState.clickWheelSensitivity.title(context);
      case _SettingsDisplayItems.appTheme:
        return settingsState.appTheme.title(context);
      case _SettingsDisplayItems.textSize:
        return settingsState.appTextSize.title;
      case _SettingsDisplayItems.repeat:
        return settingsState.repeatMode.title(context);
      case _SettingsDisplayItems.equalizer:
        return settingsState.equalizerDisplayTitle;
      case _SettingsDisplayItems.songSortOrder:
        return settingsState.songSortOrder.titleText;
      case _SettingsDisplayItems.songTransitions:
        return settingsState.songTransitionStyle.titleText;
      case _SettingsDisplayItems.crossfadeDuration:
        return '${settingsState.crossfadeDurationSeconds}s';
      case _SettingsDisplayItems.volumeMode:
        return settingsState.volumeMode.title(context);
      default:
        final bool? isOn = _isOn(settingsState, settingsItem);
        if (isOn != null) {
          if (isOn) {
            return context.localization.tileValueOn;
          } else {
            return context.localization.tileValueOff;
          }
        }
        return null;
    }
  }

  Future<void> _changeSplitScreenType() async {
    await Future.delayed(const Duration(milliseconds: 150));
    switch (displayItems[selectedDisplayItem]) {
      case _SettingsDisplayItems.language:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.language;
        break;

      case _SettingsDisplayItems.deviceColor:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.deviceColor;
        break;
      case _SettingsDisplayItems.gradientTextures:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.gradientTextures;
        break;
      case _SettingsDisplayItems.appTheme:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.appTheme;
        break;
      case _SettingsDisplayItems.textSize:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.textSize;
        break;
      case _SettingsDisplayItems.clickWheelSize:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.clickWheelSize;
        break;
      case _SettingsDisplayItems.clickWheelSensitivity:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.clickWheelSensitivity;
        break;
      case _SettingsDisplayItems.isTouchScreenEnabled:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.touchScreen;
        break;
      case _SettingsDisplayItems.shuffle:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.shuffle;
        break;
      case _SettingsDisplayItems.repeat:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.repeat;
        break;
      case _SettingsDisplayItems.equalizer:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.equalizer;
        break;
      case _SettingsDisplayItems.songSortOrder:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.songSortOrder;
        break;
      case _SettingsDisplayItems.songTransitions:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.songTransitions;
        break;
      case _SettingsDisplayItems.crossfadeDuration:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.crossfadeDuration;
        break;
      case _SettingsDisplayItems.vibrate:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.vibrate;
        break;
      case _SettingsDisplayItems.clickWheelSound:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.clickWheelSound;
        break;
      case _SettingsDisplayItems.volumeMode:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.volumeMode;
        break;
      case _SettingsDisplayItems.splitScreenEnabled:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.splitScreenMode;
        break;
      case _SettingsDisplayItems.immersiveMode:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.immersiveMode;
        break;
      case _SettingsDisplayItems.showAppTutorial:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.showTutorialScreen;
        break;
      case _SettingsDisplayItems.importSongs:
      case _SettingsDisplayItems.rescanMusicFiles:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.rescanMusicFiles;
        break;
      case _SettingsDisplayItems.excludeDirectories:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.excludeDirectories;
        break;
      case _SettingsDisplayItems.debugLogs:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.debugLogs;
        break;
      case _SettingsDisplayItems.resetDatabase:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.resetDatabase;
        break;
      case _SettingsDisplayItems.resetSettings:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.resetSettings;
        break;
      default:
        ref.read(splitScreenControllerProvider.notifier).changeSplitScreenType =
            SplitScreenType.settings;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsPreferencesControllerProvider);

    unawaited(_changeSplitScreenType());

    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.settings.title(context)),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                padding: listViewPadding,
                itemCount: displayItems.length,
                itemBuilder: (context, index) => SettingsListTile(
                  text: displayItems[index].title(context),
                  value: _getValue(settingsState, displayItems[index]),
                  subtitle: _getSubtitle(displayItems[index]),
                  isSelected: selectedDisplayItem == index,
                  onTap: () async => _settingAction(displayItems[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
