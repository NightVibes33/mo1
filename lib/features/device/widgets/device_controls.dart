import 'dart:async';

import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/constants/keys.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/features/device/models/device_action.dart';
import 'package:dope/features/device/services/device_buttons_service_provider.dart';
import 'package:dope/features/device/widgets/wheel_skin_visual.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/click_wheel_sensitivity.dart';
import 'package:dope/features/settings/models/click_wheel_size.dart';
import 'package:dope/features/settings/models/wheel_style.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
    final bool onRightSide = !onLeftSide;
    final bool onBottom = !onTop;

    final bool panUp = dragUpdateDetails.delta.dy <= 0.0;
    final bool panLeft = dragUpdateDetails.delta.dx <= 0.0;
    final bool panRight = !panLeft;
    final bool panDown = !panUp;

    final double yChange = dragUpdateDetails.delta.dy.abs();
    final double xChange = dragUpdateDetails.delta.dx.abs();

    final double verticalRotation =
        (onRightSide && panDown) || (onLeftSide && panUp)
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
      durationSinceLastScroll =
          dragUpdateDetails.sourceTimeStamp ?? Duration.zero;
    }

    final bool isForwardDirection = rotationalChange > 0;
    final double absRotationalChange = rotationalChange.abs();

    if ((absRotationalChange > bigThresholdRotationalChange) ||
        (absRotationalChange > smallThresholdRotationalChange &&
            millisecondsSinceLastScroll >
                Constants.milliSecondsBeforeNextScroll)) {
      await ref
          .read(deviceButtonsServiceProvider.notifier)
          .buttonPressVibrate();
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

  Future<void> _onMenuTap() async {
    await ref
        .read(deviceButtonsServiceProvider.notifier)
        .setDeviceAction(DeviceAction.menu);
  }

  Future<void> _onMenuLongPress(BuildContext context) async {
    await Future.wait([
      ref.read(deviceButtonsServiceProvider.notifier).buttonPressVibrate(),
      ref.read(deviceButtonsServiceProvider.notifier).clickWheelSound(),
    ]);
    if (!context.mounted) {
      return;
    }
    context.goNamed(Routes.menu.name);
    if (!ref.read(splitScreenViewControllerProvider).isScreenVisible) {
      unawaited(ref.read(splitScreenViewControllerProvider).openSplitView());
    }
  }

  Future<void> _onPreviousTap() async {
    await ref
        .read(deviceButtonsServiceProvider.notifier)
        .setDeviceAction(DeviceAction.seekBackward);
  }

  Future<void> _onPreviousLongPress() async {
    await ref
        .read(deviceButtonsServiceProvider.notifier)
        .setDeviceAction(DeviceAction.seekBackwardLongPress);
  }

  Future<void> _onSelectTap() async {
    await ref
        .read(deviceButtonsServiceProvider.notifier)
        .setDeviceAction(DeviceAction.select);
  }

  Future<void> _onSelectLongPress() async {
    await ref
        .read(deviceButtonsServiceProvider.notifier)
        .setDeviceAction(DeviceAction.selectLongPress);
  }

  Future<void> _onNextTap() async {
    await ref
        .read(deviceButtonsServiceProvider.notifier)
        .setDeviceAction(DeviceAction.seekForward);
  }

  Future<void> _onNextLongPress() async {
    await ref
        .read(deviceButtonsServiceProvider.notifier)
        .setDeviceAction(DeviceAction.seekForwardLongPress);
  }

  Future<void> _onLongPressEnd() async {
    await ref
        .read(deviceButtonsServiceProvider.notifier)
        .setDeviceAction(DeviceAction.longPressEnd);
  }

  Future<void> _onPlayPauseTap() async {
    await ref
        .read(deviceButtonsServiceProvider.notifier)
        .playPauseButtonClick();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsPreferencesControllerProvider);
    final DeviceColorStyle deviceColorStyle = settings
        .resolveDeviceColorStyle();
    final clickWheelSize = settings.clickWheelSize;
    final clickWheelSensitivity = settings.clickWheelSensitivity;
    final wheelStyle = settings.wheelStyle;

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
        final double screenWidth = constraints.maxWidth + 40;
        final double wheelSize = screenWidth * clickWheelRadiusRatio;

        return SizedBox(
          height: wheelSize,
          width: wheelSize,
          child: GestureDetector(
            onPanUpdate: (dragUpdateDetails) => onClickWheelScroll(
              dragUpdateDetails: dragUpdateDetails,
              radius: wheelSize / 2,
              smallThresholdRotationalChange: smallThresholdRotationalChange,
              bigThresholdRotationalChange: bigThresholdRotationalChange,
            ),
            child: WheelSkinVisual(
              wheelStyle: wheelStyle,
              wheelSize: wheelSize,
              selectButtonSize: screenWidth * selectButtonRadiusRatio,
              deviceColorStyle: deviceColorStyle,
              onMenuTap: _onMenuTap,
              onMenuLongPress: () => _onMenuLongPress(context),
              onPreviousTap: _onPreviousTap,
              onPreviousLongPress: _onPreviousLongPress,
              onSelectTap: _onSelectTap,
              onSelectLongPress: _onSelectLongPress,
              onNextTap: _onNextTap,
              onNextLongPress: _onNextLongPress,
              onLongPressEnd: _onLongPressEnd,
              onPlayPauseTap: _onPlayPauseTap,
              menuKey: menuButtonGlobalKey,
              previousKey: previousButtonGlobalKey,
              centerKey: centerButtonGlobalKey,
              nextKey: nextButtonGlobalKey,
              playPauseKey: playPauseButtonGlobalKey,
            ),
          ),
        );
      },
    );
  }
}
