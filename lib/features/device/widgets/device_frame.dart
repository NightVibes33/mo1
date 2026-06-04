import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/constants/keys.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/features/device/widgets/device_controls.dart';
import 'package:classipod/features/device/widgets/device_screen.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:classipod/features/settings/models/device_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceFrame extends ConsumerWidget {
  final Widget child;

  const DeviceFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeviceColor deviceColor = ref.watch(
      settingsPreferencesControllerProvider.select((e) => e.deviceColor),
    );
    final deviceColorStyle = deviceColor.style;
    final bodyRadius = BorderRadius.circular(44);
    final glassColors = [
      deviceColorStyle.frameGradientColors.first.withValues(alpha: 0.72),
      CupertinoColors.white.withValues(alpha: deviceColorStyle.isDark ? 0.12 : 0.46),
      deviceColorStyle.frameGradientColors.last.withValues(alpha: 0.78),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedAuroraBackdrop(
          colors: [
            deviceColorStyle.frameGradientColors.first,
            const Color(0xFF54FFE2),
            const Color(0xFFFF4FD8),
            deviceColorStyle.frameGradientColors.last,
          ],
          intensity: deviceColorStyle.isDark ? 1.12 : 0.82,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: const AssetImage(Assets.noiseImage),
              fit: BoxFit.cover,
              opacity: deviceColorStyle.noiseOpacity * 0.36,
            ),
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 960, maxWidth: 462),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 760),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.975 + value * 0.025,
                      child: child,
                    ),
                  );
                },
                child: LiquidGlass(
                  borderRadius: bodyRadius,
                  blur: 24,
                  opacity: 0.5,
                  borderColor: CupertinoColors.white.withValues(alpha: 0.42),
                  gradientColors: glassColors,
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
                  shadows: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.34),
                      blurRadius: 42,
                      offset: const Offset(0, 28),
                    ),
                    BoxShadow(
                      color: const Color(0xFF53FFE3).withValues(alpha: 0.14),
                      blurRadius: 30,
                      spreadRadius: 1,
                    ),
                  ],
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LiquidReflectionOverlay(
                          borderRadius: bodyRadius,
                          opacity: deviceColorStyle.isDark ? 0.72 : 0.92,
                        ),
                      ),
                      Column(
                        children: [
                          DeviceScreen(
                            key: deviceScreenGlobalKey,
                            child: child,
                          ),
                          const Spacer(flex: 2),
                          DeviceControls(key: deviceControlsGlobalKey),
                          const Spacer(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
