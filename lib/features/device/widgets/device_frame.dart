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
    final mediaQuery = MediaQuery.of(context);
    final glassColors = [
      deviceColorStyle.frameGradientColors.first.withValues(alpha: 0.86),
      CupertinoColors.white.withValues(
        alpha: deviceColorStyle.isDark ? 0.1 : 0.5,
      ),
      deviceColorStyle.frameGradientColors.last.withValues(alpha: 0.9),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final topInset = mediaQuery.padding.top;
        final bottomInset = mediaQuery.padding.bottom;
        final horizontalInset = constraints.maxWidth < 430 ? 3.0 : 10.0;
        final topGap = max(18.0, min(topInset * 0.62, 38.0));
        final bottomGap = max(5.0, bottomInset * 0.25);
        final availableWidth = max(
          0.0,
          constraints.maxWidth - horizontalInset * 2,
        );
        final availableHeight = max(
          0.0,
          constraints.maxHeight - topGap - bottomGap,
        );
        const bodyAspectRatio = 1.98;
        var bodyWidth = min(availableWidth, 620.0);
        var bodyHeight = bodyWidth * bodyAspectRatio;
        if (bodyHeight > availableHeight) {
          bodyHeight = availableHeight;
          bodyWidth = bodyHeight / bodyAspectRatio;
        }
        final bodyRadius = BorderRadius.circular(
          (bodyWidth * 0.12).clamp(36.0, 58.0).toDouble(),
        );
        final innerWidth = max(0.0, bodyWidth - 20);
        final screenHeight = min(
          bodyHeight * 0.30,
          (innerWidth * 0.56).clamp(190.0, 252.0).toDouble(),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedAuroraBackdrop(
              colors: [
                deviceColorStyle.frameGradientColors.first.withValues(alpha: 0.82),
                const Color(0xFFF5F5F0),
                const Color(0xFFC9CED7),
                deviceColorStyle.frameGradientColors.last.withValues(alpha: 0.78),
              ],
              intensity: deviceColorStyle.isDark ? 0.48 : 0.28,
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
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalInset,
                topGap,
                horizontalInset,
                bottomGap,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: bodyWidth,
                  height: bodyHeight,
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
                      opacity: deviceColorStyle.isDark ? 0.42 : 0.58,
                      borderColor: CupertinoColors.white.withValues(alpha: 0.5),
                      gradientColors: glassColors,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
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
                              const Spacer(flex: 18),
                              DeviceControls(key: deviceControlsGlobalKey),
                              const Spacer(flex: 30),
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
