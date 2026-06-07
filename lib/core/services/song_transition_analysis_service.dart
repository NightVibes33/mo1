import 'dart:convert';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:classipod/core/services/debug_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_feature_analyzer/music_feature_analyzer.dart';
import 'package:shared_preferences/shared_preferences.dart';

final songTransitionAnalysisServiceProvider =
    Provider<SongTransitionAnalysisService>((ref) {
  return SongTransitionAnalysisService(
    ref.read(sharedPreferencesWithCacheProvider).requireValue,
    ref.read(debugLogServiceProvider),
  );
});

class SongTransitionAnalysisService {
  static const _cacheKey = 'songTransitionAnalysisCache.v1';

  final SharedPreferencesWithCache _preferences;
  final DebugLogService _debugLogService;
  bool _isInitialized = false;
  Future<void>? _warmupFuture;

  SongTransitionAnalysisService(this._preferences, this._debugLogService);

  SongTransitionProfile? cachedProfileFor(MusicMetadata metadata) {
    final path = metadata.filePath;
    if (path == null || path.isEmpty || metadata.isAppleMusicCatalogTrack) {
      return null;
    }
    return _readCache()[path];
  }

  Future<SongTransitionProfile?> profileFor(MusicMetadata metadata) async {
    final cached = cachedProfileFor(metadata);
    if (cached != null) {
      return cached;
    }
    return analyze(metadata);
  }

  Future<void> warmQueue(List<MusicMetadata> metadataList) async {
    if (_warmupFuture != null) {
      return _warmupFuture;
    }

    final localTracks = metadataList
        .where((metadata) =>
            metadata.filePath != null &&
            metadata.filePath!.isNotEmpty &&
            !metadata.isAppleMusicCatalogTrack &&
            cachedProfileFor(metadata) == null)
        .take(24)
        .toList(growable: false);
    if (localTracks.isEmpty) {
      return;
    }

    _warmupFuture = _warmTracks(localTracks).whenComplete(() {
      _warmupFuture = null;
    });
    return _warmupFuture;
  }

  Future<void> _warmTracks(List<MusicMetadata> metadataList) async {
    for (final metadata in metadataList) {
      await analyze(metadata);
    }
  }

  Future<SongTransitionProfile?> analyze(MusicMetadata metadata) async {
    final path = metadata.filePath;
    if (path == null || path.isEmpty || metadata.isAppleMusicCatalogTrack) {
      return null;
    }

    try {
      await _ensureInitialized();
      final song = _songModelFromMetadata(metadata);
      final features = await MusicFeatureAnalyzer.analyzeSong(song);
      if (features == null) {
        return null;
      }

      final profile = SongTransitionProfile(
        filePath: path,
        tempoBpm: _validBpm(features.tempoBpm),
        beatStrength: _safeUnit(features.beatStrength),
        signalEnergy: _safeUnit(features.signalEnergy),
        danceability: _safeUnit(features.danceability),
        overallEnergy: _safeUnit(features.overallEnergy),
        intensity: _safeUnit(features.intensity),
        valence: _safeUnit(features.valence),
        arousal: _safeUnit(features.arousal),
        confidence: _safeUnit(features.confidence),
        estimatedGenre: _emptyToNull(features.estimatedGenre),
        mood: _emptyToNull(features.mood),
        analyzedAt: DateTime.now(),
      );
      await _writeProfile(profile);
      return profile;
    } catch (error, stackTrace) {
      _debugLogService.error(
        'song_transitions',
        'AutoMix analysis failed.',
        error: error,
        stackTrace: stackTrace,
        data: {'path': path},
      );
      return null;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized || kIsWeb) {
      return;
    }
    _isInitialized = await MusicFeatureAnalyzer.initialize();
  }

  SongModel _songModelFromMetadata(MusicMetadata metadata) {
    return SongModel(
      id: metadata.filePath ?? metadata.originalSongIndex.toString(),
      title: metadata.getTrackName,
      artist: metadata.getTrackArtistNames ?? 'Unknown Artist',
      album: metadata.getAlbumName,
      duration: metadata.trackDuration ?? 0,
      filePath: metadata.filePath ?? '',
      albumArt: metadata.thumbnailPath,
      year: metadata.year,
      genre: metadata.genres.isEmpty ? null : metadata.genres.join(', '),
      trackNumber: metadata.trackNumber,
      discNumber: metadata.discNumber,
      albumArtist: metadata.albumArtistName,
      bitrate: metadata.bitrate,
      mimeType: metadata.mimeType,
    );
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

  Future<void> _writeProfile(SongTransitionProfile profile) async {
    final cache = _readCache();
    cache[profile.filePath] = profile;
    if (cache.length > 600) {
      final sorted = cache.values.toList()
        ..sort((a, b) => b.analyzedAt.compareTo(a.analyzedAt));
      cache
        ..clear()
        ..addEntries(
          sorted.take(500).map((profile) => MapEntry(profile.filePath, profile)),
        );
    }
    await _preferences.setString(
      _cacheKey,
      jsonEncode(cache.map((key, value) => MapEntry(key, value.toJson()))),
    );
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

double? _validBpm(double? bpm) {
  if (bpm == null || bpm.isNaN || bpm.isInfinite || bpm < 45 || bpm > 220) {
    return null;
  }
  return bpm;
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

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
