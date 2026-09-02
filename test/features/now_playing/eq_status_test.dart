import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/services/native_eq_player_service.dart';
import 'package:dopi/features/now_playing/utils/eq_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const neutral = [0.0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  const rock = [5.0, 4, 3, 0, -2, 0, 2, 4, 5, 5];

  MusicMetadata localTrack() => MusicMetadata(
        trackName: 'Local MP3',
        filePath: '/tmp/local.mp3',
        isOnDevice: true,
      );

  NativeEqPlaybackSnapshot snapshot({
    bool isLoaded = true,
    String? error,
  }) => NativeEqPlaybackSnapshot(
        isSupported: true,
        isLoaded: isLoaded,
        isPlaying: isLoaded,
        currentIndex: 0,
        position: Duration.zero,
        duration: const Duration(minutes: 3),
        completionSerial: 0,
        completedIndex: -1,
        error: error,
      );

  test('reports saved preset when native curve is actually loaded', () {
    final status = buildEqStatusText(
      currentMetadata: localTrack(),
      savedBandGainsDb: rock,
      savedPreampDb: -5,
      savedTitle: 'Rock',
      runtimeState: const NativeEqRuntimeState(
        presetName: 'rock',
        displayName: 'Rock',
        bandGainsDb: rock,
        preampDb: -5,
      ),
      snapshot: snapshot(),
      nativeEqFailure: null,
    );

    expect(status, 'EQ active: Rock');
  });

  test('reports boosted live curve while saved EQ is off', () {
    final status = buildEqStatusText(
      currentMetadata: localTrack(),
      savedBandGainsDb: neutral,
      savedPreampDb: 0,
      savedTitle: 'Off',
      runtimeState: const NativeEqRuntimeState(
        bandGainsDb: rock,
        preampDb: -5,
      ),
      snapshot: snapshot(),
      nativeEqFailure: null,
    );

    expect(status, 'EQ preview: Custom Preview');
  });

  test('does not claim saved EQ is active while preview is flat', () {
    final status = buildEqStatusText(
      currentMetadata: localTrack(),
      savedBandGainsDb: rock,
      savedPreampDb: -5,
      savedTitle: 'Rock',
      runtimeState: const NativeEqRuntimeState(
        presetName: 'custom_preview',
        displayName: 'Custom Preview',
        bandGainsDb: neutral,
        preampDb: 0,
      ),
      snapshot: snapshot(),
      nativeEqFailure: null,
    );

    expect(status, 'EQ preview: Off');
  });

  test('failure wins over stale active state', () {
    final status = buildEqStatusText(
      currentMetadata: localTrack(),
      savedBandGainsDb: rock,
      savedPreampDb: -5,
      savedTitle: 'Rock',
      runtimeState: const NativeEqRuntimeState(
        presetName: 'rock',
        displayName: 'Rock',
        bandGainsDb: rock,
        preampDb: -5,
      ),
      snapshot: snapshot(),
      nativeEqFailure: 'Native EQ player has no loaded audio.',
    );

    expect(status, 'EQ failed: select song to retry');
  });

  test('unloaded native engine cannot report EQ active', () {
    final status = buildEqStatusText(
      currentMetadata: localTrack(),
      savedBandGainsDb: rock,
      savedPreampDb: -5,
      savedTitle: 'Rock',
      runtimeState: const NativeEqRuntimeState(
        presetName: 'rock',
        displayName: 'Rock',
        bandGainsDb: rock,
        preampDb: -5,
      ),
      snapshot: snapshot(isLoaded: false),
      nativeEqFailure: null,
    );

    expect(status, 'EQ not applied: Rock');
  });

  test('Apple Music remains explicitly unsupported for native EQ', () {
    final status = buildEqStatusText(
      currentMetadata: MusicMetadata(
        trackName: 'Catalog',
        filePath: '${MusicMetadata.appleMusicCatalogPathPrefix}123',
        isOnDevice: false,
      ),
      savedBandGainsDb: rock,
      savedPreampDb: -5,
      savedTitle: 'Rock',
      runtimeState: const NativeEqRuntimeState.neutral(),
      snapshot: NativeEqPlaybackSnapshot.unsupported(),
      nativeEqFailure: null,
    );

    expect(status, 'EQ unavailable: Apple Music');
  });
}
