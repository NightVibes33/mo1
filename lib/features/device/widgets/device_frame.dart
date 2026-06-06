import 'dart:async';
import 'dart:math';

import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/constants/keys.dart';
import 'package:classipod/features/device/widgets/device_controls.dart';
import 'package:classipod/features/device/widgets/device_screen.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:classipod/features/settings/models/device_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

class DeviceFrame extends ConsumerStatefulWidget {
  final Widget child;

  const DeviceFrame({super.key, required this.child});

  @override
  ConsumerState<DeviceFrame> createState() => _DeviceFrameState();
}

class _DeviceFrameState extends ConsumerState<DeviceFrame> {
  static const Duration _doubleTapWindow = Duration(milliseconds: 360);
  static const Duration _frameZoomDuration = Duration(milliseconds: 420);
  static const double _doubleTapDistance = 52;

  bool _isZoomedOut = false;
  DateTime? _lastFramePointerAt;
  Offset? _lastFramePointerPosition;

  void _handleFramePointerDown(PointerDownEvent event, Rect frameRect) {
    if (!frameRect.contains(event.localPosition)) {
      return;
    }

    final previousTime = _lastFramePointerAt;
    final previousPosition = _lastFramePointerPosition;
    final now = DateTime.now();
    final isDoubleTap =
        previousTime != null &&
        previousPosition != null &&
        now.difference(previousTime) <= _doubleTapWindow &&
        (event.localPosition - previousPosition).distance <= _doubleTapDistance;

    if (isDoubleTap) {
      _lastFramePointerAt = null;
      _lastFramePointerPosition = null;
      setState(() => _isZoomedOut = !_isZoomedOut);
      unawaited(HapticFeedback.selectionClick());
      return;
    }

    _lastFramePointerAt = now;
    _lastFramePointerPosition = event.localPosition;
  }

  @override
  Widget build(BuildContext context) {
    final DeviceColor deviceColor = ref.watch(
      settingsPreferencesControllerProvider.select((e) => e.deviceColor),
    );
    final deviceColorStyle = deviceColor.style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaSize = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : mediaSize.width;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : mediaSize.height;
        final size = Size(width, height);
        final topInset = MediaQuery.viewPaddingOf(context).top;
        final frameScale = _isZoomedOut ? (width < 390 ? 0.72 : 0.76) : 1.0;
        final zoomedTopOffset = _isZoomedOut
            ? max(topInset + 86, height * 0.14)
            : 0.0;
        final visibleFrameRect = Rect.fromLTWH(
          (width - width * frameScale) / 2,
          zoomedTopOffset,
          width * frameScale,
          height * frameScale,
        );
        final frameRadius = _isZoomedOut ? 44.0 : 0.0;

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) =>
              _handleFramePointerDown(event, visibleFrameRect),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedOpacity(
                opacity: _isZoomedOut ? 1 : 0,
                duration: _frameZoomDuration,
                curve: Curves.easeOutCubic,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: CupertinoColors.black),
                ),
              ),
              AnimatedContainer(
                duration: _frameZoomDuration,
                curve: Curves.easeOutCubic,
                transform: Matrix4.identity()
                  ..translate(0.0, zoomedTopOffset)
                  ..scale(frameScale),
                transformAlignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(frameRadius),
                  boxShadow: _isZoomedOut
                      ? [
                          BoxShadow(
                            color: CupertinoColors.black.withValues(alpha: 0.34),
                            blurRadius: 26,
                            offset: const Offset(0, 16),
                          ),
                        ]
                      : null,
                ),
                child: _OriginalDeviceBody(
                  size: size,
                  noiseOpacity: deviceColorStyle.noiseOpacity,
                  frameGradientColors: deviceColorStyle.frameGradientColors,
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OriginalDeviceBody extends StatelessWidget {
  final Size size;
  final double noiseOpacity;
  final List<Color> frameGradientColors;
  final Widget child;

  const _OriginalDeviceBody({
    required this.size,
    required this.noiseOpacity,
    required this.frameGradientColors,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage(Assets.noiseImage),
          fit: BoxFit.cover,
          opacity: noiseOpacity,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: frameGradientColors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            child: SizedBox(
              height: 20,
              width: size.width,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(blurRadius: 100, spreadRadius: 1)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: SizedBox(
              height: 20,
              width: size.width,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(blurRadius: 100, spreadRadius: 1)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            child: SizedBox(
              height: size.height,
              width: 20,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(blurRadius: 100, spreadRadius: 1)],
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            child: SizedBox(
              height: size.height,
              width: 20,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(blurRadius: 100, spreadRadius: 1)],
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 30, 20, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 960,
                  maxWidth: 450,
                ),
                child: Column(
                  children: [
                    DeviceScreen(key: deviceScreenGlobalKey, child: child),
                    const Spacer(flex: 2),
                    DeviceControls(key: deviceControlsGlobalKey),
                    const Spacer(),
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
