import 'dart:async';

import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/constants/constants.dart';
import 'package:classipod/core/constants/keys.dart';
import 'package:classipod/core/custom_painter/next_button_custom_painter.dart';
import 'package:classipod/core/custom_painter/play_pause_button_custom_painter.dart';
import 'package:classipod/core/custom_painter/previous_button_custom_painter.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/features/device/models/device_action.dart';
import 'package:classipod/features/device/services/device_buttons_service_provider.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:classipod/features/settings/models/click_wheel_sensitivity.dart';
import 'package:classipod/features/settings/models/click_wheel_size.dart';
import 'package:classipod/features/settings/models/device_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DeviceControls extends ConsumerStatefulWidget {
  const DeviceControls({super.key});

  @override
  ConsumerState createState() => _DeviceControlsState();
}

class _DeviceControlsState extends ConsumerState<DeviceControls> {
  Duration? _lastScrollTimestamp;
  bool _centerPressed = false;
  bool _wheelActive = false;
  Alignment _touchAlignment = const Alignment(-0.28, -0.35);

  void onClickWheelScroll({
    required DragUpdateDetails dragUpdateDetails,
    required double radius,
    required double smallThresholdRotationalChange,
    required double bigThresholdRotationalChange,
  }) {
    // Pan location on the wheel
    final bool onTop = dragUpdateDetails.localPosition.dy <= radius;
    final bool onLeftSide = dragUpdateDetails.localPosition.dx <= radius;
    final bool onRightSide = !onLeftSide;
    final bool onBottom = !onTop;

    // Pan movements
    final bool panUp = dragUpdateDetails.delta.dy <= 0.0;
    final bool panLeft = dragUpdateDetails.delta.dx <= 0.0;
    final bool panRight = !panLeft;
    final bool panDown = !panUp;

    // Absolute change on axis
    final double yChange = dragUpdateDetails.delta.dy.abs();
    final double xChange = dragUpdateDetails.delta.dx.abs();

    // Directional change on wheel
    final double verticalRotation =
        (onRightSide && panDown) || (onLeftSide && panUp)
        ? yChange
        : yChange * -1;

    final double horizontalRotation =
        (onTop && panRight) || (onBottom && panLeft) ? xChange : xChange * -1;

    // Total computed change
    final double rotationalChange =
        (verticalRotation + horizontalRotation) *
        (dragUpdateDetails.delta.distance * 0.8);

    final timestamp = dragUpdateDetails.sourceTimeStamp;
    final millisecondsSinceLastScroll =
        _lastScrollTimestamp != null && timestamp != null
        ? timestamp.inMilliseconds - _lastScrollTimestamp!.inMilliseconds
        : Constants.milliSecondsBeforeNextScroll + 1;

    final bool isForwardDirection = rotationalChange > 0;
    final double absRotationalChange = rotationalChange.abs();
    final shouldEmitAction =
        absRotationalChange > bigThresholdRotationalChange ||
        (absRotationalChange > smallThresholdRotationalChange &&
            millisecondsSinceLastScroll >
                Constants.milliSecondsBeforeNextScroll);

    if (!shouldEmitAction) {
      return;
    }

    _lastScrollTimestamp = timestamp;
    unawaited(
      ref
          .read(deviceButtonsServiceProvider.notifier)
          .setDeviceAction(
            isForwardDirection
                ? DeviceAction.rotateForward
                : DeviceAction.rotateBackward,
          ),
    );
  }

  void _setCenterPressed(bool value) {
    if (_centerPressed == value) {
      return;
    }
    setState(() => _centerPressed = value);
  }

  void _updateWheelTouch(Offset localPosition, double wheelSize) {
    if (wheelSize <= 0) {
      return;
    }
    final x = ((localPosition.dx / wheelSize) * 2 - 1).clamp(-0.75, 0.75);
    final y = ((localPosition.dy / wheelSize) * 2 - 1).clamp(-0.75, 0.75);
    setState(() {
      _wheelActive = true;
      _touchAlignment = Alignment(x.toDouble(), y.toDouble());
    });
  }

