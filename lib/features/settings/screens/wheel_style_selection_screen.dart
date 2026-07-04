import 'package:dope/core/constants/assets.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/custom_painter/next_button_custom_painter.dart';
import 'package:dope/core/custom_painter/play_pause_button_custom_painter.dart';
import 'package:dope/core/custom_painter/previous_button_custom_painter.dart';
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
    const wheelSize = 170.0;
    const centerSize = 70.0;
    final bool isModern = wheelStyle == WheelStyle.modern;

    final shellDecoration = isModern
        ? BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.34, -0.42),
              radius: 1.05,
              colors: [
                CupertinoColors.white.withValues(alpha: 0.46),
                deviceColorStyle.controlBackgroundColor.withValues(alpha: 0.84),
                deviceColorStyle.controlBackgroundColor.withValues(alpha: 0.72),
              ],
            ),
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: 0.28),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.16),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: CupertinoColors.white.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(-3, -4),
              ),
            ],
          )
        : BoxDecoration(
            shape: BoxShape.circle,
            color: deviceColorStyle.controlBackgroundColor,
          );

    final centerDecoration = BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: deviceColorStyle.controlBorderColor),
      image: const DecorationImage(
        image: AssetImage(Assets.noiseImage),
        fit: BoxFit.cover,
      ),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: deviceColorStyle.innerButtonGradientColors,
      ),
      boxShadow: isModern
          ? [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
    );

    final segmentBackgroundColor = isModern
        ? Colors.transparent
        : deviceColorStyle.controlBackgroundColor;

    return Container(
      height: wheelSize,
      width: wheelSize,
      padding: const EdgeInsets.all(12),
      decoration: shellDecoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: ColoredBox(
              color: segmentBackgroundColor,
              child: Align(
                alignment: Alignment.topCenter,
                child: Icon(
                  CupertinoIcons.back,
                  color: deviceColorStyle.buttonAccentColor,
                  size: 20,
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: wheelSize * 0.2175,
                  child: ColoredBox(
                    color: segmentBackgroundColor,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CustomPaint(
                        size: const Size(20, 10),
                        painter: PreviousButtonCustomPainter(
                          color: deviceColorStyle.buttonIconColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: centerSize,
                width: centerSize,
                child: DecoratedBox(decoration: centerDecoration),
              ),
              Expanded(
                child: SizedBox(
                  height: centerSize,
                  child: ColoredBox(
                    color: segmentBackgroundColor,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: CustomPaint(
                        size: const Size(20, 10),
                        painter: NextButtonCustomPainter(
                          color: deviceColorStyle.buttonIconColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: ColoredBox(
              color: segmentBackgroundColor,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: CustomPaint(
                  size: const Size(26, 12),
                  painter: PlayPauseButtonCustomPainter(
                    color: deviceColorStyle.buttonIconColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
