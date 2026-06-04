import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:flutter/cupertino.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';

class AccurateWaveformVisualizer extends StatefulWidget {
  final MusicMetadata? metadata;
  final Stream<Duration> positionStream;
  final Duration? duration;

  const AccurateWaveformVisualizer({
    super.key,
    required this.metadata,
    required this.positionStream,
    required this.duration,
  });

  @override
  State<AccurateWaveformVisualizer> createState() =>
      _AccurateWaveformVisualizerState();
}

class _AccurateWaveformVisualizerState extends State<AccurateWaveformVisualizer> {
  StreamSubscription<WaveformProgress>? _waveformSubscription;
  Waveform? _waveform;
  double _extractionProgress = 0;
  bool _canExtractWaveform = false;

  @override
  void initState() {
    super.initState();
    unawaited(_extractWaveform());
  }

  @override
  void didUpdateWidget(covariant AccurateWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata?.filePath != widget.metadata?.filePath) {
      unawaited(_extractWaveform());
    }
  }

  @override
  void dispose() {
    _waveformSubscription?.cancel();
    super.dispose();
  }

  Future<void> _extractWaveform() async {
    await _waveformSubscription?.cancel();
    _waveformSubscription = null;

    final filePath = widget.metadata?.filePath;
    final isOnDevice = widget.metadata?.isOnDevice ?? true;
    if (filePath == null || !isOnDevice || !File(filePath).existsSync()) {
      if (!mounted) return;
      setState(() {
        _waveform = null;
        _extractionProgress = 0;
        _canExtractWaveform = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _waveform = null;
      _extractionProgress = 0;
      _canExtractWaveform = true;
    });

    try {
      final cacheDirectory = await getTemporaryDirectory();
      final waveDirectory = Directory('${cacheDirectory.path}/classipod-waves');
      waveDirectory.createSync(recursive: true);
      final waveFile = File('${waveDirectory.path}/${_safeWaveName(filePath)}.wave');

      _waveformSubscription = JustWaveform.extract(
        audioInFile: File(filePath),
        waveOutFile: waveFile,
        zoom: const WaveformZoom.pixelsPerSecond(90),
      ).listen(
        (progress) {
          if (!mounted) return;
          setState(() {
            _extractionProgress = progress.progress;
            _waveform = progress.waveform ?? _waveform;
            _canExtractWaveform = true;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _waveform = null;
            _canExtractWaveform = false;
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _waveform = null;
        _canExtractWaveform = false;
      });
    }
  }

  String _safeWaveName(String path) {
    return path
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.positionStream,
      initialData: Duration.zero,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = widget.duration ?? _waveform?.duration ?? Duration.zero;
        final waveform = _waveform;

        return RepaintBoundary(
          child: CustomPaint(
            painter: waveform == null
                ? _ActualProgressPainter(
                    position: position,
                    duration: duration,
                    extractionProgress: _extractionProgress,
                    showExtractionProgress: _canExtractWaveform,
                  )
                : _WaveformPainter(
                    waveform: waveform,
                    position: position,
                    duration: duration,
                  ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Waveform waveform;
  final Duration position;
  final Duration duration;

  _WaveformPainter({
    required this.waveform,
    required this.position,
    required this.duration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final visibleDuration = duration == Duration.zero
        ? waveform.duration
        : duration;
    if (visibleDuration == Duration.zero || waveform.length == 0) return;

    final strokeWidth = max(2.6, size.width / 46);
    final pixelsPerStep = max(5.0, size.width / 22);
    final waveformPixelsPerWindow = max(
      1,
      waveform.positionToPixel(visibleDuration).toInt(),
    );
    final waveformPixelsPerDevicePixel = waveformPixelsPerWindow / size.width;
    final waveformPixelsPerStep = max(
      1.0,
      waveformPixelsPerDevicePixel * pixelsPerStep,
    );
    final playedX = size.width * _durationRatio(position, visibleDuration);
    final sampleStart = -waveform.positionToPixel(Duration.zero) %
        waveformPixelsPerStep;

    final inactivePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = CupertinoColors.white.withValues(alpha: 0.26);

    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    for (var i = sampleStart.toDouble();
        i <= waveformPixelsPerWindow + 1.0;
        i += waveformPixelsPerStep) {
      final sampleIdx = i.toInt().clamp(0, waveform.length - 1).toInt();
      final x = i / waveformPixelsPerDevicePixel;
      if (x < 0 || x > size.width + strokeWidth) {
        continue;
      }

      final minY = _normalise(waveform.getPixelMin(sampleIdx), size.height);
      final maxY = _normalise(waveform.getPixelMax(sampleIdx), size.height);
      final top = max(strokeWidth * 0.75, min(minY, maxY));
      final bottom = min(size.height - strokeWidth * 0.75, max(minY, maxY));
      final paint = x <= playedX ? activePaint : inactivePaint;
      if (x <= playedX) {
        paint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFF4FD8).withValues(alpha: 0.95),
            const Color(0xFF55F3B8).withValues(alpha: 0.82),
          ],
        ).createShader(Rect.fromLTWH(x - strokeWidth, top, strokeWidth * 2, bottom - top));
      } else {
        paint.shader = null;
      }
      canvas.drawLine(
        Offset(x + strokeWidth / 2, top),
        Offset(x + strokeWidth / 2, bottom),
        paint,
      );
    }
  }

  double _normalise(int sample, double height) {
    if (waveform.flags == 0) {
      final y = 32768 + sample.clamp(-32768, 32767).toDouble();
      return height - 1 - y * height / 65536;
    } else {
      final y = 128 + sample.clamp(-128, 127).toDouble();
      return height - 1 - y * height / 256;
    }
  }

  double _durationRatio(Duration value, Duration total) {
    if (total.inMilliseconds <= 0) {
      return 0;
    }
    return (value.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.position != position ||
        oldDelegate.duration != duration;
  }
}

class _ActualProgressPainter extends CustomPainter {
  final Duration position;
  final Duration duration;
  final double extractionProgress;
  final bool showExtractionProgress;

  const _ActualProgressPainter({
    required this.position,
    required this.duration,
    required this.extractionProgress,
    required this.showExtractionProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    final strokeWidth = max(3.0, size.height / 12);
    final basePaint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = CupertinoColors.white.withValues(alpha: 0.2);
    final playedPaint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFFFF4FD8), Color(0xFF55F3B8)],
      ).createShader(Offset.zero & size);

    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), basePaint);
    final playedX = size.width * _durationRatio(position, duration);
    canvas.drawLine(Offset(0, centerY), Offset(playedX, centerY), playedPaint);

    if (showExtractionProgress && extractionProgress > 0 && extractionProgress < 1) {
      final loadingPaint = Paint()
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = CupertinoColors.white.withValues(alpha: 0.45);
      canvas.drawLine(
        Offset(0, size.height - 1.5),
        Offset(size.width * extractionProgress, size.height - 1.5),
        loadingPaint,
      );
    }
  }

  double _durationRatio(Duration value, Duration total) {
    if (total.inMilliseconds <= 0) {
      return 0;
    }
    return (value.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _ActualProgressPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.duration != duration ||
        oldDelegate.extractionProgress != extractionProgress ||
        oldDelegate.showExtractionProgress != showExtractionProgress;
  }
}
