import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/features/now_playing/models/now_playing_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final nativeCoreBridgeProvider = Provider<NativeCoreBridge>((_) {
  return NativeCoreBridge();
});

class NativeCoreBridge {
  static const MethodChannel _channel = MethodChannel('mo1/native_core');

  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<bool> syncNowPlaying({
    required NowPlayingSnapshot snapshot,
  }) async {
    if (!isSupported) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'syncNowPlaying',
        snapshot.toJson(),
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> syncLibrarySummary({
    required int totalTracks,
    required int localTracks,
    required int appleMusicTracks,
    required int totalAlbums,
    required String? currentRoute,
  }) async {
    if (!isSupported) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'syncLibrarySummary',
        {
          'totalTracks': totalTracks,
          'localTracks': localTracks,
          'appleMusicTracks': appleMusicTracks,
          'totalAlbums': totalAlbums,
          'currentRoute': currentRoute ?? '',
        },
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> clear() async {
    if (!isSupported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

class NowPlayingSnapshot {
  final int currentIndex;
  final bool isPlaying;
  final String nowPlayingType;
  final int queueLength;
  final String? trackName;
  final String? artist;
  final String? albumName;
  final String? filePath;
  final bool isAppleMusic;
  final bool isOnDevice;
  final String? lyrics;

  const NowPlayingSnapshot({
    required this.currentIndex,
    required this.isPlaying,
    required this.nowPlayingType,
    required this.queueLength,
    required this.trackName,
    required this.artist,
    required this.albumName,
    required this.filePath,
    required this.isAppleMusic,
    required this.isOnDevice,
    required this.lyrics,
  });

  factory NowPlayingSnapshot.fromMetadataList({
    required NowPlayingModel model,
  }) {
    final metadata = model.currentMetadata;
    return NowPlayingSnapshot(
      currentIndex: model.currentIndex,
      isPlaying: model.isPlaying,
      nowPlayingType: model.nowPlayingType.name,
      queueLength: model.metadataList.length,
      trackName: metadata?.getTrackName,
      artist: metadata?.getTrackArtistNames,
      albumName: metadata?.getAlbumName,
      filePath: metadata?.filePath,
      isAppleMusic: metadata?.isAppleMusicCatalogTrack ?? false,
      isOnDevice: metadata?.isOnDevice ?? false,
      lyrics: metadata?.lyrics,
    );
  }

  Map<String, Object?> toJson() => {
        'currentIndex': currentIndex,
        'isPlaying': isPlaying,
        'nowPlayingType': nowPlayingType,
        'queueLength': queueLength,
        'trackName': trackName,
        'artist': artist,
        'albumName': albumName,
        'filePath': filePath,
        'isAppleMusic': isAppleMusic,
        'isOnDevice': isOnDevice,
        'lyrics': lyrics,
      };
}
