import 'dart:async';
import 'dart:io';

import 'package:classipod/core/services/debug_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appleMusicPlaybackServiceProvider = Provider<AppleMusicPlaybackService>(
  (ref) => AppleMusicPlaybackService(ref.read(debugLogServiceProvider)),
);

final appleMusicPlaybackSnapshotProvider =
    StreamProvider.autoDispose<AppleMusicPlaybackSnapshot>((ref) {
  return ref.watch(appleMusicPlaybackServiceProvider).playbackSnapshots();
});

class AppleMusicPlaybackService {
  static const MethodChannel _channel = MethodChannel('mo1/apple_music');

  final DebugLogService _debugLogService;

  const AppleMusicPlaybackService(this._debugLogService);

  bool get isSupported => !kIsWeb && Platform.isIOS;

  Stream<AppleMusicPlaybackSnapshot> playbackSnapshots() async* {
    while (true) {
      yield await playbackSnapshot();
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
  }

  Future<AppleMusicPlaybackSnapshot> playbackSnapshot() async {
    if (!isSupported) {
      return AppleMusicPlaybackSnapshot.unsupported();
    }

    try {
      final rawSnapshot = await _channel.invokeMapMethod<String, dynamic>(
        'playbackSnapshot',
      );
      return AppleMusicPlaybackSnapshot.fromMap(rawSnapshot);
    } on PlatformException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music playback snapshot failed.',
        error: error,
        stackTrace: stackTrace,
      );
      return AppleMusicPlaybackSnapshot.unsupported();
    } on MissingPluginException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music playback bridge is unavailable.',
        error: error,
        stackTrace: stackTrace,
      );
      return AppleMusicPlaybackSnapshot.unsupported();
    }
  }

  Future<bool> playCatalogSong(String catalogId) {
    return playCatalogQueue(catalogIds: [catalogId], startCatalogId: catalogId);
  }

  Future<bool> playCatalogQueue({
    required List<String> catalogIds,
    required String startCatalogId,
  }) async {
    final seenCatalogIds = <String>{};
    final cleanCatalogIds = catalogIds
        .map((catalogId) => catalogId.trim())
        .where((catalogId) => catalogId.isNotEmpty)
        .where(seenCatalogIds.add)
        .toList(growable: false);
    final cleanStartCatalogId = startCatalogId.trim();
    final queueCatalogIds = cleanCatalogIds.contains(cleanStartCatalogId)
        ? cleanCatalogIds
        : [cleanStartCatalogId, ...cleanCatalogIds];
    if (!isSupported ||
        queueCatalogIds.isEmpty ||
        cleanStartCatalogId.isEmpty) {
      _debugLogService.warning(
        'apple_music',
        'Apple Music catalog playback is not supported on this platform.',
        data: {'catalogId': startCatalogId},
      );
      return false;
    }

    try {
      final isPlaying = await _channel.invokeMethod<bool>(
        'playCatalogQueue',
        {
          'catalogIds': queueCatalogIds,
          'startCatalogId': cleanStartCatalogId,
        },
      );
      final didStart = isPlaying ?? false;
      _debugLogService.info(
        'apple_music',
        didStart
            ? 'Started Apple Music catalog queue playback.'
            : 'Apple Music catalog playback did not start.',
        data: {
          'catalogId': cleanStartCatalogId,
          'queueSize': queueCatalogIds.length,
        },
      );
      return didStart;
    } on PlatformException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music catalog playback failed.',
        error: error,
        stackTrace: stackTrace,
        data: {'catalogId': cleanStartCatalogId},
      );
      return false;
    } on MissingPluginException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music playback bridge is unavailable.',
        error: error,
        stackTrace: stackTrace,
        data: {'catalogId': cleanStartCatalogId},
      );
      return false;
    }
  }

  Future<bool> resume() async {
    if (!isSupported) {
      return false;
    }

    try {
      final didResume = await _channel.invokeMethod<bool>('resumePlayback');
      if (didResume ?? false) {
        _debugLogService.info('apple_music', 'Resumed Apple Music playback.');
      }
      return didResume ?? false;
    } on PlatformException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music resume failed.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } on MissingPluginException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music playback bridge is unavailable.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> pause() async {
    if (!isSupported) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('pausePlayback');
      _debugLogService.info('apple_music', 'Paused Apple Music playback.');
    } on PlatformException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music pause failed.',
        error: error,
        stackTrace: stackTrace,
      );
    } on MissingPluginException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music playback bridge is unavailable.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> seekTo(Duration position) async {
    if (!isSupported) {
      return false;
    }

    try {
      final didSeek = await _channel.invokeMethod<bool>(
        'seekToSeconds',
        {'seconds': position.inMilliseconds / 1000},
      );
      return didSeek ?? false;
    } on PlatformException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music seek failed.',
        error: error,
        stackTrace: stackTrace,
        data: {'seconds': position.inSeconds},
      );
      return false;
    } on MissingPluginException catch (error, stackTrace) {
      _debugLogService.error(
        'apple_music',
        'Apple Music playback bridge is unavailable.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> seekBy(Duration delta) async {
    final snapshot = await playbackSnapshot();
    if (!snapshot.isSupported) {
      return false;
    }
    final target = snapshot.position + delta;
    final clampedTarget = target < Duration.zero
        ? Duration.zero
        : target > snapshot.duration
            ? snapshot.duration
            : target;
    return seekTo(clampedTarget);
  }
}

class AppleMusicPlaybackSnapshot {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isSupported;
  final String playbackState;
  final String? catalogId;

  const AppleMusicPlaybackSnapshot({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isSupported,
    required this.playbackState,
    this.catalogId,
  });

  factory AppleMusicPlaybackSnapshot.unsupported() {
    return const AppleMusicPlaybackSnapshot(
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      isSupported: false,
      playbackState: 'unsupported',
    );
  }

  factory AppleMusicPlaybackSnapshot.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return AppleMusicPlaybackSnapshot.unsupported();
    }

    return AppleMusicPlaybackSnapshot(
      position: _durationFromSeconds(map['positionSeconds']),
      duration: _durationFromSeconds(map['durationSeconds']),
      isPlaying: map['isPlaying'] == true,
      isSupported: map['isSupported'] != false,
      playbackState: _stringValue(map['playbackState'], 'unknown'),
      catalogId: _nullableStringValue(map['catalogId']),
    );
  }
}

Duration _durationFromSeconds(Object? value) {
  final seconds = value is num ? value.toDouble() : 0.0;
  if (!seconds.isFinite || seconds <= 0) {
    return Duration.zero;
  }
  return Duration(milliseconds: (seconds * 1000).round());
}

String? _nullableStringValue(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String _stringValue(Object? value, String fallback) {
  return _nullableStringValue(value) ?? fallback;
}