  void _clearWheelTouch() {
    if (!_wheelActive) {
      return;
    }
    setState(() => _wheelActive = false);
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
        final double screenWidth = constraints.maxWidth;
        final adjustedWheelRatio = switch (clickWheelSize) {
          ClickWheelSize.small => clickWheelRadiusRatio + 0.1,
          ClickWheelSize.medium => clickWheelRadiusRatio + 0.075,
          ClickWheelSize.large => clickWheelRadiusRatio,
        };
        final double wheelSize = screenWidth * adjustedWheelRatio;
        final double wheelRadius = wheelSize / 2;
        final wheelBorderRadius = BorderRadius.circular(wheelRadius);
        final Color labelColor = deviceColorStyle.buttonAccentColor;
        final Color iconColor = deviceColorStyle.buttonIconColor;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _updateWheelTouch(
            details.localPosition,
            wheelSize,
          ),
          onPanUpdate: (dragUpdateDetails) {
            _updateWheelTouch(dragUpdateDetails.localPosition, wheelSize);
            onClickWheelScroll(
              dragUpdateDetails: dragUpdateDetails,
              radius: wheelRadius,
              smallThresholdRotationalChange: smallThresholdRotationalChange,
              bigThresholdRotationalChange: bigThresholdRotationalChange,
            );
          },
          onPanEnd: (_) => _clearWheelTouch(),
          onPanCancel: _clearWheelTouch,
          child: AnimatedScale(
            scale: _wheelActive ? 0.992 : 1,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: wheelSize,
            width: wheelSize,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(
                image: const AssetImage(Assets.noiseImage),
                fit: BoxFit.cover,
                opacity: deviceColorStyle.noiseOpacity * 0.26,
              ),
              gradient: RadialGradient(
                center: _wheelActive ? _touchAlignment : const Alignment(-0.28, -0.35),
                radius: 0.96,
                colors: [
                  CupertinoColors.white.withValues(
                    alpha: deviceColorStyle.isDark ? 0.2 : 0.86,
                  ),
                  deviceColorStyle.controlBackgroundColor.withValues(
                    alpha: deviceColorStyle.isDark ? 0.84 : 0.64,
                  ),
                  deviceColorStyle.controlBackgroundColor.withValues(alpha: 0.98),
                ],
              ),
              border: Border.all(
                color: deviceColorStyle.controlBorderColor.withValues(alpha: 0.72),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 11),
                ),
                BoxShadow(
                  color: CupertinoColors.white.withValues(
                    alpha: deviceColorStyle.isDark ? 0.02 : 0.26,
                  ),
                  blurRadius: 10,
                  offset: const Offset(-2, -2),
                ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                Positioned.fill(
                  child: LiquidReflectionOverlay(
                    borderRadius: wheelBorderRadius,
                    opacity: deviceColorStyle.isDark ? 0.46 : 0.72,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CupertinoColors.white.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async => ref
                            .read(deviceButtonsServiceProvider.notifier)
                            .setDeviceAction(DeviceAction.menu),
                        onLongPress: () async {
                          ref
                              .read(deviceButtonsServiceProvider.notifier)
                              .playClickFeedback();
                          if (context.mounted) {
                            context.goNamed(Routes.menu.name);
                            if (!ref
                                .read(splitScreenViewControllerProvider)
                                .isScreenVisible) {
                              unawaited(
                                ref
                                    .read(splitScreenViewControllerProvider)
                                    .openSplitView(),
                              );
                            }
                          }
                        },
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Text(
                            context.localization.menuButtonText,
                            key: menuButtonGlobalKey,
                            style: TextStyle(
                              color: labelColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: CupertinoColors.white.withValues(
                                    alpha: 0.32,
                                  ),
                                  blurRadius: 8,
                                ),
                              ],
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
                            behavior: HitTestBehavior.opaque,
                            onTap: () async => ref
                                .read(deviceButtonsServiceProvider.notifier)
                                .setDeviceAction(DeviceAction.seekBackward),
                            onLongPress: () async => ref
                                .read(deviceButtonsServiceProvider.notifier)
                                .setDeviceAction(
                                  DeviceAction.seekBackwardLongPress,
                                ),
                            onLongPressEnd: (_) async => ref
                                .read(deviceButtonsServiceProvider.notifier)
                                .setDeviceAction(DeviceAction.longPressEnd),
                            child: SizedBox(
                              height: screenWidth * 0.2175,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: CustomPaint(
                                  size: const Size(20, 10),
                                  painter: PreviousButtonCustomPainter(
                                    color: iconColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          key: centerButtonGlobalKey,
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => _setCenterPressed(true),
                          onTapCancel: () => _setCenterPressed(false),
                          onTapUp: (_) => _setCenterPressed(false),
                          onTap: () async => ref
                              .read(deviceButtonsServiceProvider.notifier)
                              .setDeviceAction(DeviceAction.select),
                          onLongPress: () async => ref
                              .read(deviceButtonsServiceProvider.notifier)
                              .setDeviceAction(DeviceAction.selectLongPress),
                          onLongPressEnd: (_) async {
                            _setCenterPressed(false);
                            await ref
                                .read(deviceButtonsServiceProvider.notifier)
                                .setDeviceAction(DeviceAction.longPressEnd);
                          },
                          child: AnimatedScale(
                            scale: _centerPressed ? 0.94 : 1,
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOut,
                            child: SizedBox(
                              height: screenWidth * selectButtonRadiusRatio,
                              width: screenWidth * selectButtonRadiusRatio,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: CupertinoColors.white.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  image: const DecorationImage(
                                    image: AssetImage(Assets.noiseImage),
                                    fit: BoxFit.cover,
                                    opacity: 0.38,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors:
                                        deviceColorStyle.innerButtonGradientColors,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: CupertinoColors.black.withValues(
                                        alpha: 0.24,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          key: nextButtonGlobalKey,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async => ref
                                .read(deviceButtonsServiceProvider.notifier)
                                .setDeviceAction(DeviceAction.seekForward),
                            onLongPress: () async => ref
                                .read(deviceButtonsServiceProvider.notifier)
                                .setDeviceAction(
                                  DeviceAction.seekForwardLongPress,
                                ),
                            onLongPressEnd: (_) async => ref
                                .read(deviceButtonsServiceProvider.notifier)
                                .setDeviceAction(DeviceAction.longPressEnd),
                            child: SizedBox(
                              height: screenWidth * selectButtonRadiusRatio,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: CustomPaint(
                                  size: const Size(20, 10),
                                  painter: NextButtonCustomPainter(
                                    color: iconColor,
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
                        behavior: HitTestBehavior.opaque,
                        onTap: () async => ref
                            .read(deviceButtonsServiceProvider.notifier)
                            .playPauseButtonClick(),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: CustomPaint(
                            key: playPauseButtonGlobalKey,
                            size: const Size(26, 12),
                            painter: PlayPauseButtonCustomPainter(
                              color: iconColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}
