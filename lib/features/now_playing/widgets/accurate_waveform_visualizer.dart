import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

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
      final waveFile = File(
        '${waveDirectory.path}/${_safeWaveName(filePath)}.wave',
      );

      _waveformSubscription = JustWaveform.extract(
        audioInFile: File(filePath),
        waveOutFile: waveFile,
        zoom: const WaveformZoom.pixelsPerSecond(80),
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
        return RepaintBoundary(
          child: CustomPaint(
            painter: _WaveformBarsPainter(
              waveform: _waveform,
              position: position,
              duration: duration,
              extractionProgress: _extractionProgress,
              showExtractionProgress: _canExtractWaveform && _waveform == null,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _WaveformBarsPainter extends CustomPainter {
  final Waveform? waveform;
  final Duration position;
  final Duration duration;
  final double extractionProgress;
  final bool showExtractionProgress;

  const _WaveformBarsPainter({
    required this.waveform,
    required this.position,
    required this.duration,
    required this.extractionProgress,
    required this.showExtractionProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final radius = Radius.circular(size.height / 2);
    final backgroundRect = Offset.zero & size;
    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          CupertinoColors.black.withValues(alpha: 0.24),
          CupertinoColors.white.withValues(alpha: 0.10),
          CupertinoColors.black.withValues(alpha: 0.18),
        ],
      ).createShader(backgroundRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(backgroundRect, radius),
      backgroundPaint,
    );

    final progress = _durationRatio(position, _effectiveDuration);
    final barCount = (size.width / 5.6).clamp(24, 52).round();
    final gap = max(2.0, size.width / 95);
    final barWidth = max(2.2, (size.width - gap * (barCount - 1)) / barCount);
    final centerY = size.height / 2;
    final maxBarHeight = size.height * 0.74;
    final minBarHeight = max(5.0, size.height * 0.18);
    final activeGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFFF8F7FF), Color(0xFF66FFE0), Color(0xFFFF55D8)],
    ).createShader(backgroundRect);
    final inactivePaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.28);
    final activePaint = Paint()..shader = activeGradient;
    final currentPaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.94);

    final currentBar = (progress * (barCount - 1)).round();
    for (var index = 0; index < barCount; index++) {
      final ratio = barCount == 1 ? 0.0 : index / (barCount - 1);
      final sourceAmplitude = waveform == null
          ? _fallbackAmplitude(index, ratio)
          : _waveformAmplitude(ratio);
      final distanceToCurrent = (index - currentBar).abs();
      final currentBoost = max(0.0, 1 - distanceToCurrent / 3.2);
      final amplitude = (sourceAmplitude + currentBoost * 0.18)
          .clamp(0.0, 1.0)
          .toDouble();
      final barHeight = lerpDouble(minBarHeight, maxBarHeight, amplitude)!;
      final left = index * (barWidth + gap);
      final top = centerY - barHeight / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );
      final isActive = ratio <= progress;
      final isCurrent = distanceToCurrent <= 1;
      canvas.drawRRect(rect, isCurrent ? currentPaint : isActive ? activePaint : inactivePaint);
    }

    final playheadX = (progress * size.width).clamp(0.0, size.width).toDouble();
    final playheadPaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..color = const Color(0xFF66FFE0).withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(Offset(playheadX, centerY), size.height * 0.38, glowPaint);
    canvas.drawLine(
      Offset(playheadX, size.height * 0.15),
      Offset(playheadX, size.height * 0.85),
      playheadPaint,
    );

    if (showExtractionProgress && extractionProgress > 0 && extractionProgress < 1) {
      final loadingPaint = Paint()
        ..color = CupertinoColors.white.withValues(alpha: 0.36)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(0, size.height - 1.5),
        Offset(size.width * extractionProgress, size.height - 1.5),
        loadingPaint,
      );
    }
  }

  Duration get _effectiveDuration {
    final waveformDuration = waveform?.duration;
    if (duration > Duration.zero) {
      return duration;
    }
    return waveformDuration ?? Duration.zero;
  }

  double _waveformAmplitude(double ratio) {
    final currentWaveform = waveform;
    if (currentWaveform == null || currentWaveform.length == 0) {
      return 0.35;
    }
    final sampleIndex = (ratio * (currentWaveform.length - 1))
        .round()
        .clamp(0, currentWaveform.length - 1)
        .toInt();
    final minSample = currentWaveform.getPixelMin(sampleIndex);
    final maxSample = currentWaveform.getPixelMax(sampleIndex);
    final divisor = currentWaveform.flags == 0 ? 32768.0 : 128.0;
    final amplitude = max(minSample.abs(), maxSample.abs()) / divisor;
    return amplitude.clamp(0.14, 1.0).toDouble();
  }

  double _fallbackAmplitude(int index, double ratio) {
    final phase = position.inMilliseconds / 260.0;
    final waveA = sin(index * 0.72 + phase).abs();
    final waveB = sin(index * 0.31 + phase * 0.58 + ratio * pi).abs();
    return (0.18 + waveA * 0.38 + waveB * 0.30)
        .clamp(0.12, 0.86)
        .toDouble();
  }

  double _durationRatio(Duration value, Duration total) {
    if (total.inMilliseconds <= 0) {
      return 0;
    }
    return (value.inMilliseconds / total.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  bool shouldRepaint(covariant _WaveformBarsPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.position != position ||
        oldDelegate.duration != duration ||
        oldDelegate.extractionProgress != extractionProgress ||
        oldDelegate.showExtractionProgress != showExtractionProgress;
  }
}
