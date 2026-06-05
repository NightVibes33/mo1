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
        final topInset = mediaQuery.viewPadding.top;
        final bottomInset = mediaQuery.viewPadding.bottom;
        final hasDynamicIsland = topInset >= 54;
        final horizontalBleed = constraints.maxWidth < 430 ? 0.0 : 4.0;
        final topContentInset = hasDynamicIsland
            ? topInset + 18
            : max(topInset + 12, 16.0);
        final bottomBleed = max(bottomInset + 72, 86.0);
        final bottomContentInset = max(bottomInset + 8, 12.0);
        final availableWidth = max(
          0.0,
          constraints.maxWidth + horizontalBleed * 2,
        );
        final availableHeight = max(0.0, constraints.maxHeight + bottomBleed);
        const bodyAspectRatio = 1.88;
        var bodyWidth = min(availableWidth, 620.0);
        final idealBodyHeight = bodyWidth * bodyAspectRatio;
        var bodyHeight = availableHeight;
        if (idealBodyHeight > availableHeight && constraints.maxWidth >= 700) {
          bodyWidth = availableHeight / bodyAspectRatio;
        }
        final bodyRadius = BorderRadius.circular(
          (bodyWidth * 0.12).clamp(36.0, 58.0).toDouble(),
        );
        final innerWidth = max(0.0, bodyWidth - 20);
        final contentHeight = max(
          0.0,
          bodyHeight - topContentInset - bottomContentInset,
        );
        final screenHeight = min(
          contentHeight * 0.42,
          (innerWidth * 0.72).clamp(218.0, 316.0).toDouble(),
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
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topContentInset + 56,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        deviceColorStyle.frameGradientColors.first.withValues(
                          alpha: deviceColorStyle.isDark ? 0.32 : 0.18,
                        ),
                        CupertinoColors.white.withValues(
                          alpha: deviceColorStyle.isDark ? 0.08 : 0.42,
                        ),
                        CupertinoColors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: -bottomBleed,
              left: -horizontalBleed,
              right: -horizontalBleed,
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
                      padding: EdgeInsets.fromLTRB(
                        10,
                        topContentInset,
                        10,
                        bottomContentInset,
                      ),
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
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: topContentInset + 22,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.vertical(
                                    top: bodyRadius.topLeft,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      CupertinoColors.white.withValues(
                                        alpha: deviceColorStyle.isDark
                                            ? 0.08
                                            : 0.42,
                                      ),
                                      deviceColorStyle.frameGradientColors.first
                                          .withValues(alpha: 0.16),
                                      CupertinoColors.white.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Column(
                            children: [
                              DeviceScreen(
                                key: deviceScreenGlobalKey,
                                height: screenHeight,
                                child: child,
                              ),
                              Expanded(
                                child: Center(
                                  child: DeviceControls(
                                    key: deviceControlsGlobalKey,
                                  ),
                                ),
                              ),
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
