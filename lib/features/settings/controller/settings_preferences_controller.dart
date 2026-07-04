import 'dart:async';
import 'dart:io' as io;

import 'package:dope/core/alerts/dialogs.dart';
import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/providers/filtered_audio_files_provider.dart';
import 'package:dope/core/services/audio_equalizer_service.dart';
import 'package:dope/core/services/audio_files_service.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/features/music/playlist/models/playlist_model.dart';
import 'package:dope/features/settings/models/app_text_size.dart';
import 'package:dope/features/settings/models/app_theme.dart';
import 'package:dope/features/settings/models/click_wheel_sensitivity.dart';
import 'package:dope/features/settings/models/click_wheel_size.dart';
import 'package:dope/features/settings/models/custom_device_theme.dart';
import 'package:dope/features/settings/models/device_color.dart';
import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:dope/features/settings/models/repeat_mode.dart';
import 'package:dope/features/settings/models/settings_preferences_model.dart';
import 'package:dope/features/settings/models/song_sort_order.dart';
import 'package:dope/features/settings/models/song_transition_style.dart';
import 'package:dope/features/settings/models/volume_mode.dart';
import 'package:dope/features/settings/models/wheel_style.dart';
import 'package:dope/features/settings/repository/settings_preferences_repository.dart';
import 'package:dope/features/tutorial/controller/tutorial_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:universal_html/html.dart';
import 'package:volume_controller/volume_controller.dart';

final settingsPreferencesControllerProvider =
    NotifierProvider<
      SettingsPreferencesControllerNotifier,
      SettingsPreferencesModel
    >(SettingsPreferencesControllerNotifier.new);

