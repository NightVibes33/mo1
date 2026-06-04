import 'dart:async';
import 'dart:math';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:flutter/cupertino.dart';

class LyricsView extends StatefulWidget {
  final String lyrics;
  final Stream<Duration> positionStream;
  final ScrollController scrollController;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.positionStream,
    required this.scrollController,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const double _lineExtent = 34;
  late List<_LyricLine> _lines;
  int _lastFocusedLine = -1;

  @override
  void initState() {
    super.initState();
    _lines = _parseLyrics(widget.lyrics);
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _lines = _parseLyrics(widget.lyrics);
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
        final currentLine = _currentLineIndex(snapshot.data ?? Duration.zero);
        _syncScroll(currentLine);
        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(4, 28, 12, 48),
          itemExtent: _lineExtent,
          itemCount: _lines.length,
          itemBuilder: (context, index) {
            final isCurrent = index == currentLine;
            return AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontSize: isCurrent ? 18 : 15,
                height: 1.25,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                color: isCurrent
                    ? context.appPrimaryTextColor
                    : context.appSecondaryTextColor.withValues(alpha: 0.62),
              ),
              child: Text(
                _lines[index].text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
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
      final position = widget.scrollController.position;
      final viewportOffset = position.viewportDimension * 0.42;
      final target = max(0.0, index * _lineExtent - viewportOffset).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ).toDouble();
      unawaited(
        widget.scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }
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
          padding: const EdgeInsets.only(right: 10, bottom: 24),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
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
