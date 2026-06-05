import 'dart:async';
import 'dart:math';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:flutter/cupertino.dart';

class LyricsView extends StatefulWidget {
  final String lyrics;
  final Stream<Duration> positionStream;
  final ScrollController scrollController;
  final Duration timingOffset;
  final ValueChanged<Duration>? onTimingOffsetChanged;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.positionStream,
    required this.scrollController,
    this.timingOffset = Duration.zero,
    this.onTimingOffsetChanged,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const Duration _lyricLead = Duration(milliseconds: 180);
  late List<_LyricLine> _lines;
  late List<GlobalKey> _lineKeys;
  int _lastFocusedLine = -1;

  @override
  void initState() {
    super.initState();
    _lines = _parseLyrics(widget.lyrics);
    _lineKeys = _keysForLines(_lines);
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _lines = _parseLyrics(widget.lyrics);
      _lineKeys = _keysForLines(_lines);
      _lastFocusedLine = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return Center(
        child: Text(
          'No lyrics saved',
          style: TextStyle(
            color: context.appSecondaryTextColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final isTimed = _lines.any((line) => line.timestamp != null);
    if (!isTimed) {
      return _PlainLyricsView(
        lines: _lines,
        scrollController: widget.scrollController,
      );
    }

    return StreamBuilder<Duration>(
      stream: widget.positionStream,
      initialData: Duration.zero,
      builder: (context, snapshot) {
        final currentLine = _currentLineIndex(
          (snapshot.data ?? Duration.zero) + _lyricLead + widget.timingOffset,
        );
        _syncScroll(currentLine);
        return CupertinoScrollbar(
          controller: widget.scrollController,
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(0, 4, 6, 38),
            itemCount: _lines.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _LyricOffsetBar(
                  offset: widget.timingOffset,
                  onChanged: widget.onTimingOffsetChanged,
                );
              }

              final lineIndex = index - 1;
              final isCurrent = lineIndex == currentLine;
              return AnimatedContainer(
                key: _lineKeys[lineIndex],
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? CupertinoColors.black.withValues(alpha: 0.1)
                      : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    fontSize: isCurrent ? 17 : 14,
                    height: 1.28,
                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
                    color: isCurrent
                        ? context.appPrimaryTextColor
                        : context.appSecondaryTextColor.withValues(alpha: 0.68),
                  ),
                  child: Text(
                    _lines[lineIndex].text,
                    softWrap: true,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  int _currentLineIndex(Duration position) {
    var index = 0;
    for (var i = 0; i < _lines.length; i++) {
      final timestamp = _lines[i].timestamp;
      if (timestamp == null) {
        continue;
      }
      if (timestamp <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _syncScroll(int index) {
    if (index == _lastFocusedLine || !widget.scrollController.hasClients) {
      return;
    }
    _lastFocusedLine = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) {
        return;
      }
      final lineContext = _lineKeys[index].currentContext;
      if (lineContext == null) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          lineContext,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: 0.38,
        ),
      );
    });
  }
}

class _LyricOffsetBar extends StatelessWidget {
  final Duration offset;
  final ValueChanged<Duration>? onChanged;

  const _LyricOffsetBar({required this.offset, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final canChange = onChanged != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey5.resolveFrom(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _OffsetButton(
              label: '-0.5s',
              enabled: canChange,
              onPressed: () => _changeBy(-500),
            ),
            Expanded(
              child: Text(
                'Sync ${_formatOffset(offset)}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appPrimaryTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _OffsetButton(
              label: '+0.5s',
              enabled: canChange,
              onPressed: () => _changeBy(500),
            ),
          ],
        ),
      ),
    );
  }

  void _changeBy(int milliseconds) {
    final next = offset + Duration(milliseconds: milliseconds);
    final clamped = next.inMilliseconds.clamp(-5000, 5000).toInt();
    onChanged?.call(Duration(milliseconds: clamped));
  }
}

class _OffsetButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _OffsetButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minSize: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onPressed: enabled ? onPressed : null,
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _formatOffset(Duration offset) {
  final milliseconds = offset.inMilliseconds;
  final sign = milliseconds >= 0 ? '+' : '-';
  final seconds = milliseconds.abs() / 1000;
  return '$sign${seconds.toStringAsFixed(1)}s';
}

List<GlobalKey> _keysForLines(List<_LyricLine> lines) {
  return List<GlobalKey>.generate(lines.length, (_) => GlobalKey());
}

class _PlainLyricsView extends StatelessWidget {
  final List<_LyricLine> lines;
  final ScrollController scrollController;

  const _PlainLyricsView({
    required this.lines,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoScrollbar(
        controller: scrollController,
        child: ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(0, 6, 8, 42),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                lines[index].text,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.bold,
                  color: context.appPrimaryTextColor,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LyricLine {
  final Duration? timestamp;
  final String text;

  const _LyricLine({required this.timestamp, required this.text});
}

List<_LyricLine> _parseLyrics(String lyrics) {
  final lines = <_LyricLine>[];
  final timestampRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]');

  for (final rawLine in lyrics.split(RegExp(r'\r?\n'))) {
    final trimmedLine = rawLine.trim();
    if (trimmedLine.isEmpty) {
      continue;
    }

    final matches = timestampRegex.allMatches(trimmedLine).toList();
    if (matches.isEmpty) {
      lines.add(_LyricLine(timestamp: null, text: trimmedLine));
      continue;
    }

    final text = trimmedLine.replaceAll(timestampRegex, '').trim();
    if (text.isEmpty) {
      continue;
    }
    for (final match in matches) {
      lines.add(_LyricLine(timestamp: _timestampFromMatch(match), text: text));
    }
  }

  lines.sort((a, b) {
    final left = a.timestamp;
    final right = b.timestamp;
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.compareTo(right);
  });
  return lines;
}

Duration _timestampFromMatch(RegExpMatch match) {
  final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
  final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
  final fractionRaw = match.group(3) ?? '0';
  final milliseconds = fractionRaw.length == 1
      ? int.parse(fractionRaw) * 100
      : fractionRaw.length == 2
          ? int.parse(fractionRaw) * 10
          : int.parse(fractionRaw.substring(0, min(3, fractionRaw.length)));
  return Duration(
    minutes: minutes,
    seconds: seconds,
    milliseconds: milliseconds,
  );
}