class SettingsPreferencesControllerNotifier
    extends Notifier<SettingsPreferencesModel> {
  SettingsPreferencesControllerNotifier() : super();

  @override
  SettingsPreferencesModel build() {
    final settingsPreferencesRepository = ref.read(
      settingsPreferencesRepositoryProvider,
    );
    return SettingsPreferencesModel(
      languageLocaleCode: settingsPreferencesRepository.getLanguageLocaleCode(),
      deviceColor: DeviceColor.fromName(
        settingsPreferencesRepository.getDeviceColor(),
      ),
      customDeviceThemes: settingsPreferencesRepository.getCustomDeviceThemes(),
      activeCustomDeviceThemeId: settingsPreferencesRepository
          .getActiveCustomDeviceThemeId(),
      clickWheelSize: ClickWheelSize.values.byName(
        settingsPreferencesRepository.getClickWheelSize(),
      ),
      clickWheelSensitivity: ClickWheelSensitivity.values.byName(
        settingsPreferencesRepository.getClickWheelSensitivity(),
      ),
      isTouchScreenEnabled: settingsPreferencesRepository
          .getTouchScreenEnabled(),
      repeatMode: RepeatMode.values.byName(
        settingsPreferencesRepository.getRepeatMode(),
      ),
      vibrate: settingsPreferencesRepository.getVibrate(),
      clickWheelSound: settingsPreferencesRepository.getClickWheelSound(),
      volumeMode: VolumeMode.values.byName(
        settingsPreferencesRepository.getVolumeMode(),
      ),
      equalizerPreset: EqualizerPreset.fromName(
        settingsPreferencesRepository.getEqualizerPreset(),
      ),
      songSortOrder: SongSortOrder.fromName(
        settingsPreferencesRepository.getSongSortOrder(),
      ),
      songTransitionStyle: SongTransitionStyle.fromName(
        settingsPreferencesRepository.getSongTransitionStyle(),
      ),
      crossfadeDurationSeconds: settingsPreferencesRepository
          .getCrossfadeDurationSeconds(),
      appTextSize: AppTextSize.fromName(
        settingsPreferencesRepository.getTextSize(),
      ),
      splitScreenEnabled: settingsPreferencesRepository.getSplitScreenEnabled(),
      immersiveMode: settingsPreferencesRepository.getImmersiveMode(),
      useColorTextures: settingsPreferencesRepository.getUseColorTextures(),
      appTheme: AppTheme.fromName(settingsPreferencesRepository.getAppTheme()),
      wheelStyle: WheelStyle.fromName(
        settingsPreferencesRepository.getWheelStyle(),
      ),
    );
  }

  Future<void> setSystemUiMode() async {
    if (kIsWeb) {
      if (state.immersiveMode) {
        // ignore: unawaited_futures
        document.documentElement?.requestFullscreen();
      } else {
        document.exitFullscreen();
      }
    } else if (io.Platform.isAndroid || io.Platform.isIOS) {
      if (state.immersiveMode) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  void setAudioSource({required bool isOnlineAudioSource}) {
    if (isOnlineAudioSource) {
      state = state.copyWith(fetchOnlineMusic: true);
    } else {
      state = state.copyWith(fetchOnlineMusic: false);
    }
  }

  Future<void> showAppTutorial() async {
    await ref.read(tutorialControllerProvider.notifier).resetTutorials();
    ref.read(routerProvider).goNamed(Routes.menu.name);
    Future.delayed(const Duration(milliseconds: 500), () {
      ref.read(tutorialControllerProvider.notifier).playMenuTutorial();
    });
  }

  Future<void> initializeVolume() async {
    if (state.volumeMode != VolumeMode.app) {
      return;
    }

    final player = ref.read(audioPlayerProvider);
    final currentVolume = player.volume;
    if (currentVolume <= 0) {
      await player.setVolume(1);
    }
  }

  Future<void> setInitialRepeatMode() async {
    switch (state.repeatMode) {
      case RepeatMode.off:
        await ref
            .read(audioPlayerServiceProvider.notifier)
            .setLoopMode(LoopMode.off);
        break;
      case RepeatMode.one:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setRepeatMode(repeatModeName: RepeatMode.all.name);
        state = state.copyWith(repeatMode: RepeatMode.all);
      case RepeatMode.all:
        await ref
            .read(audioPlayerServiceProvider.notifier)
            .setLoopMode(LoopMode.all);
        break;
    }
  }

  Future<void> setLanguage(Locale locale) async {
    state = state.copyWith(languageLocaleCode: locale.languageCode);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setLanguageLocaleCode(languageLocaleCode: locale.languageCode);
  }

  Future<void> setDeviceColor(DeviceColor deviceColor) async {
    if (state.deviceColor == deviceColor && !state.isUsingCustomDeviceTheme) {
      return;
    }
    state = state.copyWith(
      deviceColor: deviceColor,
      clearActiveCustomDeviceThemeId: true,
    );
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setDeviceColor(deviceColorName: deviceColor.name);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setActiveCustomDeviceThemeId(null);
  }

  Future<void> selectCustomDeviceTheme(String themeId) async {
    final themeExists = state.customDeviceThemes.any(
      (theme) => theme.id == themeId,
    );
    if (!themeExists) {
      return;
    }
    if (state.activeCustomDeviceThemeId == themeId) {
      return;
    }
    state = state.copyWith(activeCustomDeviceThemeId: themeId);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setActiveCustomDeviceThemeId(themeId);
  }

  Future<CustomDeviceTheme> saveCustomDeviceTheme({
    required String name,
    required Color primaryColor,
    required Color secondaryColor,
  }) async {
    final trimmedName = name.trim().isEmpty ? 'Custom Theme' : name.trim();
    final theme = CustomDeviceTheme(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmedName,
      primaryColorValue: primaryColor.toARGB32(),
      secondaryColorValue: secondaryColor.toARGB32(),
    );
    final updatedThemes = [...state.customDeviceThemes, theme];
    state = state.copyWith(
      customDeviceThemes: updatedThemes,
      activeCustomDeviceThemeId: theme.id,
    );
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setCustomDeviceThemes(customThemes: updatedThemes);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setActiveCustomDeviceThemeId(theme.id);
    return theme;
  }

  Future<CustomDeviceTheme?> updateCustomDeviceTheme({
    required String themeId,
    required String name,
    required Color primaryColor,
    required Color secondaryColor,
  }) async {
    final themeIndex = state.customDeviceThemes.indexWhere(
      (theme) => theme.id == themeId,
    );
    if (themeIndex < 0) {
      return null;
    }

    final trimmedName = name.trim().isEmpty
        ? state.customDeviceThemes[themeIndex].name
        : name.trim();
    final updatedTheme = state.customDeviceThemes[themeIndex].copyWith(
      name: trimmedName,
      primaryColorValue: primaryColor.toARGB32(),
      secondaryColorValue: secondaryColor.toARGB32(),
    );
    final updatedThemes = [...state.customDeviceThemes];
    updatedThemes[themeIndex] = updatedTheme;
    state = state.copyWith(customDeviceThemes: updatedThemes);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setCustomDeviceThemes(customThemes: updatedThemes);
    return updatedTheme;
  }

  Future<void> deleteCustomDeviceTheme(String themeId) async {
    final updatedThemes = state.customDeviceThemes
        .where((theme) => theme.id != themeId)
        .toList(growable: false);
    if (updatedThemes.length == state.customDeviceThemes.length) {
      return;
    }

    final shouldClearActiveTheme = state.activeCustomDeviceThemeId == themeId;
    state = state.copyWith(
      customDeviceThemes: updatedThemes,
      clearActiveCustomDeviceThemeId: shouldClearActiveTheme,
    );
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setCustomDeviceThemes(customThemes: updatedThemes);
    if (shouldClearActiveTheme) {
      await ref
          .read(settingsPreferencesRepositoryProvider)
          .setActiveCustomDeviceThemeId(null);
    }
  }

  Future<void> toggleClickWheelSize() async {
    switch (state.clickWheelSize) {
      case ClickWheelSize.small:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setClickWheelSize(clickWheelSizeName: ClickWheelSize.medium.name);
        state = state.copyWith(clickWheelSize: ClickWheelSize.medium);
        break;
      case ClickWheelSize.medium:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setClickWheelSize(clickWheelSizeName: ClickWheelSize.large.name);
        state = state.copyWith(clickWheelSize: ClickWheelSize.large);
        break;
      case ClickWheelSize.large:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setClickWheelSize(clickWheelSizeName: ClickWheelSize.small.name);
        state = state.copyWith(clickWheelSize: ClickWheelSize.small);
        break;
    }
  }

  Future<void> toggleClickWheelSensitivity() async {
    switch (state.clickWheelSensitivity) {
      case ClickWheelSensitivity.veryLow:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setClickWheelSensitivity(
              clickWheelSensitivityName: ClickWheelSensitivity.low.name,
            );
        state = state.copyWith(
          clickWheelSensitivity: ClickWheelSensitivity.low,
        );
        break;
      case ClickWheelSensitivity.low:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setClickWheelSensitivity(
              clickWheelSensitivityName: ClickWheelSensitivity.medium.name,
            );
        state = state.copyWith(
          clickWheelSensitivity: ClickWheelSensitivity.medium,
        );
        break;
      case ClickWheelSensitivity.medium:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setClickWheelSensitivity(
              clickWheelSensitivityName: ClickWheelSensitivity.high.name,
            );
        state = state.copyWith(
          clickWheelSensitivity: ClickWheelSensitivity.high,
        );
        break;
      case ClickWheelSensitivity.high:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setClickWheelSensitivity(
              clickWheelSensitivityName: ClickWheelSensitivity.veryLow.name,
            );
        state = state.copyWith(
          clickWheelSensitivity: ClickWheelSensitivity.veryLow,
        );
        break;
    }
  }

  Future<void> toggleTouchScreen() async {
    state = state.copyWith(isTouchScreenEnabled: !state.isTouchScreenEnabled);

    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setTouchScreenEnabled(
          isTouchScreenEnabled: state.isTouchScreenEnabled,
        );
  }

  Future<void> toggleRepeatMode() async {
    switch (state.repeatMode) {
      case RepeatMode.off:
        state = state.copyWith(repeatMode: RepeatMode.one);
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setRepeatMode(repeatModeName: RepeatMode.one.name);
        break;
      case RepeatMode.one:
        state = state.copyWith(repeatMode: RepeatMode.all);
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setRepeatMode(repeatModeName: RepeatMode.all.name);
        break;
      case RepeatMode.all:
        state = state.copyWith(repeatMode: RepeatMode.off);
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setRepeatMode(repeatModeName: RepeatMode.off.name);
        break;
    }
    await ref
        .read(audioPlayerServiceProvider.notifier)
        .setLoopMode(state.repeatMode.toLoopMode());
  }

  Future<void> toggleVibrate() async {
    state = state.copyWith(vibrate: !state.vibrate);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setVibrate(isVibrateEnabled: state.vibrate);
  }

  Future<void> toggleClickWheelSound(BuildContext context) async {
    state = state.copyWith(clickWheelSound: !state.clickWheelSound);

    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setClickWheelSound(isClickWheelSoundEnabled: state.clickWheelSound);

    if (state.clickWheelSound && context.mounted) {
      await Dialogs.showInfoDialog(
        context: context,
        title: context.localization.touchSoundsDialogTitle,
        content: context.localization.touchSoundsDialogContent,
      );
    }
  }

  Future<void> toggleVolumeMode() async {
    switch (state.volumeMode) {
      case VolumeMode.app:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setVolumeMode(volumeModeName: VolumeMode.system.name);
        state = state.copyWith(volumeMode: VolumeMode.system);
        break;
      case VolumeMode.system:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setVolumeMode(volumeModeName: VolumeMode.app.name);
        state = state.copyWith(volumeMode: VolumeMode.app);
        break;
    }
  }

  Future<void> toggleEqualizerPreset() async {
    final updatedPreset = state.equalizerPreset.next;
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setEqualizerPreset(equalizerPresetName: updatedPreset.name);
    state = state.copyWith(equalizerPreset: updatedPreset);
    await ref.read(audioEqualizerServiceProvider).applyPreset(updatedPreset);
  }

  Future<void> toggleSongSortOrder() async {
    final updatedSortOrder = state.songSortOrder.next;
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setSongSortOrder(songSortOrderName: updatedSortOrder.name);
    state = state.copyWith(songSortOrder: updatedSortOrder);
  }

  Future<void> toggleSongTransitionStyle() async {
    final updatedStyle = state.songTransitionStyle.next;
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setSongTransitionStyle(songTransitionStyleName: updatedStyle.name);
    state = state.copyWith(songTransitionStyle: updatedStyle);
    await ref
        .read(audioPlayerServiceProvider.notifier)
        .syncSongTransitionStyle();
  }

  Future<void> increaseCrossfadeDuration() async {
    final currentSeconds = state.crossfadeDurationSeconds;
    final updatedSeconds = currentSeconds >= maxCrossfadeDurationSeconds
        ? minCrossfadeDurationSeconds
        : currentSeconds + 1;
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setCrossfadeDurationSeconds(seconds: updatedSeconds);
    state = state.copyWith(crossfadeDurationSeconds: updatedSeconds);
    await ref
        .read(audioPlayerServiceProvider.notifier)
        .syncSongTransitionStyle();
  }

  Future<void> toggleSplitScreen() async {
    state = state.copyWith(splitScreenEnabled: !state.splitScreenEnabled);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setSplitScreenEnabled(isSplitScreenEnabled: state.splitScreenEnabled);
  }

  Future<void> toggleColorTextures() async {
    state = state.copyWith(useColorTextures: !state.useColorTextures);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setUseColorTextures(isUseColorTexturesEnabled: state.useColorTextures);
  }

  Future<void> toggleAppTheme() async {
    final AppTheme updatedTheme = state.appTheme == AppTheme.light
        ? AppTheme.dark
        : AppTheme.light;
    state = state.copyWith(appTheme: updatedTheme);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setAppTheme(appThemeName: updatedTheme.name);
  }

  Future<void> toggleTextSize() async {
    final updatedTextSize = state.appTextSize.next;
    state = state.copyWith(appTextSize: updatedTextSize);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setTextSize(textSizeName: updatedTextSize.name);
  }

  Future<void> setWheelStyle(WheelStyle wheelStyle) async {
    if (state.wheelStyle == wheelStyle) {
      return;
    }
    state = state.copyWith(wheelStyle: wheelStyle);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setWheelStyle(wheelStyleName: wheelStyle.name);
  }

  Future<void> toggleWheelStyle() async {
    final updatedStyle = state.wheelStyle == WheelStyle.modern
        ? WheelStyle.classic
        : WheelStyle.modern;
    await setWheelStyle(updatedStyle);
  }

  Future<void> toggleImmersiveMode() async {
    state = state.copyWith(immersiveMode: !state.immersiveMode);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setImmersiveMode(isImmersiveModeEnabled: state.immersiveMode);
    await setSystemUiMode();
  }

  Future<void> rescanMusicFiles({bool clearPlaylists = false}) async {
    await Hive.box<MusicMetadata>(Constants.metadataBoxName).clear();
    if (clearPlaylists) {
      await Hive.box<PlaylistModel>(Constants.playlistBoxName).clear();
    }
    ref.invalidate(audioFilesServiceProvider);
    ref.invalidate(filteredAudioFilesProvider);
    ref.read(routerProvider).goNamed(Routes.splash.name);
  }

  Future<void> resetSettings() async {
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setLanguageLocaleCode(languageLocaleCode: 'en');
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setDeviceColor(deviceColorName: DeviceColor.silver.name);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setCustomDeviceThemes(customThemes: const []);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setActiveCustomDeviceThemeId(null);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setTouchScreenEnabled(isTouchScreenEnabled: true);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setRepeatMode(repeatModeName: RepeatMode.off.name);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setVibrate(isVibrateEnabled: true);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setClickWheelSound(isClickWheelSoundEnabled: false);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setEqualizerPreset(equalizerPresetName: EqualizerPreset.off.name);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setSongSortOrder(songSortOrderName: SongSortOrder.title.name);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setSongTransitionStyle(
          songTransitionStyleName: SongTransitionStyle.off.name,
        );
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setCrossfadeDurationSeconds(seconds: defaultCrossfadeDurationSeconds);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setTextSize(textSizeName: AppTextSize.medium.name);
    state = state.copyWith(appTextSize: AppTextSize.medium);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setSplitScreenEnabled(isSplitScreenEnabled: true);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setImmersiveMode(isImmersiveModeEnabled: false);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setUseColorTextures(isUseColorTexturesEnabled: true);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setAppTheme(appThemeName: AppTheme.light.name);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setWheelStyle(wheelStyleName: WheelStyle.modern.name);
    state = state.copyWith(
      songTransitionStyle: SongTransitionStyle.off,
      crossfadeDurationSeconds: defaultCrossfadeDurationSeconds,
      useColorTextures: true,
      customDeviceThemes: const [],
      clearActiveCustomDeviceThemeId: true,
      wheelStyle: WheelStyle.modern,
    );
    await ref
        .read(audioEqualizerServiceProvider)
        .applyPreset(EqualizerPreset.off);
    await ref
        .read(audioPlayerServiceProvider.notifier)
        .syncSongTransitionStyle();
    ref.invalidateSelf();
  }

  Future<void> increaseVolume() async {
    if (state.volumeMode == VolumeMode.app) {
      final double currentVolume = ref.read(audioPlayerProvider).volume;
      if (currentVolume < 1) {
        await ref.read(audioPlayerProvider).setVolume(currentVolume + 0.05);
      }
    } else {
      final double currentVolume = await VolumeController.instance.getVolume();
      if (currentVolume < 1) {
        await VolumeController.instance.setVolume(
          (currentVolume + 0.05).clamp(0, 1),
        );
      }
    }
  }

  Future<void> decreaseVolume() async {
    if (state.volumeMode == VolumeMode.app) {
      final double currentVolume = ref.read(audioPlayerProvider).volume;
      if (currentVolume > 0) {
        if (currentVolume <= 0.05) {
          await ref.read(audioPlayerProvider).setVolume(0);
        } else {
          await ref.read(audioPlayerProvider).setVolume(currentVolume - 0.05);
        }
      }
    } else {
      final double currentVolume = await VolumeController.instance.getVolume();
      if (currentVolume > 0) {
        await VolumeController.instance.setVolume(
          (currentVolume - 0.05).clamp(0, 1),
        );
      }
    }
  }
}
