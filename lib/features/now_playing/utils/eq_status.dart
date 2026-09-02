import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/services/native_eq_player_service.dart';

String? buildEqStatusText({
  required MusicMetadata? currentMetadata,
  required List<double> savedBandGainsDb,
  required double savedPreampDb,
  required String savedTitle,
  required NativeEqRuntimeState runtimeState,
  required NativeEqPlaybackSnapshot? snapshot,
  required String? nativeEqFailure,
}) {
  if (currentMetadata == null) {
    return null;
  }

  final savedEqRequested = _hasAudibleProcessing(
    savedBandGainsDb,
    savedPreampDb,
  );
  final runtimeEqRequested = runtimeState.hasAudibleProcessing;
  final hasEqIntent = savedEqRequested || runtimeEqRequested || runtimeState.isPreview;
  if (!hasEqIntent) {
    return null;
  }

  if (currentMetadata.isAppleMusicCatalogTrack) {
    return 'EQ unavailable: Apple Music';
  }

  final failure = _firstNonEmpty([
    nativeEqFailure,
    snapshot?.error,
  ]);
  if (failure != null) {
    return 'EQ failed: select song to retry';
  }

  final nativeLoaded = snapshot?.isSupported == true && snapshot?.isLoaded == true;
  final runtimeMatchesSaved = runtimeState.matchesCurve(
    savedBandGainsDb,
    savedPreampDb,
  );

  if (nativeLoaded) {
    if (!runtimeEqRequested) {
      if (savedEqRequested && !runtimeMatchesSaved) {
        return 'EQ preview: Off';
      }
      return null;
    }

    final runtimeTitle = _firstNonEmpty([
          runtimeState.displayName,
          runtimeMatchesSaved ? savedTitle : null,
        ]) ??
        'Custom Preview';
    if (runtimeState.isPreview || !runtimeMatchesSaved) {
      return 'EQ preview: $runtimeTitle';
    }
    return 'EQ active: $runtimeTitle';
  }

  if (savedEqRequested) {
    return 'EQ not applied: $savedTitle';
  }
  return null;
}

bool _hasAudibleProcessing(List<double> gains, double preampDb) {
  return gains.any((gain) => gain.abs() >= 0.001) || preampDb.abs() >= 0.001;
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}
