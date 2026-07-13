import 'package:dope/features/settings/models/app_text_size.dart';
import 'package:dope/features/settings/models/app_theme.dart';
import 'package:dope/features/settings/models/click_wheel_sensitivity.dart';
import 'package:dope/features/settings/models/click_wheel_size.dart';
import 'package:dope/features/settings/models/custom_device_theme.dart';
import 'package:dope/features/settings/models/custom_equalizer_preset.dart';
import 'package:dope/features/settings/models/device_color.dart';
import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:dope/features/settings/models/repeat_mode.dart';
import 'package:dope/features/settings/models/song_sort_order.dart';
import 'package:dope/features/settings/models/song_transition_style.dart';
import 'package:dope/features/settings/models/volume_mode.dart';
import 'package:dope/features/settings/models/wheel_style.dart';
import 'package:flutter/foundation.dart';

class SettingsPreferencesModel {
  final String languageLocaleCode;
  final DeviceColor deviceColor;
  final List<CustomDeviceTheme> customDeviceThemes;
  final String? activeCustomDeviceThemeId;
  final ClickWheelSize clickWheelSize;
  final ClickWheelSensitivity clickWheelSensitivity;
  final bool isTouchScreenEnabled;
  final RepeatMode repeatMode;
  final bool vibrate;
  final bool clickWheelSound;
  final VolumeMode volumeMode;
  final EqualizerPreset equalizerPreset;
  final List<CustomEqualizerPreset> customEqualizerPresets;
  final String? activeCustomEqualizerPresetId;
  final SongSortOrder songSortOrder;
  final SongTransitionStyle songTransitionStyle;
  final int crossfadeDurationSeconds;
  final AppTextSize appTextSize;
  final bool splitScreenEnabled;
  final bool immersiveMode;
  final bool useColorTextures;
  final bool fetchOnlineMusic;
  final AppTheme appTheme;
  final WheelStyle wheelStyle;

  SettingsPreferencesModel({
    required this.languageLocaleCode,
    required this.deviceColor,
    required this.customDeviceThemes,
    required this.activeCustomDeviceThemeId,
    required this.clickWheelSize,
    required this.clickWheelSensitivity,
    required this.isTouchScreenEnabled,
    required this.repeatMode,
    required this.vibrate,
    required this.clickWheelSound,
    required this.volumeMode,
    required this.equalizerPreset,
    required this.customEqualizerPresets,
    required this.activeCustomEqualizerPresetId,
    required this.songSortOrder,
    required this.songTransitionStyle,
    required this.crossfadeDurationSeconds,
    required this.appTextSize,
    required this.splitScreenEnabled,
    required this.immersiveMode,
    required this.useColorTextures,
    required this.appTheme,
    required this.wheelStyle,
    this.fetchOnlineMusic = false,
  });

  CustomDeviceTheme? get activeCustomDeviceTheme {
    if (activeCustomDeviceThemeId == null ||
        activeCustomDeviceThemeId!.isEmpty) {
      return null;
    }
    for (final theme in customDeviceThemes) {
      if (theme.id == activeCustomDeviceThemeId) {
        return theme;
      }
    }
    return null;
  }

  bool get isUsingCustomDeviceTheme => activeCustomDeviceTheme != null;

  CustomEqualizerPreset? get activeCustomEqualizerPreset {
    if (activeCustomEqualizerPresetId == null ||
        activeCustomEqualizerPresetId!.isEmpty) {
      return null;
    }
    for (final preset in customEqualizerPresets) {
      if (preset.id == activeCustomEqualizerPresetId) {
        return preset;
      }
    }
    return null;
  }

  bool get isUsingCustomEqualizerPreset => activeCustomEqualizerPreset != null;

  List<double> get activeEqualizerBandGainsDb =>
      activeCustomEqualizerPreset?.bandGainsDb ??
      equalizerPreset.approximateBandGainsDb;

  bool get activeEqualizerHasNeutralCurve =>
      activeEqualizerBandGainsDb.every((gain) => gain == 0);

  String get equalizerDisplayTitle =>
      activeCustomEqualizerPreset?.name ?? equalizerPreset.title;

  DeviceColorStyle resolveDeviceColorStyle() {
    final customTheme = activeCustomDeviceTheme;
    if (customTheme != null) {
      return customTheme.style(useColorTextures: useColorTextures);
    }
    return deviceColor.style(useColorTextures: useColorTextures);
  }

