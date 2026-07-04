import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/features/device/widgets/wheel_skin_visual.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.appBackgroundColor,
                    context.appSurfaceColor.withValues(alpha: 0.86),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    Text(
                      'Choose how the controls look.',
                      style: CupertinoTheme.of(context).textTheme.textStyle
                          .copyWith(
                            fontSize: 15,
                            color: context.appSecondaryTextColor,
                          ),
                    ),
                    const SizedBox(height: 16),
                    _WheelStyleCard(
                      title: 'Modern',
                      subtitle: 'Current default controls dock',
                      isSelected: activeStyle == WheelStyle.modern,
                      preview: _WheelPreview(
                        wheelStyle: WheelStyle.modern,
                        deviceColorStyle: deviceColorStyle,
                      ),
                      onTap: () => selectStyle(WheelStyle.modern),
                    ),
                    const SizedBox(height: 18),
                    _WheelStyleCard(
                      title: 'Classic',
                      subtitle: 'Legacy circular wheel',
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
          color: context.appSurfaceColor.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isSelected
                ? context.appPrimaryTextColor.withValues(alpha: 0.26)
                : context.appOutlineColor.withValues(alpha: 0.28),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                                fontSize: 28,
                                color: context.appPrimaryTextColor,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: CupertinoTheme.of(context).textTheme.textStyle
                              .copyWith(
                                fontSize: 15,
                                color: context.appSecondaryTextColor,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      isSelected
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.circle,
                      color: isSelected
                          ? context.appPrimaryTextColor
                          : context.appSecondaryTextColor.withValues(alpha: 0.55),
                      size: 28,
                    ),
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
    if (wheelStyle == WheelStyle.modern) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
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
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
          child: SizedBox(
            width: 280,
            child: WheelSkinVisual(
              wheelStyle: WheelStyle.modern,
              wheelSize: 200,
              selectButtonSize: 84,
              deviceColorStyle: deviceColorStyle,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 280,
      child: Center(
        child: WheelSkinVisual(
          wheelStyle: WheelStyle.classic,
          wheelSize: 220,
          selectButtonSize: 92,
          deviceColorStyle: deviceColorStyle,
        ),
      ),
    );
  }
}
