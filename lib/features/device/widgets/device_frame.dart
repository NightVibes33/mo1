import 'package:dopi/core/constants/assets.dart';
import 'package:dopi/core/constants/keys.dart';
import 'package:dopi/features/device/widgets/device_controls.dart';
import 'package:dopi/features/device/widgets/device_screen.dart';
import 'package:dopi/features/settings/controller/settings_preferences_controller.dart';
import 'package:dopi/features/settings/models/wheel_style.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceFrame extends ConsumerWidget {
  final Widget child;

  const DeviceFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsPreferencesControllerProvider);
    final deviceColorStyle = settings.resolveDeviceColorStyle();
    final wheelStyle = settings.wheelStyle;
    final shellColors = [
      deviceColorStyle.frameGradientColors.first.withValues(alpha: 0.96),
      deviceColorStyle.frameGradientColors.last.withValues(alpha: 0.98),
    ];

    Widget controls = Center(child: DeviceControls(key: deviceControlsGlobalKey));

    if (wheelStyle == WheelStyle.modern) {
      controls = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: deviceColorStyle.isDark
              ? CupertinoColors.black.withValues(alpha: 0.24)
              : CupertinoColors.white.withValues(alpha: 0.18),
          border: Border.all(
            color: deviceColorStyle.isDark
                ? CupertinoColors.white.withValues(alpha: 0.10)
                : CupertinoColors.black.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
          child: controls,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage(Assets.noiseImage),
          fit: BoxFit.cover,
          opacity: deviceColorStyle.noiseOpacity * 0.55,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: shellColors,
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(
                  child: DeviceScreen(
                    key: deviceScreenGlobalKey,
                    child: child,
                  ),
                ),
                const SizedBox(height: 14),
                controls,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
