import 'dart:convert';

import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/models/shared_preference_keys.dart';
import 'package:dope/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:dope/features/settings/models/app_text_size.dart';
import 'package:dope/features/settings/models/app_theme.dart';
import 'package:dope/features/settings/models/click_wheel_sensitivity.dart';
import 'package:dope/features/settings/models/click_wheel_size.dart';
import 'package:dope/features/settings/models/custom_device_theme.dart';
import 'package:dope/features/settings/models/device_color.dart';
import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:dope/features/settings/models/repeat_mode.dart';
import 'package:dope/features/settings/models/song_sort_order.dart';
import 'package:dope/features/settings/models/song_transition_style.dart';
import 'package:dope/features/settings/models/volume_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final settingsPreferencesRepositoryProvider =
    Provider.autoDispose<SettingsPreferencesRepository>((ref) {
      return SettingsPreferencesRepository(
        ref.read(sharedPreferencesWithCacheProvider).requireValue,
      );
    });

class SettingsPreferencesRepository {
  final SharedPreferencesWithCache _sharedPreferencesWithCache;

  SettingsPreferencesRepository(this._sharedPreferencesWithCache);

  String getLanguageLocaleCode() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.languageLocaleCode.name,
        ) ??
        Constants.defaultLanguageLocaleCode;
  }

  String getDeviceColor() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.deviceColor.name,
        ) ??
        DeviceColor.silver.name;
  }

  List<CustomDeviceTheme> getCustomDeviceThemes() {
    final rawThemes = _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.customDeviceThemes.name,
        ) ??
        '[]';
    try {
      final decoded = jsonDecode(rawThemes);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map((theme) => CustomDeviceTheme.fromJson(
                Map<String, dynamic>.from(theme),
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  String? getActiveCustomDeviceThemeId() {
    final rawId = _sharedPreferencesWithCache.getString(
      SharedPreferencesKeys.activeCustomDeviceThemeId.name,
    );
    if (rawId == null || rawId.isEmpty) {
      return null;
    }
    return rawId;
  }

  String getClickWheelSize() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.clickWheelSize.name,
        ) ??
        ClickWheelSize.medium.name;
  }

  String getClickWheelSensitivity() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.clickWheelSensitivity.name,
        ) ??
        ClickWheelSensitivity.medium.name;
  }

  bool getTouchScreenEnabled() {
    return _sharedPreferencesWithCache.getBool(
          SharedPreferencesKeys.isTouchScreenEnabled.name,
        ) ??
        true;
  }

  String getRepeatMode() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.repeatMode.name,
        ) ??
        RepeatMode.off.name;
  }

  bool getVibrate() {
    return _sharedPreferencesWithCache.getBool(
          SharedPreferencesKeys.vibrate.name,
        ) ??
        true;
  }

  bool getSplitScreenEnabled() {
    return _sharedPreferencesWithCache.getBool(
          SharedPreferencesKeys.splitScreenEnabled.name,
        ) ??
        true;
  }

  bool getClickWheelSound() {
    return _sharedPreferencesWithCache.getBool(
          SharedPreferencesKeys.clickWheelSound.name,
        ) ??
        false;
  }

  String getVolumeMode() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.volumeMode.name,
        ) ??
        VolumeMode.app.name;
  }

  String getEqualizerPreset() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.equalizerPreset.name,
        ) ??
        EqualizerPreset.off.name;
  }

  String getSongSortOrder() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.songSortOrder.name,
        ) ??
        SongSortOrder.title.name;
  }

  String getSongTransitionStyle() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.songTransitionStyle.name,
        ) ??
        SongTransitionStyle.off.name;
  }

  int getCrossfadeDurationSeconds() {
    final seconds = _sharedPreferencesWithCache.getInt(
          SharedPreferencesKeys.crossfadeDurationSeconds.name,
        ) ??
        defaultCrossfadeDurationSeconds;
    return normalizedCrossfadeDurationSeconds(seconds);
  }

  String getAppTheme() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.appTheme.name,
        ) ??
        AppTheme.light.name;
  }

  String getTextSize() {
    return _sharedPreferencesWithCache.getString(
          SharedPreferencesKeys.textSize.name,
        ) ??
        AppTextSize.medium.name;
  }

  bool getImmersiveMode() {
    return _sharedPreferencesWithCache.getBool(
          SharedPreferencesKeys.immersiveMode.name,
        ) ??
        false;
  }

  bool getUseColorTextures() {
    return _sharedPreferencesWithCache.getBool(
          SharedPreferencesKeys.useColorTextures.name,
        ) ??
        true;
  }

  Future<void> setLanguageLocaleCode({
    required String languageLocaleCode,
  }) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.languageLocaleCode.name,
      languageLocaleCode,
    );
  }

  Future<void> setDeviceColor({required String deviceColorName}) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.deviceColor.name,
      deviceColorName,
    );
  }

  Future<void> setCustomDeviceThemes({
    required List<CustomDeviceTheme> customThemes,
  }) async {
    final encoded = jsonEncode(
      customThemes.map((theme) => theme.toJson()).toList(growable: false),
    );
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.customDeviceThemes.name,
      encoded,
    );
  }

  Future<void> setActiveCustomDeviceThemeId(String? themeId) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.activeCustomDeviceThemeId.name,
      themeId ?? '',
    );
  }

  Future<void> setClickWheelSize({required String clickWheelSizeName}) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.clickWheelSize.name,
      clickWheelSizeName,
    );
  }

  Future<void> setClickWheelSensitivity({
    required String clickWheelSensitivityName,
  }) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.clickWheelSensitivity.name,
      clickWheelSensitivityName,
    );
  }

  Future<void> setTouchScreenEnabled({
    required bool isTouchScreenEnabled,
  }) async {
    return _sharedPreferencesWithCache.setBool(
      SharedPreferencesKeys.isTouchScreenEnabled.name,
      isTouchScreenEnabled,
    );
  }

  Future<void> setRepeatMode({required String repeatModeName}) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.repeatMode.name,
      repeatModeName,
    );
  }

  Future<void> setVibrate({required bool isVibrateEnabled}) async {
    return _sharedPreferencesWithCache.setBool(
      SharedPreferencesKeys.vibrate.name,
      isVibrateEnabled,
    );
  }

  Future<void> setClickWheelSound({
    required bool isClickWheelSoundEnabled,
  }) async {
    return _sharedPreferencesWithCache.setBool(
      SharedPreferencesKeys.clickWheelSound.name,
      isClickWheelSoundEnabled,
    );
  }

  Future<void> setVolumeMode({required String volumeModeName}) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.volumeMode.name,
      volumeModeName,
    );
  }

  Future<void> setEqualizerPreset({required String equalizerPresetName}) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.equalizerPreset.name,
      equalizerPresetName,
    );
  }

  Future<void> setSongSortOrder({required String songSortOrderName}) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.songSortOrder.name,
      songSortOrderName,
    );
  }

  Future<void> setSongTransitionStyle({
    required String songTransitionStyleName,
  }) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.songTransitionStyle.name,
      songTransitionStyleName,
    );
  }

  Future<void> setCrossfadeDurationSeconds({required int seconds}) async {
    return _sharedPreferencesWithCache.setInt(
      SharedPreferencesKeys.crossfadeDurationSeconds.name,
      normalizedCrossfadeDurationSeconds(seconds),
    );
  }

  Future<void> setAppTheme({required String appThemeName}) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.appTheme.name,
      appThemeName,
    );
  }

  Future<void> setTextSize({required String textSizeName}) async {
    return _sharedPreferencesWithCache.setString(
      SharedPreferencesKeys.textSize.name,
      textSizeName,
    );
  }

  Future<void> setSplitScreenEnabled({
    required bool isSplitScreenEnabled,
  }) async {
    return _sharedPreferencesWithCache.setBool(
      SharedPreferencesKeys.splitScreenEnabled.name,
      isSplitScreenEnabled,
    );
  }

  Future<void> setImmersiveMode({required bool isImmersiveModeEnabled}) async {
    return _sharedPreferencesWithCache.setBool(
      SharedPreferencesKeys.immersiveMode.name,
      isImmersiveModeEnabled,
    );
  }

  Future<void> setUseColorTextures({
    required bool isUseColorTexturesEnabled,
  }) async {
    return _sharedPreferencesWithCache.setBool(
      SharedPreferencesKeys.useColorTextures.name,
      isUseColorTexturesEnabled,
    );
  }
}
