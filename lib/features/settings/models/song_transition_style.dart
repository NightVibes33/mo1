import 'dart:math' as math;

import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/core/services/song_transition_analysis_service.dart';
import 'package:dope/features/now_playing/models/now_playing_model.dart';

const int minCrossfadeDurationSeconds = 1;
const int maxCrossfadeDurationSeconds = 12;
const int defaultCrossfadeDurationSeconds = 6;

/// Controls how adjacent songs blend into each other.
enum SongTransitionStyle {
  off,
  autoMix,
  crossfade;

  String get titleText {
    switch (this) {
      case SongTransitionStyle.off:
        return 'Off';
      case SongTransitionStyle.autoMix:
        return 'AutoMix';
      case SongTransitionStyle.crossfade:
        return 'Crossfade';
    }
  }

  String get description {
    switch (this) {
      case SongTransitionStyle.off:
        return 'Songs play without blending.';
      case SongTransitionStyle.autoMix:
        return 'Automatic smart timing based on genre and cached track info.';
      case SongTransitionStyle.crossfade:
        return 'Simple timed blend between songs.';
    }
  }

  SongTransitionStyle get next {
    switch (this) {
      case SongTransitionStyle.off:
        return SongTransitionStyle.autoMix;
      case SongTransitionStyle.autoMix:
        return SongTransitionStyle.crossfade;
      case SongTransitionStyle.crossfade:
        return SongTransitionStyle.off;
    }
  }

  Duration transitionDuration({
    required NowPlayingType nowPlayingType,
    required MusicMetadata currentMetadata,
    required int crossfadeDurationSeconds,
    MusicMetadata? nextMetadata,
    SongTransitionProfile? currentProfile,
    SongTransitionProfile? nextProfile,
  }) {
    if (this == SongTransitionStyle.off ||
        nowPlayingType == NowPlayingType.album ||
        _shouldPreserveGap(currentMetadata) ||
        (nextMetadata != null && _shouldPreserveGap(nextMetadata))) {
      return Duration.zero;
    }

    switch (this) {
      case SongTransitionStyle.off:
        return Duration.zero;
      case SongTransitionStyle.crossfade:
        return Duration(
          seconds: normalizedCrossfadeDurationSeconds(
            crossfadeDurationSeconds,
          ),
        );
      case SongTransitionStyle.autoMix:
        return _autoMixDuration(
          currentMetadata,
          nextMetadata,
          currentProfile,
          nextProfile,
        );
    }
  }

  bool get usesAppleMusicSubscription {
    return this == SongTransitionStyle.autoMix;
  }

  static SongTransitionStyle fromName(String? name) {
    return SongTransitionStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => SongTransitionStyle.off,
    );
  }
}

Duration _autoMixDuration(
  MusicMetadata currentMetadata,
  MusicMetadata? nextMetadata,
  SongTransitionProfile? currentProfile,
  SongTransitionProfile? nextProfile,
) {
  final genreText = [
    ...currentMetadata.genres,
    if (nextMetadata != null) ...nextMetadata.genres,
  ].join(' ').toLowerCase();

  final currentBpm = currentProfile?.tempoBpm;
  final nextBpm = nextProfile?.tempoBpm;
  final hasTempoPair = currentBpm != null && nextBpm != null;
  final tempoDifference = hasTempoPair
      ? (currentBpm - nextBpm).abs()
      : double.infinity;
  final energy = math.max(
    currentProfile?.overallEnergy ?? 0,
    nextProfile?.overallEnergy ?? 0,
  );
  final danceability = math.max(
    currentProfile?.danceability ?? 0,
    nextProfile?.danceability ?? 0,
  );
  final beatStrength = math.max(
    currentProfile?.beatStrength ?? 0,
    nextProfile?.beatStrength ?? 0,
  );

  if (hasTempoPair &&
      tempoDifference <= 4 &&
      danceability >= 0.58 &&
      beatStrength >= 0.42) {
    return const Duration(seconds: 10);
  }
  if (hasTempoPair &&
      tempoDifference <= 8 &&
      (danceability >= 0.45 || energy >= 0.55)) {
    return const Duration(seconds: 8);
  }
  if (hasTempoPair && tempoDifference <= 14) {
    return const Duration(seconds: 6);
  }
  if (currentProfile != null || nextProfile != null) {
    return const Duration(seconds: 4);
  }

  if (_containsAny(genreText, const [
    'dance',
    'electronic',
    'edm',
    'house',
    'techno',
    'trance',
    'dubstep',
    'disco',
  ])) {
    return const Duration(seconds: 8);
  }

  if (_containsAny(genreText, const [
    'pop',
    'hip-hop',
    'hip hop',
    'rap',
    'r&b',
    'rhythm',
    'latin',
  ])) {
    return const Duration(seconds: 6);
  }

  if (_containsAny(genreText, const [
    'rock',
    'alternative',
    'country',
    'indie',
  ])) {
    return const Duration(seconds: 4);
  }

  return const Duration(seconds: 5);
}

Duration autoMixStartPosition({
  required Duration duration,
  required Duration transitionDuration,
  SongTransitionProfile? profile,
}) {
  if (duration <= transitionDuration + const Duration(seconds: 3)) {
    return Duration.zero;
  }

  final latestStart = duration - transitionDuration;
  final bpm = profile?.tempoBpm;
  if (bpm == null || bpm <= 0) {
    return latestStart;
  }

  final barMs = (60000 / bpm * 4).round();
  if (barMs <= 0) {
    return latestStart;
  }

  final latestMs = latestStart.inMilliseconds;
  final alignedMs = (latestMs ~/ barMs) * barMs;
  final minStartMs = math.max(0, latestMs - 6000);
  return Duration(milliseconds: math.max(alignedMs, minStartMs));
}

bool _shouldPreserveGap(MusicMetadata metadata) {
  final genreText = metadata.genres.join(' ').toLowerCase();
  return _containsAny(genreText, const [
    'classical',
    'opera',
    'spoken',
    'podcast',
    'audiobook',
    'audio book',
    'comedy',
    'meditation',
    'ambient',
  ]);
}

bool _containsAny(String haystack, List<String> needles) {
  return needles.any(haystack.contains);
}

int normalizedCrossfadeDurationSeconds(int seconds) {
  return seconds
      .clamp(minCrossfadeDurationSeconds, maxCrossfadeDurationSeconds)
      .toInt();
}
