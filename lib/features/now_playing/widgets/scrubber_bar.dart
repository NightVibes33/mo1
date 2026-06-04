import 'dart:math' as math;

import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ScrubberBar extends ConsumerWidget {
  final double max;
  final double value;

  const ScrubberBar({super.key, required this.max, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final gradientColors = isDarkTheme
        ? const [
            AppPalette.darkSliderGradientColor1,
            AppPalette.darkSliderGradientColor2,
          ]
        : const [Color(0xFFF9F9F7), Color(0xFFD8DAD6)];
    final borderColor = isDarkTheme
        ? AppPalette.darkSliderBorderColor
        : const Color(0xFF9BA0A1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeMax = max <= 0 || !max.isFinite ? 1.0 : max;
        final progress = (value / safeMax).clamp(0.0, 1.0).toDouble();
        final barWidth = constraints.maxWidth;
        final knobRange = math.max(0.0, barWidth - 14);
        final knobLeft = knobRange * progress;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (tapDownDetails) async {
            if (barWidth <= 0) {
              return;
            }
            final targetSeekValue =
                (tapDownDetails.localPosition.dx.clamp(0.0, barWidth).toDouble() * safeMax) /
                barWidth;
            await ref
                .read(audioPlayerServiceProvider.notifier)
                .seekToDuration(targetSeekValue.floor());
          },
          child: SizedBox(
            height: 20,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Positioned.fill(
                  child: Center(
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: gradientColors,
                        ),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: knobLeft.clamp(0.0, knobRange).toDouble(),
                  child: Transform.rotate(
                    angle: 0.785,
                    child: Container(
                      height: 14,
                      width: 14,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            CupertinoColors.white.withValues(alpha: 0.92),
                            const Color(0xFF6E8EDB),
                          ],
                        ),
                        border: Border.all(color: borderColor, width: 0.8),
                        boxShadow: [
                          BoxShadow(
                            color: CupertinoColors.black.withValues(alpha: 0.18),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
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
