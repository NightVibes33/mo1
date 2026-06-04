import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SeekBar extends ConsumerWidget {
  final double max;
  final double value;

  const SeekBar({super.key, required this.max, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final inactiveGradientColors = isDarkTheme
        ? const [
            AppPalette.darkSliderGradientColor1,
            AppPalette.darkSliderGradientColor2,
          ]
        : const [
            Color(0xFFF7F7F5),
            Color(0xFFDADDD8),
          ];
    final borderColor = isDarkTheme
        ? AppPalette.darkSliderBorderColor
        : const Color(0xFF9BA0A1);
    final fillColors = isDarkTheme
        ? const [Color(0xFF7A8FD8), Color(0xFFB8C7FF)]
        : const [Color(0xFF86A9F4), Color(0xFF5B82DD)];

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeMax = max <= 0 || !max.isFinite ? 1.0 : max;
        final progress = (value / safeMax).clamp(0.0, 1.0).toDouble();
        final barWidth = constraints.maxWidth;

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
            child: Center(
              child: Container(
                height: 12,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: borderColor, width: 1),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: inactiveGradientColors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.14),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    height: double.infinity,
                    width: barWidth * progress,
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.linear,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: fillColors,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
