import 'package:classipod/core/constants/constants.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceScreen extends ConsumerWidget {
  final Widget child;

  const DeviceScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTouchScreenEnabled = ref.watch(
      settingsPreferencesControllerProvider.select(
        (e) => e.isTouchScreenEnabled,
      ),
    );

    final size = MediaQuery.sizeOf(context);
    final screenRadius = BorderRadius.circular(18);

    return AbsorbPointer(
      absorbing: !isTouchScreenEnabled,
      child: SizedBox(
        height: Constants.screenHeight + 10,
        width: double.infinity,
        child: LiquidGlass(
          borderRadius: screenRadius,
          blur: 14,
          opacity: 0.34,
          borderColor: CupertinoColors.white.withValues(alpha: 0.48),
          gradientColors: [
            CupertinoColors.white.withValues(alpha: 0.42),
            context.appDeviceScreenBackgroundColor.withValues(alpha: 0.92),
            const Color(0xFF081015).withValues(alpha: 0.18),
          ],
          shadows: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: const Color(0xFF4FFFF1).withValues(alpha: 0.2),
              blurRadius: 18,
            ),
          ],
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: screenRadius,
                  color: context.appDeviceScreenBackgroundColor,
                ),
              ),
              MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(size.width - 50, Constants.screenHeight),
                ),
                child: child,
              ),
              Positioned.fill(
                child: LiquidReflectionOverlay(
                  borderRadius: screenRadius,
                  opacity: 0.24,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: screenRadius,
                  border: Border.all(color: context.appDeviceScreenBorderColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
