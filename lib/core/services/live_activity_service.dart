import 'dart:async';

import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LiveActivitySync extends ConsumerStatefulWidget {
  final Widget child;

  const LiveActivitySync({super.key, required this.child});

  @override
  ConsumerState<LiveActivitySync> createState() => _LiveActivitySyncState();
}

class _LiveActivitySyncState extends ConsumerState<LiveActivitySync> {
  static const MethodChannel _channel = MethodChannel('mo1/live_activity');

  Timer? _timer;
  bool _hasLiveActivity = false;
  String? _lastSignature;

  bool get _canUseLiveActivities {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    if (_canUseLiveActivities) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_syncNow());
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_syncNow());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_canUseLiveActivities) {
      ref.listen(nowPlayingDetailsProvider, (_, _) {
        unawaited(_syncNow(force: true));
      });
    }

    return widget.child;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _syncNow({bool force = false}) async {
    if (!_canUseLiveActivities) {
      return;
    }

    final nowPlaying = ref.read(nowPlayingDetailsProvider);
    final metadata = nowPlaying.currentMetadata;
    if (metadata == null) {
      await _endActivityIfNeeded();
      return;
    }

    final player = ref.read(audioPlayerProvider);
    final position = player.position;
    final duration = player.duration ??
        (metadata.trackDuration == null
            ? null
            : Duration(milliseconds: metadata.trackDuration!));
    final durationSeconds = duration?.inSeconds ?? 0;
    final elapsedSeconds = durationSeconds <= 0
        ? position.inSeconds
        : position.inSeconds.clamp(0, durationSeconds).toInt();
    final progress = durationSeconds <= 0 ? 0.0 : elapsedSeconds / durationSeconds;
    final artist = metadata.getTrackArtistNames ?? metadata.getAlbumArtistName;

    final payload = <String, Object?>{
      'title': metadata.getTrackName,
      'artist': artist,
      'album': metadata.getAlbumName,
      'isPlaying': nowPlaying.isPlaying,
      'elapsed': elapsedSeconds,
      'duration': durationSeconds,
      'progress': progress,
    };
    final signature = payload.entries.map((entry) => '${entry.key}:${entry.value}').join('|');
    if (!force && signature == _lastSignature) {
      return;
    }
    _lastSignature = signature;

    try {
      await _channel.invokeMethod<void>('update', payload);
      _hasLiveActivity = true;
    } on MissingPluginException {
      _hasLiveActivity = false;
    } on PlatformException catch (error) {
      debugPrint('mo1 Live Activity update failed: ${error.message}');
    }
  }

  Future<void> _endActivityIfNeeded() async {
    if (!_hasLiveActivity) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('end');
    } on MissingPluginException {
      // Native side is not available on this platform/build.
    } on PlatformException catch (error) {
      debugPrint('mo1 Live Activity end failed: ${error.message}');
    } finally {
      _hasLiveActivity = false;
      _lastSignature = null;
    }
  }
}
