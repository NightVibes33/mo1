import 'package:dope/core/services/widget_sync_service.dart';
import 'package:dope/features/settings/models/custom_device_theme.dart';
import 'package:dope/features/settings/models/device_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('widget theme fields follow the resolved device style', () {
    final style = DeviceColor.silver.style();
    final fields = widgetThemeSnapshotFields(style: style);

    expect(
      fields['themePrimaryColor'],
      style.frameGradientColors.first.toARGB32(),
    );
    expect(
      fields['themeSecondaryColor'],
      style.frameGradientColors.last.toARGB32(),
    );
    expect(
      fields['frameGradientStart'],
      style.frameGradientColors.first.toARGB32(),
    );
    expect(
      fields['frameGradientEnd'],
      style.frameGradientColors.last.toARGB32(),
    );
    expect(
      fields['controlBackgroundColor'],
      style.controlBackgroundColor.toARGB32(),
    );
    expect(
      fields['controlBorderColor'],
      style.controlBorderColor.toARGB32(),
    );
    expect(
      fields['innerButtonGradientStart'],
      style.innerButtonGradientColors.first.toARGB32(),
    );
    expect(
      fields['innerButtonGradientEnd'],
      style.innerButtonGradientColors.last.toARGB32(),
    );
    expect(fields['buttonAccentColor'], style.buttonAccentColor.toARGB32());
    expect(fields['buttonIconColor'], style.buttonIconColor.toARGB32());
    expect(fields['themeIsDark'], style.isDark);
    expect(fields['themeIsDark'], isFalse);
  });

  test('custom theme keeps chosen colors beside the derived style', () {
    const theme = CustomDeviceTheme(
      id: 'red',
      name: 'Red',
      primaryColorValue: 0xFFE74954,
      secondaryColorValue: 0xFF7C0015,
    );
    final style = theme.style();
    final fields = widgetThemeSnapshotFields(
      style: style,
      primaryColorValue: theme.primaryColorValue,
      secondaryColorValue: theme.secondaryColorValue,
    );

    expect(fields['themePrimaryColor'], 0xFFE74954);
    expect(fields['themeSecondaryColor'], 0xFF7C0015);
    expect(
      fields['frameGradientStart'],
      style.frameGradientColors.first.toARGB32(),
    );
    expect(
      fields['frameGradientEnd'],
      style.frameGradientColors.last.toARGB32(),
    );
    expect(fields['frameGradientStart'], isNot(0xFFE74954));
    expect(fields['themeIsDark'], style.isDark);
  });

  test('dark preset reports themeIsDark from the device style', () {
    final style = DeviceColor.graphite.style();
    final fields = widgetThemeSnapshotFields(style: style);

    expect(style.isDark, isTrue);
    expect(fields['themeIsDark'], isTrue);
    expect(
      fields['controlBackgroundColor'],
      style.controlBackgroundColor.toARGB32(),
    );
  });
}
