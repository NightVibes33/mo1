import 'dart:math';

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
      CupertinoColors.white.withValues(
        alpha: deviceColorStyle.isDark ? 0.12 : 0.46,
      ),
      deviceColorStyle.frameGradientColors.last.withValues(alpha: 0.78),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = min(constraints.maxWidth, constraints.maxHeight);
        final bodyMaxWidth = shortestSide < 520
            ? constraints.maxWidth
            : min(constraints.maxWidth, 620.0);
        final safeHeight = constraints.maxHeight;
        final screenHeight = (safeHeight * 0.34).clamp(310.0, 390.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedAuroraBackdrop(
              colors: [
                deviceColorStyle.frameGradientColors.first,
                const Color(0xFFEFEAFF),
                const Color(0xFFFF4FD8),
                deviceColorStyle.frameGradientColors.last,
              ],
              intensity: deviceColorStyle.isDark ? 0.72 : 0.58,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: const AssetImage(Assets.noiseImage),
                  fit: BoxFit.cover,
                  opacity: deviceColorStyle.noiseOpacity * 0.3,
                ),
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Center(
                child: SizedBox(
                  width: bodyMaxWidth,
                  height: double.infinity,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.scale(
                          scale: 0.985 + value * 0.015,
                          child: child,
                        ),
                      );
                    },
                    child: LiquidGlass(
                      borderRadius: bodyRadius,
                      blur: 22,
                      opacity: 0.5,
                      borderColor: CupertinoColors.white.withValues(alpha: 0.42),
                      gradientColors: glassColors,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                      shadows: [
                        BoxShadow(
                          color: CupertinoColors.black.withValues(alpha: 0.28),
                          blurRadius: 32,
                          offset: const Offset(0, 20),
                        ),
                      ],
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: LiquidReflectionOverlay(
                              borderRadius: bodyRadius,
                              opacity: deviceColorStyle.isDark ? 0.54 : 0.7,
                            ),
                          ),
                          Column(
                            children: [
                              DeviceScreen(
                                key: deviceScreenGlobalKey,
                                height: screenHeight,
                                child: child,
                              ),
                              const Spacer(),
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
      },
    );
  }
}
