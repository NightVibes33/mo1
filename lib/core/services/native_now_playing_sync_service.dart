import 'dart:async';
import 'dart:io';

import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

final nativeNowPlayingSyncProvider = Provider<void>((ref) {
  if (kIsWeb || !Platform.isIOS) {
    return;
  }

  final controller = _NativeNowPlayingSyncController(ref);
  ref.listen(nowPlayingDetailsProvider, (_, __) {
    unawaited(controller.sync(force: true));
  });
  ref.onDispose(controller.dispose);
});

class _NativeNowPlayingSyncController {
  static const MethodChannel _channel = MethodChannel('mo1/now_playing');

  _NativeNowPlayingSyncController(this._ref) {
    final player = _ref.read(audioPlayerProvider);
    _positionSubscription = player.positionStream.listen((position) {
      final wholeSecond = position.inSeconds;
      if (_lastPositionSecond == wholeSecond) {
        return;
      }
      _lastPositionSecond = wholeSecond;
      unawaited(sync());
    });
    _durationSubscription = player.durationStream.listen((_) {
      unawaited(sync(force: true));
    });
    _playerStateSubscription = player.playerStateStream.listen((_) {
      unawaited(sync(force: true));
    });
    _currentIndexSubscription = player.currentIndexStream.listen((_) {
      _lastPositionSecond = null;
      unawaited(sync(force: true));
    });
    unawaited(sync(force: true));
  }

  final Ref _ref;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;

  bool _disposed = false;
  bool _syncInFlight = false;
  bool _resyncRequested = false;
  int? _lastPositionSecond;
  String? _lastPayloadSignature;

  Future<void> sync({bool force = false}) async {
    if (_disposed) {
      return;
    }
    if (_syncInFlight) {
      _resyncRequested = true;
      return;
    }

    _syncInFlight = true;
    var shouldForce = force;
    try {
      do {
        _resyncRequested = false;
        await _performSync(force: shouldForce);
        shouldForce = false;
      } while (_resyncRequested && !_disposed);
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> _performSync({required bool force}) async {
    final nowPlaying = _ref.read(nowPlayingDetailsProvider);
    final metadata = nowPlaying.currentMetadata;

    if (metadata == null || metadata.isAppleMusicCatalogTrack) {
      await _clearNowPlayingIfNeeded();
      return;
    }

    final player = _ref.read(audioPlayerProvider);
    final durationSeconds =
        player.duration?.inSeconds ?? metadata.getTrackDuration ~/ 1000;
    final rawPositionSeconds = player.position.inSeconds;
    final positionSeconds = durationSeconds > 0
        ? rawPositionSeconds.clamp(0, durationSeconds).toInt()
        : rawPositionSeconds;
    final payload = <String, Object?>{
      'id': metadata.filePath ?? metadata.originalSongIndex.toString(),
      'title': metadata.getTrackName,
      'artist': metadata.getTrackArtistNames ?? metadata.getAlbumArtistName,
      'album': metadata.albumName,
      'durationSeconds': durationSeconds,
      'positionSeconds': positionSeconds,
      'isPlaying': nowPlaying.isPlaying && player.playing,
      'artworkPath': metadata.thumbnailPath,
    };

    final signature = payload.toString();
    if (!force && signature == _lastPayloadSignature) {
      return;
    }

    _lastPayloadSignature = signature;
    try {
      await _channel.invokeMethod<void>('updateNowPlaying', payload);
    } catch (_) {
      // Native sync should never interrupt playback.
    }
  }

  Future<void> _clearNowPlayingIfNeeded() async {
    if (_lastPayloadSignature == null) {
      return;
    }

    _lastPayloadSignature = null;
    try {
      await _channel.invokeMethod<void>('clearNowPlaying');
    } catch (_) {
      // Native sync should never interrupt playback.
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_currentIndexSubscription?.cancel());
  }
}
