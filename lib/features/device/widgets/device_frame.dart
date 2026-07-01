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
    final size = MediaQuery.sizeOf(context);
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

    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage(Assets.noiseImage),
          fit: BoxFit.cover,
          opacity: deviceColorStyle.noiseOpacity,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: deviceColorStyle.frameGradientColors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
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
                    DeviceScreen(
                      key: deviceScreenGlobalKey,
                      child: widget.child,
                    ),
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
          colors[0].withValues(alpha: 0.24),
          colors[1].withValues(alpha: 0.18),
          colors[2].withValues(alpha: 0.2),
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
          colors[0].withValues(alpha: 0.32),
          colors[2].withValues(alpha: 0.14),
          CupertinoColors.white.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRect(rect, glowPaint);

    final wavePaint = Paint()
      ..blendMode = BlendMode.screen
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.width * 0.006)
      ..strokeCap = StrokeCap.round
      ..color = colors[1].withValues(alpha: 0.28);
    for (var i = 0; i < 3; i += 1) {
      final yBase = size.height * (0.22 + i * 0.18);
      final drift = math.sin(phase + i * 1.4) * size.height * 0.035;
      final path = Path()
        ..moveTo(-size.width * 0.08, yBase + drift)
        ..cubicTo(
          size.width * 0.25,
          yBase - size.height * 0.08 + drift,
          size.width * 0.55,
          yBase + size.height * 0.1 - drift,
          size.width * 1.08,
          yBase - drift,
        );
      canvas.drawPath(path, wavePaint);
    }

    final frostPaint = Paint()
      ..blendMode = BlendMode.screen
      ..style = PaintingStyle.fill
      ..color = CupertinoColors.white.withValues(alpha: 0.22);
    for (var i = 0; i < 34; i += 1) {
      final seed = i * 12.9898;
      final x = (math.sin(seed + 4.0) * 0.5 + 0.5) * size.width;
      final y = (math.sin(seed * 1.77 + 9.0) * 0.5 + 0.5) * size.height;
      final pulse = 0.55 + (math.sin(phase + i) * 0.5 + 0.5) * 0.45;
      canvas.drawCircle(
        Offset(x, y),
        (0.45 + (i % 3) * 0.22) * pulse,
        frostPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraIceFramePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.colors != colors;
  }
}
