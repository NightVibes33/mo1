import 'dart:convert';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final songTransitionAnalysisServiceProvider =
    Provider<SongTransitionAnalysisService>((ref) {
  return SongTransitionAnalysisService(
    ref.read(sharedPreferencesWithCacheProvider).requireValue,
  );
});

class SongTransitionAnalysisService {
  static const _cacheKey = 'songTransitionAnalysisCache.v1';

  final SharedPreferencesWithCache _preferences;

  SongTransitionAnalysisService(this._preferences);

  SongTransitionProfile? cachedProfileFor(MusicMetadata metadata) {
    final path = metadata.filePath;
    if (path == null || path.isEmpty || metadata.isAppleMusicCatalogTrack) {
      return null;
    }
    return _readCache()[path];
  }

  Future<SongTransitionProfile?> profileFor(MusicMetadata metadata) async {
    return cachedProfileFor(metadata);
  }

  Future<void> warmQueue(List<MusicMetadata> metadataList) async {
    // Runtime analysis was intentionally disabled on iOS. The analyzer can
    // destabilize long MP3 playback, while cached/metadata AutoMix timing is
    // enough to keep the feature distinct from simple Crossfade.
  }

  Map<String, SongTransitionProfile> _readCache() {
    final raw = _preferences.getString(_cacheKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return {};
      }
      return decoded.map((key, value) {
        return MapEntry(
          key,
          SongTransitionProfile.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        );
      });
    } catch (_) {
      return {};
    }
  }
}

class SongTransitionProfile {
  final String filePath;
  final double? tempoBpm;
  final double beatStrength;
  final double signalEnergy;
  final double danceability;
  final double overallEnergy;
  final double intensity;
  final double valence;
  final double arousal;
  final double confidence;
  final String? estimatedGenre;
  final String? mood;
  final DateTime analyzedAt;

  const SongTransitionProfile({
    required this.filePath,
    required this.tempoBpm,
    required this.beatStrength,
    required this.signalEnergy,
    required this.danceability,
    required this.overallEnergy,
    required this.intensity,
    required this.valence,
    required this.arousal,
    required this.confidence,
    required this.estimatedGenre,
    required this.mood,
    required this.analyzedAt,
  });

  factory SongTransitionProfile.fromJson(Map<String, dynamic> json) {
    return SongTransitionProfile(
      filePath: json['filePath'] as String,
      tempoBpm: _doubleOrNull(json['tempoBpm']),
      beatStrength: _safeUnit(_doubleOrNull(json['beatStrength'])),
      signalEnergy: _safeUnit(_doubleOrNull(json['signalEnergy'])),
      danceability: _safeUnit(_doubleOrNull(json['danceability'])),
      overallEnergy: _safeUnit(_doubleOrNull(json['overallEnergy'])),
      intensity: _safeUnit(_doubleOrNull(json['intensity'])),
      valence: _safeUnit(_doubleOrNull(json['valence'])),
      arousal: _safeUnit(_doubleOrNull(json['arousal'])),
      confidence: _safeUnit(_doubleOrNull(json['confidence'])),
      estimatedGenre: json['estimatedGenre'] as String?,
      mood: json['mood'] as String?,
      analyzedAt: DateTime.tryParse(json['analyzedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'tempoBpm': tempoBpm,
        'beatStrength': beatStrength,
        'signalEnergy': signalEnergy,
        'danceability': danceability,
        'overallEnergy': overallEnergy,
        'intensity': intensity,
        'valence': valence,
        'arousal': arousal,
        'confidence': confidence,
        'estimatedGenre': estimatedGenre,
        'mood': mood,
        'analyzedAt': analyzedAt.toIso8601String(),
      };
}

double _safeUnit(double? value) {
  if (value == null || value.isNaN || value.isInfinite) {
    return 0;
  }
  return value.clamp(0, 1).toDouble();
}

double? _doubleOrNull(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}
