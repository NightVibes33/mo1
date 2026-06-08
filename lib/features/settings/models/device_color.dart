import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:flutter/cupertino.dart';

@immutable
class DeviceColorStyle {
  final double noiseOpacity;
  final List<Color> frameGradientColors;
  final Color controlBackgroundColor;
  final Color controlBorderColor;
  final List<Color> innerButtonGradientColors;
  final Color buttonAccentColor;
  final Color buttonIconColor;
  final bool isDark;
  final List<Color> frameHighlightColors;
  final bool animateFrameHighlights;

  const DeviceColorStyle({
    required this.noiseOpacity,
    required this.frameGradientColors,
    required this.controlBackgroundColor,
    required this.controlBorderColor,
    required this.innerButtonGradientColors,
    required this.buttonAccentColor,
    required this.buttonIconColor,
    required this.isDark,
    this.frameHighlightColors = const [],
    this.animateFrameHighlights = false,
  });
}

enum DeviceColor {
  silver,
  white,
  starlight,
  auroraIce,
  black,
  graphite,
  midnight,
  red,
  orange,
  yellow,
  gold,
  roseGold,
  lime,
  green,
  teal,
  cyan,
  blue,
  pink,
  magenta,
  purple,
  brown;

  static DeviceColor fromName(String raw) {
    switch (raw) {
      case 'white':
        return DeviceColor.white;
      case 'starlight':
      case 'cream':
        return DeviceColor.starlight;
      case 'aurora':
      case 'auroraIce':
      case 'ice':
      case 'pearl':
        return DeviceColor.auroraIce;
      case 'spaceGray':
      case 'spaceGrey':
      case 'graphite':
        return DeviceColor.graphite;
      case 'midnight':
      case 'midnightBlue':
        return DeviceColor.midnight;
      case 'rose':
      case 'roseGold':
        return DeviceColor.roseGold;
      case 'teal':
        return DeviceColor.teal;
      case 'cyan':
      case 'aqua':
        return DeviceColor.cyan;
      case 'magenta':
        return DeviceColor.magenta;
      case 'lightRed':
      case 'darkRed':
      case 'red':
        return DeviceColor.red;
      case 'gold':
        return DeviceColor.gold;
      case 'lime':
      case 'lightGreen':
        return DeviceColor.lime;
      case 'green':
      case 'darkGreen':
        return DeviceColor.green;
      case 'blue':
      case 'lightBlue':
      case 'darkBlue':
        return DeviceColor.blue;
      case 'violet':
        return DeviceColor.purple;
      default:
        try {
          return DeviceColor.values.byName(raw);
        } catch (_) {
          return DeviceColor.silver;
        }
    }
  }

  String title(BuildContext context) {
    switch (this) {
      case silver:
        return context.localization.silverDeviceColor;
      case white:
        return context.localization.whiteDeviceColor;
      case starlight:
        return context.localization.starlightDeviceColor;
      case auroraIce:
        return context.localization.auroraIceDeviceColor;
      case black:
        return context.localization.blackDeviceColor;
      case graphite:
        return context.localization.graphiteDeviceColor;
      case midnight:
        return context.localization.midnightDeviceColor;
      case red:
        return context.localization.redDeviceColor;
      case orange:
        return context.localization.orangeDeviceColor;
      case yellow:
        return context.localization.yellowDeviceColor;
      case gold:
        return context.localization.goldDeviceColor;
      case roseGold:
        return context.localization.roseGoldDeviceColor;
      case lime:
        return context.localization.limeDeviceColor;
      case green:
        return context.localization.greenDeviceColor;
      case teal:
        return context.localization.tealDeviceColor;
      case cyan:
        return context.localization.cyanDeviceColor;
      case blue:
        return context.localization.blueDeviceColor;
      case pink:
        return context.localization.pinkDeviceColor;
      case magenta:
        return context.localization.magentaDeviceColor;
      case purple:
        return context.localization.purpleDeviceColor;
      case brown:
        return context.localization.brownDeviceColor;
    }
  }

