import 'dart:async';

import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/constants/keys.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/features/device/models/device_action.dart';
import 'package:dope/features/device/services/device_buttons_service_provider.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/click_wheel_sensitivity.dart';
import 'package:dope/features/settings/models/click_wheel_size.dart';
import 'package:dope/features/settings/models/device_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DeviceControls extends ConsumerStatefulWidget {
  const DeviceControls({super.key});

  @override
  ConsumerState createState() => _DeviceControlsState();
}

class _DeviceControlsState extends ConsumerState<DeviceControls> {
  Duration durationSinceLastScroll = Duration.zero;

  Future<void> onClickWheelScroll({
    required DragUpdateDetails dragUpdateDetails,
    required double radius,
    required double smallThresholdRotationalChange,
    required double bigThresholdRotationalChange,
  }) async {
    final bool onTop = dragUpdateDetails.localPosition.dy <= radius;
    final bool onLeftSide = dragUpdateDetails.localPosition.dx <= radius;
    final bool onBottom = !onTop;
    final bool panUp = dragUpdateDetails.delta.dy <= 0.0;
    final bool panLeft = dragUpdateDetails.delta.dx <= 0.0;
    final bool panRight = !panLeft;

    final double yChange = dragUpdateDetails.delta.dy.abs();
    final double xChange = dragUpdateDetails.delta.dx.abs();

    final double verticalRotation =
        (onLeftSide && panUp) || (!onLeftSide && !panUp)
        ? yChange
        : yChange * -1;
    final double horizontalRotation =
        (onTop && panRight) || (onBottom && panLeft) ? xChange : xChange * -1;

    final double rotationalChange =
        (verticalRotation + horizontalRotation) *
        (dragUpdateDetails.delta.distance * 0.8);

    int millisecondsSinceLastScroll = 0;
    if (durationSinceLastScroll.inMinutes ==
            dragUpdateDetails.sourceTimeStamp?.inMinutes &&
        durationSinceLastScroll.inSeconds ==
            dragUpdateDetails.sourceTimeStamp?.inSeconds) {
      millisecondsSinceLastScroll =
          dragUpdateDetails.sourceTimeStamp!.inMilliseconds -
          durationSinceLastScroll.inMilliseconds;
    } else {
      durationSinceLastScroll = dragUpdateDetails.sourceTimeStamp ?? Duration.zero;
    }

    final bool isForwardDirection = rotationalChange > 0;
    final double absRotationalChange = rotationalChange.abs();

    if ((absRotationalChange > bigThresholdRotationalChange) ||
        (absRotationalChange > smallThresholdRotationalChange &&
            millisecondsSinceLastScroll >
                Constants.milliSecondsBeforeNextScroll)) {
      await ref.read(deviceButtonsServiceProvider.notifier).buttonPressVibrate();
      await ref.read(deviceButtonsServiceProvider.notifier).clickWheelSound();
      if (isForwardDirection) {
        await ref
            .read(deviceButtonsServiceProvider.notifier)
            .setDeviceAction(DeviceAction.rotateForward);
      } else {
        await ref
            .read(deviceButtonsServiceProvider.notifier)
            .setDeviceAction(DeviceAction.rotateBackward);
      }
      durationSinceLastScroll = Duration.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeviceColor deviceColor = ref.watch(
      settingsPreferencesControllerProvider.select(
        (settings) => settings.deviceColor,
      ),
    );
    final deviceColorStyle = deviceColor.style;
    final clickWheelSize = ref.watch(
      settingsPreferencesControllerProvider.select(
        (settings) => settings.clickWheelSize,
      ),
    );
    final clickWheelSensitivity = ref.watch(
      settingsPreferencesControllerProvider.select(
        (settings) => settings.clickWheelSensitivity,
      ),
    );
    late final double clickWheelRadiusRatio;
    late final double selectButtonRadiusRatio;
    switch (clickWheelSize) {
      case ClickWheelSize.small:
        clickWheelRadiusRatio = Constants.deviceClickWheelSmallRadiusRatio;
        selectButtonRadiusRatio = Constants.deviceSelectButtonSmallRadiusRatio;
        break;
      case ClickWheelSize.medium:
        clickWheelRadiusRatio = Constants.deviceClickWheelMediumRadiusRatio;
        selectButtonRadiusRatio = Constants.deviceSelectButtonMediumRadiusRatio;
        break;
      case ClickWheelSize.large:
        clickWheelRadiusRatio = Constants.deviceClickWheelLargeRadiusRatio;
        selectButtonRadiusRatio = Constants.deviceSelectButtonLargeRadiusRatio;
        break;
    }

    late final double smallThresholdRotationalChange;
    late final double bigThresholdRotationalChange;
    switch (clickWheelSensitivity) {
      case ClickWheelSensitivity.veryLow:
        smallThresholdRotationalChange =
            Constants.clickWheelVeryLowSensitivitySmallThreshold;
        bigThresholdRotationalChange =
            Constants.clickWheelVeryLowSensitivityBigThreshold;
        break;
      case ClickWheelSensitivity.low:
        smallThresholdRotationalChange =
            Constants.clickWheelLowSensitivitySmallThreshold;
        bigThresholdRotationalChange =
            Constants.clickWheelLowSensitivityBigThreshold;
        break;
      case ClickWheelSensitivity.medium:
        smallThresholdRotationalChange =
            Constants.clickWheelMediumSensitivitySmallThreshold;
        bigThresholdRotationalChange =
            Constants.clickWheelMediumSensitivityBigThreshold;
        break;
      case ClickWheelSensitivity.high:
        smallThresholdRotationalChange =
            Constants.clickWheelHighSensitivitySmallThreshold;
        bigThresholdRotationalChange =
            Constants.clickWheelHighSensitivityBigThreshold;
        break;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double panelSize = (constraints.maxWidth + 40) * 0.92;
        final double padSize = panelSize * clickWheelRadiusRatio;
        final double centerSize = panelSize * selectButtonRadiusRatio;

        return GestureDetector(
          onPanUpdate: (dragUpdateDetails) => onClickWheelScroll(
            dragUpdateDetails: dragUpdateDetails,
            radius: panelSize / 2,
            smallThresholdRotationalChange: smallThresholdRotationalChange,
            bigThresholdRotationalChange: bigThresholdRotationalChange,
          ),
          child: Container(
            height: panelSize,
            width: panelSize,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  deviceColorStyle.controlBackgroundColor.withValues(alpha: 0.96),
                  deviceColorStyle.controlBackgroundColor.withValues(alpha: 0.72),
                ],
              ),
              border: Border.all(
                color: CupertinoColors.white.withValues(alpha: 0.18),
                width: 1.1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D000000),
                  blurRadius: 30,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _DeckButtonRow(
                  label: 'MENU',
                  leftIcon: CupertinoIcons.chevron_left,
                  rightIcon: CupertinoIcons.chevron_right,
                  centerIcon: CupertinoIcons.play_arrow_solid,
                  accent: deviceColorStyle.buttonAccentColor,
                  iconColor: deviceColorStyle.buttonIconColor,
                  onLabelTap: () => ref
                      .read(deviceButtonsServiceProvider.notifier)
                      .setDeviceAction(DeviceAction.menu),
                  onLabelLongPress: () async {
                    await Future.wait([
                      ref.read(deviceButtonsServiceProvider.notifier).buttonPressVibrate(),
                      ref.read(deviceButtonsServiceProvider.notifier).clickWheelSound(),
                    ]);
                    if (context.mounted) {
                      context.goNamed(Routes.menu.name);
                      if (!ref.read(splitScreenViewControllerProvider).isScreenVisible) {
                        unawaited(
                          ref.read(splitScreenViewControllerProvider).openSplitView(),
                        );
                      }
                    }
                  },
                ),
                Center(
                  child: Container(
                    height: centerSize,
                    width: centerSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CupertinoColors.white.withValues(alpha: 0.88),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        height: centerSize * 0.62,
                        width: centerSize * 0.62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: deviceColorStyle.controlBackgroundColor,
                          border: Border.all(
                            color: CupertinoColors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: padSize * 0.34,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _DeckActionButton(
                        icon: CupertinoIcons.backward_end_fill,
                        color: deviceColorStyle.buttonIconColor,
                        onTap: () async => ref
                            .read(deviceButtonsServiceProvider.notifier)
                            .setDeviceAction(DeviceAction.seekBackward),
                        onLongPress: () async => ref
                            .read(deviceButtonsServiceProvider.notifier)
                            .setDeviceAction(DeviceAction.seekBackwardLongPress),
                        onLongPressEnd: () async => ref
                            .read(deviceButtonsServiceProvider.notifier)
                            .setDeviceAction(DeviceAction.longPressEnd),
                      ),
                      _DeckActionButton(
                        icon: CupertinoIcons.forward_end_fill,
                        color: deviceColorStyle.buttonIconColor,
                        onTap: () async => ref
                            .read(deviceButtonsServiceProvider.notifier)
                            .setDeviceAction(DeviceAction.seekForward),
                        onLongPress: () async => ref
                            .read(deviceButtonsServiceProvider.notifier)
                            .setDeviceAction(DeviceAction.seekForwardLongPress),
                        onLongPressEnd: () async => ref
                            .read(deviceButtonsServiceProvider.notifier)
                            .setDeviceAction(DeviceAction.longPressEnd),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeckButtonRow extends StatelessWidget {
  final String label;
  final IconData leftIcon;
  final IconData rightIcon;
  final IconData centerIcon;
  final Color accent;
  final Color iconColor;
  final VoidCallback onLabelTap;
  final Future<void> Function() onLabelLongPress;

  const _DeckButtonRow({
    required this.label,
    required this.leftIcon,
    required this.rightIcon,
    required this.centerIcon,
    required this.accent,
    required this.iconColor,
    required this.onLabelTap,
    required this.onLabelLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: onLabelTap,
          onLongPress: onLabelLongPress,
          child: Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(leftIcon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Icon(centerIcon, color: iconColor, size: 16),
            const SizedBox(width: 10),
            Icon(rightIcon, color: iconColor, size: 20),
          ],
        ),
      ],
    );
  }
}

class _DeckActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Future<void> Function() onTap;
  final Future<void> Function() onLongPress;
  final Future<void> Function() onLongPressEnd;

  const _DeckActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onLongPress,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async => onTap(),
      onLongPress: () async => onLongPress(),
      onLongPressEnd: (_) async => onLongPressEnd(),
      child: Container(
        height: 48,
        width: 68,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: CupertinoColors.white.withValues(alpha: 0.07),
          border: Border.all(color: CupertinoColors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}