  SettingsPreferencesModel copyWith({
    String? languageLocaleCode,
    DeviceColor? deviceColor,
    List<CustomDeviceTheme>? customDeviceThemes,
    String? activeCustomDeviceThemeId,
    bool clearActiveCustomDeviceThemeId = false,
    ClickWheelSize? clickWheelSize,
    ClickWheelSensitivity? clickWheelSensitivity,
    bool? isTouchScreenEnabled,
    RepeatMode? repeatMode,
    bool? vibrate,
    bool? clickWheelSound,
    VolumeMode? volumeMode,
    EqualizerPreset? equalizerPreset,
    List<CustomEqualizerPreset>? customEqualizerPresets,
    String? activeCustomEqualizerPresetId,
    bool clearActiveCustomEqualizerPresetId = false,
    SongSortOrder? songSortOrder,
    SongTransitionStyle? songTransitionStyle,
    int? crossfadeDurationSeconds,
    AppTextSize? appTextSize,
    bool? splitScreenEnabled,
    bool? immersiveMode,
    bool? useColorTextures,
    bool? fetchOnlineMusic,
    AppTheme? appTheme,
    WheelStyle? wheelStyle,
  }) {
    return SettingsPreferencesModel(
      languageLocaleCode: languageLocaleCode ?? this.languageLocaleCode,
      deviceColor: deviceColor ?? this.deviceColor,
      customDeviceThemes: customDeviceThemes ?? this.customDeviceThemes,
      activeCustomDeviceThemeId: clearActiveCustomDeviceThemeId
          ? null
          : activeCustomDeviceThemeId ?? this.activeCustomDeviceThemeId,
      clickWheelSize: clickWheelSize ?? this.clickWheelSize,
      clickWheelSensitivity:
          clickWheelSensitivity ?? this.clickWheelSensitivity,
      isTouchScreenEnabled: isTouchScreenEnabled ?? this.isTouchScreenEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      vibrate: vibrate ?? this.vibrate,
      clickWheelSound: clickWheelSound ?? this.clickWheelSound,
      volumeMode: volumeMode ?? this.volumeMode,
      equalizerPreset: equalizerPreset ?? this.equalizerPreset,
      customEqualizerPresets:
          customEqualizerPresets ?? this.customEqualizerPresets,
      activeCustomEqualizerPresetId: clearActiveCustomEqualizerPresetId
          ? null
          : activeCustomEqualizerPresetId ?? this.activeCustomEqualizerPresetId,
      songSortOrder: songSortOrder ?? this.songSortOrder,
      songTransitionStyle: songTransitionStyle ?? this.songTransitionStyle,
      crossfadeDurationSeconds:
          crossfadeDurationSeconds ?? this.crossfadeDurationSeconds,
      appTextSize: appTextSize ?? this.appTextSize,
      splitScreenEnabled: splitScreenEnabled ?? this.splitScreenEnabled,
      immersiveMode: immersiveMode ?? this.immersiveMode,
      useColorTextures: useColorTextures ?? this.useColorTextures,
      appTheme: appTheme ?? this.appTheme,
      wheelStyle: wheelStyle ?? this.wheelStyle,
      fetchOnlineMusic: fetchOnlineMusic ?? this.fetchOnlineMusic,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SettingsPreferencesModel &&
        other.languageLocaleCode == languageLocaleCode &&
        other.deviceColor == deviceColor &&
        listEquals(other.customDeviceThemes, customDeviceThemes) &&
        other.activeCustomDeviceThemeId == activeCustomDeviceThemeId &&
        other.clickWheelSize == clickWheelSize &&
        other.clickWheelSensitivity == clickWheelSensitivity &&
        other.isTouchScreenEnabled == isTouchScreenEnabled &&
        other.repeatMode == repeatMode &&
        other.vibrate == vibrate &&
        other.clickWheelSound == clickWheelSound &&
        other.volumeMode == volumeMode &&
        other.equalizerPreset == equalizerPreset &&
        listEquals(other.customEqualizerPresets, customEqualizerPresets) &&
        other.activeCustomEqualizerPresetId == activeCustomEqualizerPresetId &&
        other.songSortOrder == songSortOrder &&
        other.songTransitionStyle == songTransitionStyle &&
        other.crossfadeDurationSeconds == crossfadeDurationSeconds &&
        other.appTextSize == appTextSize &&
        other.splitScreenEnabled == splitScreenEnabled &&
        other.immersiveMode == immersiveMode &&
        other.useColorTextures == useColorTextures &&
        other.fetchOnlineMusic == fetchOnlineMusic &&
        other.appTheme == appTheme &&
        other.wheelStyle == wheelStyle;
  }

  @override
  int get hashCode => Object.hashAll([
    languageLocaleCode,
    deviceColor,
    Object.hashAll(customDeviceThemes),
    activeCustomDeviceThemeId,
    clickWheelSize,
    clickWheelSensitivity,
    isTouchScreenEnabled,
    repeatMode,
    vibrate,
    clickWheelSound,
    volumeMode,
    equalizerPreset,
    Object.hashAll(customEqualizerPresets),
    activeCustomEqualizerPresetId,
    songSortOrder,
    songTransitionStyle,
    crossfadeDurationSeconds,
    appTextSize,
    splitScreenEnabled,
    immersiveMode,
    useColorTextures,
    appTheme,
    wheelStyle,
    fetchOnlineMusic,
  ]);
}
