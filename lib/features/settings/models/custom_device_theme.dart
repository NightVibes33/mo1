import 'package:dopi/features/settings/models/device_color.dart';
import 'package:flutter/cupertino.dart';

@immutable
class CustomDeviceTheme {
  final String id;
  final String name;
  final int primaryColorValue;
  final int secondaryColorValue;

  const CustomDeviceTheme({
    required this.id,
    required this.name,
    required this.primaryColorValue,
    required this.secondaryColorValue,
  });

  Color get primaryColor => Color(primaryColorValue);
  Color get secondaryColor => Color(secondaryColorValue);

  DeviceColorStyle style({bool useColorTextures = true}) {
    final primary = primaryColor;
    final secondary = secondaryColor;
    final baseControlColor = _mix(primary, secondary, 0.46);
    final isDark =
        ((primary.computeLuminance() + secondary.computeLuminance()) / 2) < 0.52;
    final controlBackgroundColor = isDark
        ? _darken(baseControlColor, 0.18)
        : _lighten(baseControlColor, 0.22);
    final controlBorderColor = isDark
        ? _lighten(secondary, 0.18)
        : _darken(secondary, 0.14);
    final buttonAccentColor = isDark
        ? CupertinoColors.white
        : _darken(secondary, 0.34);
    final buttonIconColor = isDark
        ? CupertinoColors.white
        : _darken(secondary, 0.42);

    return DeviceColorStyle(
      noiseOpacity: useColorTextures ? 0.34 : 0.18,
      frameGradientColors: useColorTextures
          ? [
              _lighten(primary, 0.18),
              _darken(secondary, 0.08),
            ]
          : [primary, primary],
      controlBackgroundColor: controlBackgroundColor,
      controlBorderColor: controlBorderColor,
      innerButtonGradientColors: useColorTextures
          ? [
              _lighten(primary, 0.24),
              _mix(primary, secondary, 0.74),
            ]
          : [controlBackgroundColor, controlBackgroundColor],
      buttonAccentColor: buttonAccentColor,
      buttonIconColor: buttonIconColor,
      isDark: isDark,
      frameHighlightColors: const [],
      animateFrameHighlights: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'primaryColorValue': primaryColorValue,
      'secondaryColorValue': secondaryColorValue,
    };
  }

  factory CustomDeviceTheme.fromJson(Map<String, dynamic> json) {
    return CustomDeviceTheme(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Custom',
      primaryColorValue: json['primaryColorValue'] as int? ?? 0xFFFFFFFF,
      secondaryColorValue: json['secondaryColorValue'] as int? ?? 0xFF000000,
    );
  }

  CustomDeviceTheme copyWith({
    String? id,
    String? name,
    int? primaryColorValue,
    int? secondaryColorValue,
  }) {
    return CustomDeviceTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      primaryColorValue: primaryColorValue ?? this.primaryColorValue,
      secondaryColorValue: secondaryColorValue ?? this.secondaryColorValue,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CustomDeviceTheme &&
        other.id == id &&
        other.name == name &&
        other.primaryColorValue == primaryColorValue &&
        other.secondaryColorValue == secondaryColorValue;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    primaryColorValue,
    secondaryColorValue,
  );

  static Color _mix(Color a, Color b, double amount) {
    return Color.lerp(a, b, amount.clamp(0, 1)) ?? a;
  }

  static Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  static Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}
