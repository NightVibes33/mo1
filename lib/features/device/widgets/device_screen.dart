import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);

        return AbsorbPointer(
          absorbing: !isTouchScreenEnabled,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.appDeviceScreenBackgroundColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: context.appDeviceScreenBorderColor.withValues(alpha: 0.36),
              ),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: viewSize),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
