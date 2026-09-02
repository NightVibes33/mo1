import 'package:dopi/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dopi/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatusBar extends ConsumerWidget {
  final String title;

  const StatusBar({super.key, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsPreferencesControllerProvider);
    final deviceColorStyle = settings.resolveDeviceColorStyle();
    final borderColor = deviceColorStyle.isDark
        ? CupertinoColors.white.withValues(alpha: 0.12)
        : CupertinoColors.black.withValues(alpha: 0.10);
    final backgroundColor = Color.lerp(
          deviceColorStyle.frameGradientColors.first,
          deviceColorStyle.frameGradientColors.last,
          0.36,
        )
        ?.withValues(alpha: deviceColorStyle.isDark ? 0.90 : 0.94);
    final textColor = deviceColorStyle.isDark
        ? CupertinoColors.white
        : const Color(0xFF111418);

    return SizedBox(
      height: 42,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? const Color(0x1626D98B)
                          : (deviceColorStyle.isDark
                                ? CupertinoColors.white.withValues(alpha: 0.08)
                                : CupertinoColors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isPlaying
                            ? const Color(0x3326D98B)
                            : (deviceColorStyle.isDark
                                  ? CupertinoColors.white.withValues(alpha: 0.12)
                                  : CupertinoColors.black.withValues(alpha: 0.06)),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlaying
                              ? CupertinoIcons.waveform_path_ecg
                              : CupertinoIcons.music_note,
                          size: 14,
                          color: isPlaying
                              ? const Color(0xFF26D98B)
                              : textColor.withValues(alpha: 0.62),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
