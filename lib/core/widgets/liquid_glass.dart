import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';

class LiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double opacity;
  final List<Color>? gradientColors;
  final Color borderColor;
  final List<BoxShadow> shadows;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = EdgeInsets.zero,
    this.blur = 18,
    this.opacity = 0.42,
    this.gradientColors,
    this.borderColor = const Color(0x66FFFFFF),
    this.shadows = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors =
        gradientColors ??
        [
          CupertinoColors.white.withValues(alpha: opacity),
          CupertinoColors.white.withValues(alpha: opacity * 0.18),
          const Color(0xFFFF4FD8).withValues(alpha: opacity * 0.10),
        ];

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              border: Border.all(color: borderColor),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.center,
                        colors: [
                          CupertinoColors.white.withValues(alpha: 0.38),
                          CupertinoColors.white.withValues(alpha: 0.04),
                          CupertinoColors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedAuroraBackdrop extends StatefulWidget {
  final List<Color> colors;
  final double intensity;

  const AnimatedAuroraBackdrop({
    super.key,
    required this.colors,
    this.intensity = 1,
  });

  @override
  State<AnimatedAuroraBackdrop> createState() => _AnimatedAuroraBackdropState();
}

class _AnimatedAuroraBackdropState extends State<AnimatedAuroraBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 11),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _AuroraPainter(
              progress: _controller.value,
              colors: widget.colors,
              intensity: widget.intensity,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final double intensity;

  const _AuroraPainter({
    required this.progress,
    required this.colors,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.first.withValues(alpha: 0.38),
          colors.last.withValues(alpha: 0.78),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    for (var index = 0; index < 4; index++) {
      final phase = progress * pi * 2 + index * 0.9;
      final y = size.height * (0.18 + index * 0.2) + sin(phase) * 42;
      final path = Path()
        ..moveTo(-size.width * 0.15, y)
        ..cubicTo(
          size.width * 0.22,
          y - 110 - cos(phase) * 35,
          size.width * 0.72,
          y + 120 + sin(phase * 0.7) * 40,
          size.width * 1.15,
          y - 20,
        )
        ..lineTo(size.width * 1.15, y + 125)
        ..cubicTo(
          size.width * 0.68,
          y + 210,
          size.width * 0.22,
          y + 28,
          -size.width * 0.15,
          y + 150,
        )
        ..close();

      final paint = Paint()
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28)
        ..shader = LinearGradient(
          colors: [
            colors[index % colors.length].withValues(alpha: 0.17 * intensity),
            colors[(index + 1) % colors.length].withValues(
              alpha: 0.32 * intensity,
            ),
            CupertinoColors.white.withValues(alpha: 0.10 * intensity),
          ],
        ).createShader(rect);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.colors != colors ||
        oldDelegate.intensity != intensity;
  }
}

class LiquidReflectionOverlay extends StatelessWidget {
  final BorderRadius borderRadius;
  final double opacity;

  const LiquidReflectionOverlay({
    super.key,
    this.borderRadius = BorderRadius.zero,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.32, 0.34, 0.58, 1],
            colors: [
              CupertinoColors.white.withValues(alpha: 0.32 * opacity),
              CupertinoColors.white.withValues(alpha: 0.04 * opacity),
              CupertinoColors.white.withValues(alpha: 0.19 * opacity),
              CupertinoColors.white.withValues(alpha: 0.03 * opacity),
              CupertinoColors.black.withValues(alpha: 0.18 * opacity),
            ],
          ),
        ),
      ),
    );
  }
}
