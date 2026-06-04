import 'dart:math' as math;

import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/now_playing/widgets/scrubber_bar.dart';
import 'package:classipod/features/now_playing/widgets/seek_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NowPlayingBottomBar extends ConsumerWidget {
  final bool showScrubber;

  const NowPlayingBottomBar({super.key, this.showScrubber = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RepaintBoundary(
      child: StreamBuilder<Duration>(
        stream: ref.read(audioPlayerProvider).positionStream,
        builder: (context, snapshot) {
          final playerIndex = ref.read(audioPlayerProvider).currentIndex ?? 0;
          final metadataList = ref.read(nowPlayingDetailsProvider).metadataList;
          if (metadataList.isEmpty) {
            return const SizedBox.shrink();
          }
          final safeIndex = playerIndex.clamp(0, metadataList.length - 1).toInt();
          final totalDuration = math.max(
            1.0,
            (metadataList[safeIndex].trackDuration ?? 1000) / 1000,
          );
          final currentDuration = (snapshot.data?.inSeconds.toDouble() ?? 0)
              .clamp(0.0, totalDuration)
              .toDouble();
          final remainingDuration = math.max(0.0, totalDuration - currentDuration);

          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _TimeLabel(_formatDuration(currentDuration), alignRight: false),
                const SizedBox(width: 6),
                if (showScrubber)
                  Expanded(
                    child: ScrubberBar(max: totalDuration, value: currentDuration),
                  )
                else
                  Expanded(
                    child: SeekBar(max: totalDuration, value: currentDuration),
                  ),
                const SizedBox(width: 6),
                _TimeLabel('-${_formatDuration(remainingDuration)}', alignRight: true),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(double seconds) {
    final safeSeconds = seconds.isFinite ? seconds.round() : 0;
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

class _TimeLabel extends StatelessWidget {
  final String text;
  final bool alignRight;

  const _TimeLabel(this.text, {required this.alignRight});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 43,
      child: FittedBox(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}
