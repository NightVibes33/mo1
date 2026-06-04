import 'package:classipod/core/constants/constants.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceScreen extends ConsumerWidget {
  final Widget child;
  final double? height;

  const DeviceScreen({super.key, required this.child, this.height});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTouchScreenEnabled = ref.watch(
      settingsPreferencesControllerProvider.select(
        (e) => e.isTouchScreenEnabled,
      ),
    );

    final screenHeight = height ?? Constants.screenHeight + 10;
    final screenRadius = BorderRadius.circular(18);

    return AbsorbPointer(
      absorbing: !isTouchScreenEnabled,
      child: SizedBox(
        height: screenHeight,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return LiquidGlass(
              borderRadius: screenRadius,
              blur: 8,
              opacity: 0.18,
              borderColor: CupertinoColors.black.withValues(alpha: 0.72),
              gradientColors: [
                CupertinoColors.white.withValues(alpha: 0.24),
                context.appDeviceScreenBackgroundColor.withValues(alpha: 0.98),
                const Color(0xFFBEC6BE).withValues(alpha: 0.1),
              ],
              shadows: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: screenRadius,
                      color: context.appDeviceScreenBackgroundColor,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          CupertinoColors.white.withValues(alpha: 0.92),
                          context.appDeviceScreenBackgroundColor,
                          const Color(0xFFF4F5EE).withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                  ),
                  MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(constraints.maxWidth, screenHeight - 10),
                      textScaler: TextScaler.noScaling,
                    ),
                    child: child,
                  ),
                  Positioned.fill(
                    child: LiquidReflectionOverlay(
                      borderRadius: screenRadius,
                      opacity: 0.16,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: screenRadius,
                      border: Border.all(
                        color: context.appDeviceScreenBorderColor.withValues(alpha: 0.9),
                        width: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
