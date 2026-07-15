import 'dart:async';
import 'dart:io';

import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool get widgetSyncAvailable => !kIsWeb && Platform.isIOS;

final widgetSyncProvider = Provider<void>((ref) {
  if (!widgetSyncAvailable) {
    return;
  }
  final controller = _WidgetSyncController(ref);
  ref.listen(nowPlayingDetailsProvider, (_, __) => controller.scheduleSync());
  ref.listen(settingsPreferencesControllerProvider, (_, __) => controller.scheduleSync());
  ref.onDispose(controller.dispose);
});

class _WidgetSyncController {
  static const MethodChannel _channel = MethodChannel('mo1/widgets');

  _WidgetSyncController(this._ref) {
    scheduleSync(force: true);
  }

  final Ref _ref;
  Timer? _debounce;
  String? _lastSignature;
  bool _disposed = false;

  void scheduleSync({bool force = false}) {
    if (_disposed) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_sync(force: force));
    });
  }

  Future<void> _sync({required bool force}) async {
    if (_disposed) {
      return;
    }
    final nowPlaying = _ref.read(nowPlayingDetailsProvider);
    final settings = _ref.read(settingsPreferencesControllerProvider);
    final metadata = nowPlaying.currentMetadata;
    final queuePreview = <Map<String, Object?>>[];
    if (nowPlaying.metadataList.isNotEmpty) {
      final start = nowPlaying.currentIndex + 1;
      final end = (start + 3).clamp(0, nowPlaying.metadataList.length).toInt();
      for (var index = start; index < end; index++) {
        final item = nowPlaying.metadataList[index];
        queuePreview.add({
          'title': item.getTrackName,
          'artist': item.getTrackArtistNames ?? item.getAlbumArtistName,
          'sourceType': _sourceTypeName(item),
          'isExplicit': item.isExplicit,
          'artworkPath': item.thumbnailPath,
        });
      }
    }

    final sourceType = metadata == null ? 'none' : _sourceTypeName(metadata);
    final eqSupported = metadata != null && !metadata.isAppleMusicCatalogTrack;
    final snapshot = <String, Object?>{
      'schemaVersion': 1,
      'trackTitle': metadata?.getTrackName ?? 'Open døPe',
      'artistName': metadata == null
          ? 'Choose music to start'
          : metadata.getTrackArtistNames ?? metadata.getAlbumArtistName,
      'albumName': metadata?.albumName ?? '',
      'sourceType': sourceType,
      'isExplicit': metadata?.isExplicit ?? false,
      'isPlaying': nowPlaying.isPlaying,
      'queueIndex': metadata == null ? 0 : nowPlaying.currentIndex + 1,
      'queueCount': nowPlaying.metadataList.length,
      'eqName': settings.equalizerDisplayTitle,
      'eqSupported': eqSupported,
      'artworkPath': metadata?.thumbnailPath,
      'lastUpdatedEpochMs': DateTime.now().millisecondsSinceEpoch,
      'deepLink': 'dope://now-playing',
      'queuePreview': queuePreview,
    };
    final signature = snapshot.toString();
    if (!force && signature == _lastSignature) {
      return;
    }
    _lastSignature = signature;
    try {
      await _channel.invokeMethod<void>('writeSnapshot', snapshot);
    } catch (_) {
      // Widget sync must never interrupt playback or app startup.
    }
  }

  String _sourceTypeName(MusicMetadata metadata) {
    switch (metadata.sourceType) {
      case MusicSourceType.appleMusic:
        return 'appleMusic';
      case MusicSourceType.navidrome:
        return 'navidrome';
      case MusicSourceType.jellyfin:
        return 'jellyfin';
      case MusicSourceType.remote:
        return 'remote';
      case MusicSourceType.local:
        return 'mp3';
    }
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
  }
}
