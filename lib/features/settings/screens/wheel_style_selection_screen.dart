import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/device/widgets/wheel_skin_visual.dart';
import 'package:dope/features/settings/models/device_color.dart';
import 'package:dope/features/settings/models/wheel_style.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WheelStyleSelectionScreen extends ConsumerWidget {
  const WheelStyleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsPreferencesControllerProvider);
    final deviceColorStyle = settings.resolveDeviceColorStyle();
    final activeStyle = settings.wheelStyle;

    Future<void> selectStyle(WheelStyle style) async {
      await ref
          .read(settingsPreferencesControllerProvider.notifier)
          .setWheelStyle(style);
    }

    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.wheelStyle.title(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
              children: [
                _WheelStyleCard(
                  title: 'Modern',
                  subtitle: 'Current default wheel',
                  isSelected: activeStyle == WheelStyle.modern,
                  preview: _WheelPreview(
                    wheelStyle: WheelStyle.modern,
                    deviceColorStyle: deviceColorStyle,
                  ),
                  onTap: () => selectStyle(WheelStyle.modern),
                ),
                const SizedBox(height: 14),
                _WheelStyleCard(
                  title: 'Classic',
                  subtitle: 'Circular wheel from the older design',
                  isSelected: activeStyle == WheelStyle.classic,
                  preview: _WheelPreview(
                    wheelStyle: WheelStyle.classic,
                    deviceColorStyle: deviceColorStyle,
                  ),
                  onTap: () => selectStyle(WheelStyle.classic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelStyleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final Widget preview;
  final VoidCallback onTap;

  const _WheelStyleCard({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appSurfaceColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected
                ? context.appPrimaryTextColor.withValues(alpha: 0.22)
                : context.appOutlineColor.withValues(alpha: 0.32),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .navTitleTextStyle
                              .copyWith(
                                fontSize: 20,
                                color: context.appPrimaryTextColor,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: CupertinoTheme.of(context).textTheme.textStyle
                              .copyWith(
                                fontSize: 13,
                                color: context.appSecondaryTextColor,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isSelected
                        ? CupertinoIcons.check_mark_circled_solid
                        : CupertinoIcons.circle,
                    color: isSelected
                        ? context.appPrimaryTextColor
                        : context.appSecondaryTextColor.withValues(alpha: 0.55),
                    size: 24,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(child: preview),
            ],
          ),
        ),
      ),
    );
  }
}

class _WheelPreview extends StatelessWidget {
  final WheelStyle wheelStyle;
  final DeviceColorStyle deviceColorStyle;

  const _WheelPreview({
    required this.wheelStyle,
    required this.deviceColorStyle,
  });

  @override
  Widget build(BuildContext context) {
    return WheelSkinVisual(
      wheelStyle: wheelStyle,
      wheelSize: 170,
      selectButtonSize: 70,
      deviceColorStyle: deviceColorStyle,
    );
  }
}
