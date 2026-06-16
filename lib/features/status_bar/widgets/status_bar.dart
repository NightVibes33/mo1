import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/widgets/liquid_glass.dart';
import 'package:dope/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dope/features/status_bar/widgets/battery_indicator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatusBar extends StatelessWidget {
  final String title;

  const StatusBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final borderColor = isDarkTheme
        ? AppPalette.darkStatusBarBorderColor
        : AppPalette.statusBarBorderColor;
    final textColor = isDarkTheme
        ? CupertinoColors.white
        : CupertinoColors.black;

    return SizedBox(
      height: 30,
      width: double.infinity,
      child: LiquidGlass(
        borderRadius: BorderRadius.zero,
        blur: 10,
        opacity: isDarkTheme ? 0.16 : 0.34,
        borderColor: borderColor.withValues(alpha: 0.62),
        gradientColors: [
          CupertinoColors.white.withValues(alpha: isDarkTheme ? 0.12 : 0.78),
          const Color(0xFFE9ECE8).withValues(alpha: isDarkTheme ? 0.08 : 0.46),
          CupertinoColors.black.withValues(alpha: isDarkTheme ? 0.16 : 0.05),
        ],
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final isPlaying = ref.watch(
                      nowPlayingDetailsProvider.select((e) => e.isPlaying),
                    );
                    return AnimatedScale(
                      scale: isPlaying ? 1.08 : 1,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutBack,
                      child: Icon(
                        isPlaying
                            ? CupertinoIcons.play_fill
                            : CupertinoIcons.pause_fill,
                        color: isPlaying
                            ? const Color(0xFF26D98B)
                            : AppPalette.selectedTileGradientColor1,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 2),
                const RepaintBoundary(child: BatteryIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
