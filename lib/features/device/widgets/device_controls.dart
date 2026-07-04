import 'dart:async';

import 'package:dope/core/constants/assets.dart';
import 'package:dope/core/constants/constants.dart';
import 'package:dope/core/constants/keys.dart';
import 'package:dope/core/custom_painter/next_button_custom_painter.dart';
import 'package:dope/core/custom_painter/play_pause_button_custom_painter.dart';
import 'package:dope/core/custom_painter/previous_button_custom_painter.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/features/device/models/device_action.dart';
import 'package:dope/features/device/services/device_buttons_service_provider.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/click_wheel_sensitivity.dart';
import 'package:dope/features/settings/models/click_wheel_size.dart';
import 'package:dope/features/settings/models/device_color.dart';
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
            child: switch (wheelStyle) {
              WheelStyle.modern => _WheelSkin(
                wheelSize: wheelSize,
                selectButtonSize: screenWidth * selectButtonRadiusRatio,
                deviceColorStyle: deviceColorStyle,
                shellDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.34, -0.42),
                    radius: 1.05,
                    colors: [
                      CupertinoColors.white.withValues(alpha: 0.46),
                      deviceColorStyle.controlBackgroundColor.withValues(
                        alpha: 0.84,
                      ),
                      deviceColorStyle.controlBackgroundColor.withValues(
                        alpha: 0.72,
                      ),
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
                ),
                centerDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: deviceColorStyle.controlBorderColor,
                  ),
                  image: const DecorationImage(
                    image: AssetImage(Assets.noiseImage),
                    fit: BoxFit.cover,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: deviceColorStyle.innerButtonGradientColors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                segmentBackgroundColor: Colors.transparent,
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
              ),
              WheelStyle.classic => _WheelSkin(
                wheelSize: wheelSize,
                selectButtonSize: screenWidth * selectButtonRadiusRatio,
                deviceColorStyle: deviceColorStyle,
                shellDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: deviceColorStyle.controlBackgroundColor,
                ),
                centerDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: deviceColorStyle.controlBorderColor,
                  ),
                  image: const DecorationImage(
                    image: AssetImage(Assets.noiseImage),
                    fit: BoxFit.cover,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: deviceColorStyle.innerButtonGradientColors,
                  ),
                ),
                segmentBackgroundColor: deviceColorStyle.controlBackgroundColor,
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
              ),
            },
          ),
        );
      },
    );
  }
}

class _WheelSkin extends StatelessWidget {
  final double wheelSize;
  final double selectButtonSize;
  final DeviceColorStyle deviceColorStyle;
  final BoxDecoration shellDecoration;
  final BoxDecoration centerDecoration;
  final Color segmentBackgroundColor;
  final Future<void> Function() onMenuTap;
  final Future<void> Function() onMenuLongPress;
  final Future<void> Function() onPreviousTap;
  final Future<void> Function() onPreviousLongPress;
  final Future<void> Function() onSelectTap;
  final Future<void> Function() onSelectLongPress;
  final Future<void> Function() onNextTap;
  final Future<void> Function() onNextLongPress;
  final Future<void> Function() onLongPressEnd;
  final Future<void> Function() onPlayPauseTap;

  const _WheelSkin({
    required this.wheelSize,
    required this.selectButtonSize,
    required this.deviceColorStyle,
    required this.shellDecoration,
    required this.centerDecoration,
    required this.segmentBackgroundColor,
    required this.onMenuTap,
    required this.onMenuLongPress,
    required this.onPreviousTap,
    required this.onPreviousLongPress,
    required this.onSelectTap,
    required this.onSelectLongPress,
    required this.onNextTap,
    required this.onNextLongPress,
    required this.onLongPressEnd,
    required this.onPlayPauseTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
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
              child: GestureDetector(
                onTap: onMenuTap,
                onLongPress: onMenuLongPress,
                child: ColoredBox(
                  color: segmentBackgroundColor,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Icon(
                      CupertinoIcons.back,
                      key: menuButtonGlobalKey,
                      color: deviceColorStyle.buttonAccentColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  key: previousButtonGlobalKey,
                  child: GestureDetector(
                    onTap: onPreviousTap,
                    onLongPress: onPreviousLongPress,
                    onLongPressEnd: (_) => onLongPressEnd(),
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
                ),
                GestureDetector(
                  key: centerButtonGlobalKey,
                  onTap: onSelectTap,
                  onLongPress: onSelectLongPress,
                  onLongPressEnd: (_) => onLongPressEnd(),
                  child: SizedBox(
                    height: selectButtonSize,
                    width: selectButtonSize,
                    child: DecoratedBox(decoration: centerDecoration),
                  ),
                ),
                Expanded(
                  key: nextButtonGlobalKey,
                  child: GestureDetector(
                    onTap: onNextTap,
                    onLongPress: onNextLongPress,
                    onLongPressEnd: (_) => onLongPressEnd(),
                    child: SizedBox(
                      height: selectButtonSize,
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
                ),
              ],
            ),
            Expanded(
              child: GestureDetector(
                onTap: onPlayPauseTap,
                child: ColoredBox(
                  color: segmentBackgroundColor,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: CustomPaint(
                      key: playPauseButtonGlobalKey,
                      size: const Size(26, 12),
                      painter: PlayPauseButtonCustomPainter(
                        color: deviceColorStyle.buttonIconColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
