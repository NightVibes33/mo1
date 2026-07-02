import 'dart:math' as math;

import 'package:dope/core/constants/assets.dart';
import 'package:dope/core/constants/keys.dart';
import 'package:dope/features/device/widgets/device_controls.dart';
import 'package:dope/features/device/widgets/device_screen.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/device_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceFrame extends ConsumerStatefulWidget {
  final Widget child;

  const DeviceFrame({super.key, required this.child});

  @override
  ConsumerState<DeviceFrame> createState() => _DeviceFrameState();
}

class _DeviceFrameState extends ConsumerState<DeviceFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _auroraController;

  @override
  void initState() {
    super.initState();
    _auroraController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
  }

  @override
  void dispose() {
    _auroraController.dispose();
    super.dispose();
  }

  void _syncAuroraAnimation(bool shouldAnimate) {
    if (shouldAnimate) {
      if (!_auroraController.isAnimating) {
        _auroraController.repeat();
      }
    } else if (_auroraController.isAnimating) {
      _auroraController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeviceColor deviceColor = ref.watch(
      settingsPreferencesControllerProvider.select((e) => e.deviceColor),
    );
    final useColorTextures = ref.watch(
      settingsPreferencesControllerProvider.select(
        (settings) => settings.useColorTextures,
      ),
    );
    final deviceColorStyle = deviceColor.style(
      useColorTextures: useColorTextures,
    );
    _syncAuroraAnimation(deviceColorStyle.animateFrameHighlights);

    final shellColors = [
      deviceColorStyle.frameGradientColors.first.withValues(alpha: 0.9),
      deviceColorStyle.frameGradientColors.last.withValues(alpha: 0.98),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage(Assets.noiseImage),
          fit: BoxFit.cover,
          opacity: deviceColorStyle.noiseOpacity * 0.65,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: shellColors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (deviceColorStyle.animateFrameHighlights)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _auroraController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _AuroraIceFramePainter(
                        progress: _auroraController.value,
                        colors: deviceColorStyle.frameHighlightColors,
                      ),
                    );
                  },
                ),
              ),
            ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    Expanded(
                      child: DeviceScreen(
                        key: deviceScreenGlobalKey,
                        child: widget.child,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        color: CupertinoColors.black.withValues(alpha: 0.14),
                        border: Border.all(
                          color: CupertinoColors.white.withValues(alpha: 0.18),
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
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                        child: Center(
                          child: DeviceControls(key: deviceControlsGlobalKey),
                        ),
                      ),
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

class _AuroraIceFramePainter extends CustomPainter {
  final double progress;
  final List<Color> colors;

  const _AuroraIceFramePainter({
    required this.progress,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.length < 3) {
      return;
    }

    final rect = Offset.zero & size;
    final phase = progress * math.pi * 2;

    final washPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = LinearGradient(
        begin: Alignment(-1.2 + math.sin(phase) * 0.35, -1),
        end: Alignment(1.1 + math.cos(phase * 0.72) * 0.25, 1),
        colors: [
          CupertinoColors.white.withValues(alpha: 0),
          colors[0].withValues(alpha: 0.2),
          colors[1].withValues(alpha: 0.14),
          colors[2].withValues(alpha: 0.16),
          CupertinoColors.white.withValues(alpha: 0),
        ],
        stops: const [0, 0.24, 0.48, 0.72, 1],
      ).createShader(rect);
    canvas.drawRect(rect, washPaint);

    final glowPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = RadialGradient(
        center: Alignment(
          math.cos(phase * 0.65) * 0.5,
          -0.1 + math.sin(phase * 0.55) * 0.35,
        ),
        radius: 0.9,
        colors: [
          colors[0].withValues(alpha: 0.22),
          colors[2].withValues(alpha: 0.12),
          CupertinoColors.white.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRect(rect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _AuroraIceFramePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.colors != colors;
  }
}
