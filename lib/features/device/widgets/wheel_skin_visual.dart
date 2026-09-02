import 'package:dopi/core/constants/assets.dart';
import 'package:dopi/core/custom_painter/next_button_custom_painter.dart';
import 'package:dopi/core/custom_painter/play_pause_button_custom_painter.dart';
import 'package:dopi/core/custom_painter/previous_button_custom_painter.dart';
import 'package:dopi/features/settings/models/device_color.dart';
import 'package:dopi/features/settings/models/wheel_style.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class WheelSkinVisual extends StatelessWidget {
  final WheelStyle wheelStyle;
  final double wheelSize;
  final double selectButtonSize;
  final DeviceColorStyle deviceColorStyle;
  final Future<void> Function()? onMenuTap;
  final Future<void> Function()? onMenuLongPress;
  final Future<void> Function()? onPreviousTap;
  final Future<void> Function()? onPreviousLongPress;
  final Future<void> Function()? onSelectTap;
  final Future<void> Function()? onSelectLongPress;
  final Future<void> Function()? onNextTap;
  final Future<void> Function()? onNextLongPress;
  final Future<void> Function()? onLongPressEnd;
  final Future<void> Function()? onPlayPauseTap;
  final Key? menuKey;
  final Key? previousKey;
  final Key? centerKey;
  final Key? nextKey;
  final Key? playPauseKey;

  const WheelSkinVisual({
    super.key,
    required this.wheelStyle,
    required this.wheelSize,
    required this.selectButtonSize,
    required this.deviceColorStyle,
    this.onMenuTap,
    this.onMenuLongPress,
    this.onPreviousTap,
    this.onPreviousLongPress,
    this.onSelectTap,
    this.onSelectLongPress,
    this.onNextTap,
    this.onNextLongPress,
    this.onLongPressEnd,
    this.onPlayPauseTap,
    this.menuKey,
    this.previousKey,
    this.centerKey,
    this.nextKey,
    this.playPauseKey,
  });

  @override
  Widget build(BuildContext context) {
    switch (wheelStyle) {
      case WheelStyle.modern:
        return Center(
          child: SizedBox(
            height: wheelSize,
            width: wheelSize,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _WheelContent(
                wheelSize: wheelSize,
                selectButtonSize: selectButtonSize,
                deviceColorStyle: deviceColorStyle,
                segmentBackgroundColor: Colors.transparent,
                centerShadow: [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: CupertinoColors.white.withValues(alpha: 0.26),
                    blurRadius: 8,
                    offset: const Offset(0, -3),
                  ),
                ],
                onMenuTap: onMenuTap,
                onMenuLongPress: onMenuLongPress,
                onPreviousTap: onPreviousTap,
                onPreviousLongPress: onPreviousLongPress,
                onSelectTap: onSelectTap,
                onSelectLongPress: onSelectLongPress,
                onNextTap: onNextTap,
                onNextLongPress: onNextLongPress,
                onLongPressEnd: onLongPressEnd,
                onPlayPauseTap: onPlayPauseTap,
                menuKey: menuKey,
                previousKey: previousKey,
                centerKey: centerKey,
                nextKey: nextKey,
                playPauseKey: playPauseKey,
              ),
            ),
          ),
        );
      case WheelStyle.classic:
        return Center(
          child: Container(
            height: wheelSize,
            width: wheelSize,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: deviceColorStyle.controlBackgroundColor,
            ),
            clipBehavior: Clip.hardEdge,
            child: _WheelContent(
              wheelSize: wheelSize,
              selectButtonSize: selectButtonSize,
              deviceColorStyle: deviceColorStyle,
              segmentBackgroundColor: deviceColorStyle.controlBackgroundColor,
              centerShadow: null,
              onMenuTap: onMenuTap,
              onMenuLongPress: onMenuLongPress,
              onPreviousTap: onPreviousTap,
              onPreviousLongPress: onPreviousLongPress,
              onSelectTap: onSelectTap,
              onSelectLongPress: onSelectLongPress,
              onNextTap: onNextTap,
              onNextLongPress: onNextLongPress,
              onLongPressEnd: onLongPressEnd,
              onPlayPauseTap: onPlayPauseTap,
              menuKey: menuKey,
              previousKey: previousKey,
              centerKey: centerKey,
              nextKey: nextKey,
              playPauseKey: playPauseKey,
            ),
          ),
        );
    }
  }
}

class _WheelContent extends StatelessWidget {
  final double wheelSize;
  final double selectButtonSize;
  final DeviceColorStyle deviceColorStyle;
  final Color segmentBackgroundColor;
  final List<BoxShadow>? centerShadow;
  final Future<void> Function()? onMenuTap;
  final Future<void> Function()? onMenuLongPress;
  final Future<void> Function()? onPreviousTap;
  final Future<void> Function()? onPreviousLongPress;
  final Future<void> Function()? onSelectTap;
  final Future<void> Function()? onSelectLongPress;
  final Future<void> Function()? onNextTap;
  final Future<void> Function()? onNextLongPress;
  final Future<void> Function()? onLongPressEnd;
  final Future<void> Function()? onPlayPauseTap;
  final Key? menuKey;
  final Key? previousKey;
  final Key? centerKey;
  final Key? nextKey;
  final Key? playPauseKey;

  const _WheelContent({
    required this.wheelSize,
    required this.selectButtonSize,
    required this.deviceColorStyle,
    required this.segmentBackgroundColor,
    required this.centerShadow,
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
    required this.menuKey,
    required this.previousKey,
    required this.centerKey,
    required this.nextKey,
    required this.playPauseKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: _wrap(
            onTap: onMenuTap,
            onLongPress: onMenuLongPress,
            child: ColoredBox(
              color: segmentBackgroundColor,
              child: Align(
                alignment: Alignment.topCenter,
                child: Icon(
                  CupertinoIcons.back,
                  key: menuKey,
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
              key: previousKey,
              child: _wrap(
                onTap: onPreviousTap,
                onLongPress: onPreviousLongPress,
                onLongPressEnd: onLongPressEnd,
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
            _wrap(
              onTap: onSelectTap,
              onLongPress: onSelectLongPress,
              onLongPressEnd: onLongPressEnd,
              child: SizedBox(
                key: centerKey,
                height: selectButtonSize,
                width: selectButtonSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
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
                    boxShadow: centerShadow,
                  ),
                ),
              ),
            ),
            Expanded(
              key: nextKey,
              child: _wrap(
                onTap: onNextTap,
                onLongPress: onNextLongPress,
                onLongPressEnd: onLongPressEnd,
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
          child: _wrap(
            onTap: onPlayPauseTap,
            child: ColoredBox(
              color: segmentBackgroundColor,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: CustomPaint(
                  key: playPauseKey,
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
    );
  }

  Widget _wrap({
    required Widget child,
    Future<void> Function()? onTap,
    Future<void> Function()? onLongPress,
    Future<void> Function()? onLongPressEnd,
  }) {
    if (onTap == null && onLongPress == null && onLongPressEnd == null) {
      return child;
    }
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressEnd: onLongPressEnd == null
          ? null
          : (_) {
              onLongPressEnd();
            },
      child: child,
    );
  }
}
