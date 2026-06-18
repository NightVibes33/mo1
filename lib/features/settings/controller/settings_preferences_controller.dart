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
import 'package:dope/features/settings/models/device_color.dart';
import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:dope/features/settings/models/repeat_mode.dart';
import 'package:dope/features/settings/models/settings_preferences_model.dart';
import 'package:dope/features/settings/models/song_sort_order.dart';
import 'package:dope/features/settings/models/song_transition_style.dart';
import 'package:dope/features/settings/models/volume_mode.dart';
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
      crossfadeDurationSeconds:
          settingsPreferencesRepository.getCrossfadeDurationSeconds(),
      appTextSize: AppTextSize.fromName(
        settingsPreferencesRepository.getTextSize(),
      ),
      splitScreenEnabled: settingsPreferencesRepository.getSplitScreenEnabled(),
      immersiveMode: settingsPreferencesRepository.getImmersiveMode(),
      appTheme: AppTheme.fromName(settingsPreferencesRepository.getAppTheme()),
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

  Future<void> setInitialRepeatMode() async {
    switch (state.repeatMode) {
      case RepeatMode.off:
        await ref
            .read(audioPlayerServiceProvider.notifier)
            .setLoopMode(LoopMode.off);
        break;
      case RepeatMode.one:
        // in case app starts with repeat mode one, set the loop mode to all
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
    if (state.deviceColor == deviceColor) {
      return;
    }
    state = state.copyWith(deviceColor: deviceColor);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setDeviceColor(deviceColorName: deviceColor.name);
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
    await ref.read(audioPlayerServiceProvider.notifier).toggleRepeatMode();
  }

  Future<void> setRepeatMode(RepeatMode repeatMode) async {
    state = state.copyWith(repeatMode: repeatMode);
    switch (repeatMode) {
      case RepeatMode.off:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setRepeatMode(repeatModeName: RepeatMode.off.name);
        await ref
            .read(audioPlayerServiceProvider.notifier)
            .setRepeatMode(RepeatMode.off);
        break;
      case RepeatMode.one:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setRepeatMode(repeatModeName: RepeatMode.one.name);
        await ref
            .read(audioPlayerServiceProvider.notifier)
            .setRepeatMode(RepeatMode.one);
        break;
      case RepeatMode.all:
        await ref
            .read(settingsPreferencesRepositoryProvider)
            .setRepeatMode(repeatModeName: RepeatMode.all.name);
        await ref
            .read(audioPlayerServiceProvider.notifier)
            .setRepeatMode(RepeatMode.all);
        break;
    }
  }

  Future<void> toggleVibrate() async {
    state = state.copyWith(vibrate: !state.vibrate);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setVibrate(isVibrateEnabled: state.vibrate);
  }

  Future<void> toggleClickWheelSound() async {
    state = state.copyWith(clickWheelSound: !state.clickWheelSound);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setClickWheelSound(isClickWheelSoundEnabled: state.clickWheelSound);
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
    await ref
        .read(audioEqualizerServiceProvider.notifier)
        .applyPreset(updatedPreset);
  }

  Future<void> toggleSongSortOrder() async {
    final updatedSortOrder = state.songSortOrder.next;
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setSongSortOrder(songSortOrderName: updatedSortOrder.name);
    state = state.copyWith(songSortOrder: updatedSortOrder);
  }

  Future<void> setSongTransitionStyle(
    SongTransitionStyle songTransitionStyle,
  ) async {
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setSongTransitionStyle(
          songTransitionStyleName: songTransitionStyle.name,
        );
    state = state.copyWith(songTransitionStyle: songTransitionStyle);
    await ref
        .read(audioPlayerServiceProvider.notifier)
        .syncSongTransitionStyle();
  }

  Future<void> setCrossfadeDurationSeconds(int seconds) async {
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setCrossfadeDurationSeconds(seconds: seconds);
    state = state.copyWith(crossfadeDurationSeconds: seconds);
    await ref
        .read(audioPlayerServiceProvider.notifier)
        .syncSongTransitionStyle();
  }

  Future<void> setAppTextSize(AppTextSize appTextSize) async {
    state = state.copyWith(appTextSize: appTextSize);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setTextSize(textSizeName: appTextSize.name);
  }

  Future<void> toggleSplitScreenEnabled() async {
    state = state.copyWith(splitScreenEnabled: !state.splitScreenEnabled);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setSplitScreenEnabled(
          isSplitScreenEnabled: state.splitScreenEnabled,
        );
  }

  Future<void> toggleImmersiveMode() async {
    state = state.copyWith(immersiveMode: !state.immersiveMode);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setImmersiveMode(isImmersiveModeEnabled: state.immersiveMode);
    await setSystemUiMode();
  }

  Future<void> setAppTheme(AppTheme appTheme) async {
    state = state.copyWith(appTheme: appTheme);
    await ref
        .read(settingsPreferencesRepositoryProvider)
        .setAppTheme(appThemeName: appTheme.name);
  }

  Future<void> resetDatabase() async {
    await ref.read(audioFilesServiceProvider.notifier).resetDatabase();
  }

  Future<void> resetAllSettings() async {
    final settingsRepo = ref.read(settingsPreferencesRepositoryProvider);
    await settingsRepo.setRepeatMode(repeatModeName: RepeatMode.off.name);
    await settingsRepo.setVibrate(isVibrateEnabled: true);
    await settingsRepo.setClickWheelSound(
      isClickWheelSoundEnabled: false,
    );
    await settingsRepo.setEqualizerPreset(
      equalizerPresetName: EqualizerPreset.off.name,
    );
    await settingsRepo.setSongSortOrder(
      songSortOrderName: SongSortOrder.title.name,
    );
    await settingsRepo.setSongTransitionStyle(
      songTransitionStyleName: SongTransitionStyle.off.name,
    );
    await settingsRepo.setCrossfadeDurationSeconds(
      seconds: defaultCrossfadeDurationSeconds,
    );
    await settingsRepo.setTextSize(textSizeName: AppTextSize.medium.name);
    await settingsRepo.setAppTheme(appThemeName: AppTheme.light.name);
    state = state.copyWith(
      songTransitionStyle: SongTransitionStyle.off,
      crossfadeDurationSeconds: defaultCrossfadeDurationSeconds,
    );
    await ref
        .read(audioEqualizerServiceProvider.notifier)
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
        await ref.read(audioPlayerProvider).setVolume(currentVolume - 0.05);
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

  Future<void> showConfirmDeletePlaylistDialog({
    required BuildContext context,
    required PlaylistModel playlist,
  }) async {
    await showConfirmDialog(
      context: context,
      title: context.l10n.delete_playlist,
      content: context.l10n.confirm_delete_playlist(playlist.name),
      onConfirm: () {
        ref.read(audioFilesServiceProvider.notifier).deletePlaylist(
              playlist: playlist,
            );
      },
    );
  }

  Future<void> showConfirmDeleteSongDialog({
    required BuildContext context,
    required MusicMetadata song,
  }) async {
    await showConfirmDialog(
      context: context,
      title: context.l10n.delete_song,
      content: context.l10n.confirm_delete_song(song.trackName),
      onConfirm: () {
        ref.read(audioFilesServiceProvider.notifier).deleteSong(song: song);
      },
    );
  }
}