  DeviceColorStyle get style {
    switch (this) {
      case DeviceColor.silver:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.lightDeviceFrameGradientColor1,
            AppPalette.lightDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: CupertinoColors.white,
          controlBorderColor: AppPalette.lightDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.lightDeviceControlInnerButtonGradientColor1,
            AppPalette.lightDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.lightDeviceButtonColor,
          buttonIconColor: AppPalette.lightDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.white:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.whiteDeviceFrameGradientColor1,
            AppPalette.whiteDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: CupertinoColors.white,
          controlBorderColor: AppPalette.whiteDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.whiteDeviceControlInnerButtonGradientColor1,
            AppPalette.whiteDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.whiteDeviceButtonColor,
          buttonIconColor: AppPalette.whiteDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.starlight:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.starlightDeviceFrameGradientColor1,
            AppPalette.starlightDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: CupertinoColors.white,
          controlBorderColor: AppPalette.starlightDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.starlightDeviceControlInnerButtonGradientColor1,
            AppPalette.starlightDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.starlightDeviceButtonColor,
          buttonIconColor: AppPalette.starlightDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.auroraIce:
        return const DeviceColorStyle(
          noiseOpacity: 0.42,
          frameGradientColors: [
            AppPalette.auroraIceDeviceFrameGradientColor1,
            AppPalette.auroraIceDeviceFrameGradientColor2,
          ],
          frameHighlightColors: [
            AppPalette.auroraIceDeviceFrameHighlightColor1,
            AppPalette.auroraIceDeviceFrameHighlightColor2,
            AppPalette.auroraIceDeviceFrameHighlightColor3,
          ],
          animateFrameHighlights: true,
          controlBackgroundColor:
              AppPalette.auroraIceDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.auroraIceDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.auroraIceDeviceControlInnerButtonGradientColor1,
            AppPalette.auroraIceDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.auroraIceDeviceButtonColor,
          buttonIconColor: AppPalette.auroraIceDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.black:
        return const DeviceColorStyle(
          noiseOpacity: 0.3,
          frameGradientColors: [
            AppPalette.darkDeviceFrameGradientColor1,
            AppPalette.darkDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.darkDeviceControlBackgroundColor,
          controlBorderColor: CupertinoColors.black,
          innerButtonGradientColors: [
            AppPalette.darkDeviceControlInnerButtonGradientColor1,
            AppPalette.darkDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: CupertinoColors.white,
          buttonIconColor: CupertinoColors.white,
          isDark: true,
        );
      case DeviceColor.graphite:
        return const DeviceColorStyle(
          noiseOpacity: 0.45,
          frameGradientColors: [
            AppPalette.graphiteDeviceFrameGradientColor1,
            AppPalette.graphiteDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.graphiteDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.graphiteDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.graphiteDeviceControlInnerButtonGradientColor1,
            AppPalette.graphiteDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: CupertinoColors.white,
          buttonIconColor: CupertinoColors.white,
          isDark: true,
        );
      case DeviceColor.midnight:
        return const DeviceColorStyle(
          noiseOpacity: 0.45,
          frameGradientColors: [
            AppPalette.midnightDeviceFrameGradientColor1,
            AppPalette.midnightDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.midnightDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.midnightDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.midnightDeviceControlInnerButtonGradientColor1,
            AppPalette.midnightDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.midnightDeviceButtonAccentColor,
          buttonIconColor: AppPalette.midnightDeviceButtonAccentColor,
          isDark: true,
        );
      case DeviceColor.red:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.redDeviceFrameGradientColor1,
            AppPalette.redDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.redDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.redDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.redDeviceControlInnerButtonGradientColor1,
            AppPalette.redDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.redDeviceButtonAccentColor,
          buttonIconColor: AppPalette.redDeviceButtonAccentColor,
          isDark: false,
        );
      case DeviceColor.orange:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.orangeDeviceFrameGradientColor1,
            AppPalette.orangeDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: CupertinoColors.white,
          controlBorderColor: AppPalette.orangeDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.orangeDeviceControlInnerButtonGradientColor1,
            AppPalette.orangeDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.orangeDeviceButtonColor,
          buttonIconColor: AppPalette.orangeDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.yellow:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.yellowDeviceFrameGradientColor1,
            AppPalette.yellowDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.yellowDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.yellowDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.yellowDeviceControlInnerButtonGradientColor1,
            AppPalette.yellowDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.yellowDeviceButtonColor,
          buttonIconColor: AppPalette.yellowDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.gold:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.goldDeviceFrameGradientColor1,
            AppPalette.goldDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.goldDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.goldDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.goldDeviceControlInnerButtonGradientColor1,
            AppPalette.goldDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.goldDeviceButtonColor,
          buttonIconColor: AppPalette.goldDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.roseGold:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.roseGoldDeviceFrameGradientColor1,
            AppPalette.roseGoldDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: CupertinoColors.white,
          controlBorderColor: AppPalette.roseGoldDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.roseGoldDeviceControlInnerButtonGradientColor1,
            AppPalette.roseGoldDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.roseGoldDeviceButtonColor,
          buttonIconColor: AppPalette.roseGoldDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.lime:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.limeDeviceFrameGradientColor1,
            AppPalette.limeDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: CupertinoColors.white,
          controlBorderColor: AppPalette.limeDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.limeDeviceControlInnerButtonGradientColor1,
            AppPalette.limeDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.limeDeviceButtonColor,
          buttonIconColor: AppPalette.limeDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.green:
        return const DeviceColorStyle(
          noiseOpacity: 0.6,
          frameGradientColors: [
            AppPalette.greenDeviceFrameGradientColor1,
            AppPalette.greenDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.greenDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.greenDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.greenDeviceControlInnerButtonGradientColor1,
            AppPalette.greenDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.greenDeviceButtonAccentColor,
          buttonIconColor: AppPalette.greenDeviceButtonAccentColor,
          isDark: true,
        );
      case DeviceColor.teal:
        return const DeviceColorStyle(
          noiseOpacity: 0.7,
          frameGradientColors: [
            AppPalette.tealDeviceFrameGradientColor1,
            AppPalette.tealDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.tealDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.tealDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.tealDeviceControlInnerButtonGradientColor1,
            AppPalette.tealDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.tealDeviceButtonAccentColor,
          buttonIconColor: AppPalette.tealDeviceButtonAccentColor,
          isDark: true,
        );
      case DeviceColor.cyan:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.cyanDeviceFrameGradientColor1,
            AppPalette.cyanDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: CupertinoColors.white,
          controlBorderColor: AppPalette.cyanDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.cyanDeviceControlInnerButtonGradientColor1,
            AppPalette.cyanDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.cyanDeviceButtonColor,
          buttonIconColor: AppPalette.cyanDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.blue:
        return const DeviceColorStyle(
          noiseOpacity: 0.8,
          frameGradientColors: [
            AppPalette.blueDeviceFrameGradientColor1,
            AppPalette.blueDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.blueDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.blueDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.blueDeviceControlInnerButtonGradientColor1,
            AppPalette.blueDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.blueDeviceButtonAccentColor,
          buttonIconColor: AppPalette.blueDeviceButtonAccentColor,
          isDark: true,
        );
      case DeviceColor.pink:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.pinkDeviceFrameGradientColor1,
            AppPalette.pinkDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: CupertinoColors.white,
          controlBorderColor: AppPalette.pinkDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.pinkDeviceControlInnerButtonGradientColor1,
            AppPalette.pinkDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.pinkDeviceButtonColor,
          buttonIconColor: AppPalette.pinkDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.magenta:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.magentaDeviceFrameGradientColor1,
            AppPalette.magentaDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.magentaDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.magentaDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.magentaDeviceControlInnerButtonGradientColor1,
            AppPalette.magentaDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.magentaDeviceButtonAccentColor,
          buttonIconColor: AppPalette.magentaDeviceButtonAccentColor,
          isDark: false,
        );
      case DeviceColor.purple:
        return const DeviceColorStyle(
          noiseOpacity: 1,
          frameGradientColors: [
            AppPalette.purpleDeviceFrameGradientColor1,
            AppPalette.purpleDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.purpleDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.purpleDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.purpleDeviceControlInnerButtonGradientColor1,
            AppPalette.purpleDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.purpleDeviceButtonColor,
          buttonIconColor: AppPalette.purpleDeviceButtonColor,
          isDark: false,
        );
      case DeviceColor.brown:
        return const DeviceColorStyle(
          noiseOpacity: 0.8,
          frameGradientColors: [
            AppPalette.brownDeviceFrameGradientColor1,
            AppPalette.brownDeviceFrameGradientColor2,
          ],
          controlBackgroundColor: AppPalette.brownDeviceControlBackgroundColor,
          controlBorderColor: AppPalette.brownDeviceControlBorderColor,
          innerButtonGradientColors: [
            AppPalette.brownDeviceControlInnerButtonGradientColor1,
            AppPalette.brownDeviceControlInnerButtonGradientColor2,
          ],
          buttonAccentColor: AppPalette.brownDeviceButtonAccentColor,
          buttonIconColor: AppPalette.brownDeviceButtonAccentColor,
          isDark: true,
        );
    }
  }
}
