import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/services/audio_equalizer_service.dart';
import 'package:dopi/core/services/debug_log_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path_provider/path_provider.dart';

final nativeEqFailureProvider = StateProvider<String?>((_) => null);

final nativeEqRuntimeStateProvider = StateProvider<NativeEqRuntimeState>(
  (_) => const NativeEqRuntimeState.neutral(),
);

final nativeEqPlayerServiceProvider = Provider<NativeEqPlayerService>((ref) {
  return NativeEqPlayerService(
    ref.read(debugLogServiceProvider),
    onFailureChanged: (failure) {
      ref.read(nativeEqFailureProvider.notifier).state = failure;
    },
    onRuntimeStateChanged: (runtimeState) {
      ref.read(nativeEqRuntimeStateProvider.notifier).state = runtimeState;
    },
  );
});

final nativeEqPlaybackActiveProvider = StateProvider<bool>((_) => false);

final nativeEqPlaybackSnapshotProvider =
    StreamProvider.autoDispose<NativeEqPlaybackSnapshot>((ref) {
      return ref.watch(nativeEqPlayerServiceProvider).playbackSnapshots();
    });

class NativeEqRuntimeState {
  static const int bandCount = 10;

  final String? presetName;
  final String? displayName;
  final List<double> bandGainsDb;
  final double preampDb;

  const NativeEqRuntimeState({
    this.presetName,
    this.displayName,
    required this.bandGainsDb,
    this.preampDb = 0,
  });

  const NativeEqRuntimeState.neutral()
    : presetName = null,
      displayName = null,
      bandGainsDb = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      preampDb = 0;

  bool get hasAudibleProcessing =>
      bandGainsDb.any((gain) => gain.abs() >= 0.001) || preampDb.abs() >= 0.001;

  bool get isPreview => presetName == 'custom_preview';

  bool matchesCurve(List<double> gains, double otherPreampDb) {
    final normalized = _normalizeRuntimeBandGains(gains);
    if (normalized.length != bandGainsDb.length ||
        (preampDb - otherPreampDb).abs() >= 0.001) {
      return false;
    }
    for (var index = 0; index < bandGainsDb.length; index++) {
      if ((bandGainsDb[index] - normalized[index]).abs() >= 0.001) {
        return false;
      }
    }
    return true;
  }
}

class PreparedNativeEqQueue {
  final List<Map<String, Object?>> items;
  final List<MusicMetadata> metadataList;
  final List<int> sourceIndexes;
  final int startIndex;

  const PreparedNativeEqQueue({
    required this.items,
    required this.metadataList,
    required this.sourceIndexes,
    required this.startIndex,
  });
}

class NativeEqPlayerService {
  static const MethodChannel _channel = MethodChannel('mo1/native_eq_player');
  static const int _maxCacheBytes = 600 * 1024 * 1024;

  final DebugLogService _debugLogService;
  final void Function(String? failure) _onFailureChanged;
  final void Function(NativeEqRuntimeState runtimeState) _onRuntimeStateChanged;
  final HttpClient _httpClient = HttpClient();
  String? lastLoadFailure;

  NativeEqPlayerService(
    this._debugLogService, {
    required void Function(String? failure) onFailureChanged,
    required void Function(NativeEqRuntimeState runtimeState)
    onRuntimeStateChanged,
  }) : _onFailureChanged = onFailureChanged,
       _onRuntimeStateChanged = onRuntimeStateChanged;

  void _setFailure(String? failure) {
    lastLoadFailure = failure;
    _onFailureChanged(failure);
  }

  void _setRuntimeState({
    String? presetName,
    String? displayName,
    required List<double> bandGainsDb,
    required double preampDb,
  }) {
    _onRuntimeStateChanged(
      NativeEqRuntimeState(
        presetName: presetName,
        displayName: displayName,
        bandGainsDb: _normalizeRuntimeBandGains(bandGainsDb),
        preampDb: preampDb,
      ),
    );
  }

  void _clearRuntimeState() {
    _onRuntimeStateChanged(const NativeEqRuntimeState.neutral());
  }

  bool get isSupported => !kIsWeb && Platform.isIOS;

  Stream<NativeEqPlaybackSnapshot> playbackSnapshots() async* {
    while (true) {
      yield await snapshot();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Stream<Duration> playbackPositions() {
    return playbackSnapshots().map((snapshot) => snapshot.position);
  }

  Future<PreparedNativeEqQueue?> prepareQueue({
    required List<MusicMetadata> metadataList,
    required int startIndex,
  }) async {
    if (!isSupported || metadataList.isEmpty) {
      return null;
    }
    final safeStartIndex = startIndex.clamp(0, metadataList.length - 1).toInt();
    if (metadataList[safeStartIndex].isAppleMusicCatalogTrack) {
      return null;
    }

    // Load only the selected item. Remote queues otherwise block playback while
    // downloading dozens of complete tracks, and queue advancement is already
    // coordinated by the unified source queue.
    final firstPreparedIndex = safeStartIndex;
    final lastPreparedIndex = safeStartIndex;

    final preparedItems = <Map<String, Object?>>[];
    final preparedMetadata = <MusicMetadata>[];
    final sourceIndexes = <int>[];

    for (var index = firstPreparedIndex; index <= lastPreparedIndex; index++) {
      final metadata = metadataList[index];
      if (metadata.isAppleMusicCatalogTrack) {
        continue;
      }
      final sourcePath = metadata.filePath;
      if (sourcePath == null || sourcePath.isEmpty) {
        if (index == safeStartIndex) {
          return null;
        }
        continue;
      }

      final playablePath = metadata.isOnDevice
          ? sourcePath
          : await _cachedRemoteTrack(metadata);
      if (playablePath == null || playablePath.isEmpty) {
        if (index == safeStartIndex) {
          return null;
        }
        continue;
      }

      preparedItems.add({
        'id': metadata.sourceIdentityKey,
        'filePath': playablePath,
        'title': metadata.getTrackName,
        'artist': metadata.getTrackArtistNames ?? metadata.getAlbumArtistName,
        'album': metadata.getAlbumName,
        'durationMs': metadata.trackDuration ?? 0,
      });
      preparedMetadata.add(metadata.copyWith(filePath: metadata.filePath));
      sourceIndexes.add(index);
    }

    if (preparedItems.isEmpty) {
      return null;
    }

    final selectedMetadata = metadataList[safeStartIndex];
    final preparedStartIndex = preparedMetadata.indexWhere(
      (metadata) => metadata.hasSameSourceIdentity(selectedMetadata),
    );
    if (preparedStartIndex == -1) {
      return null;
    }

    return PreparedNativeEqQueue(
      items: preparedItems,
      metadataList: preparedMetadata,
      sourceIndexes: sourceIndexes,
      startIndex: preparedStartIndex,
    );
  }

  Future<bool> loadQueue({
    required PreparedNativeEqQueue queue,
    required List<double> bandGainsDb,
    required double preampDb,
  }) async {
    if (!isSupported) {
      return false;
    }
    try {
      final didLoad = await _channel.invokeMethod<bool>('loadQueue', {
        'items': queue.items,
        'startIndex': queue.startIndex,
        'bandGainsDb': bandGainsDb,
        'preampDb': preampDb,
      });
      final loaded = didLoad ?? false;
      if (loaded) {
        _setFailure(null);
        _setRuntimeState(
          bandGainsDb: bandGainsDb,
          preampDb: preampDb,
        );
        _debugLogService.info(
          'equalizer',
          'Native EQ queue loaded.',
          data: {'queueSize': queue.items.length, 'startIndex': queue.startIndex},
        );
      } else {
        _setFailure('Native EQ rejected the audio queue.');
      }
      return loaded;
    } on PlatformException catch (error, stackTrace) {
      _setFailure(error.message ?? error.code);
      _debugLogService.warning(
        'equalizer',
        'Native EQ queue load failed; falling back.',
        data: {'error': error, 'stackTrace': stackTrace},
      );
      return false;
    } on MissingPluginException catch (error, stackTrace) {
      _setFailure(error.message ?? 'missing_plugin');
      _debugLogService.warning(
        'equalizer',
        'Native EQ player bridge is unavailable.',
        data: {'error': error, 'stackTrace': stackTrace},
      );
      return false;
    }
  }

  Future<bool> play() => _boolMethod('play');
  Future<bool> pause() => _boolMethod('pause');

  Future<bool> stop() async {
    final stopped = await _boolMethod('stop');
    if (stopped) {
      _clearRuntimeState();
    }
    return stopped;
  }

  Future<bool> next() => _boolMethod('next');
  Future<bool> previous() => _boolMethod('previous');

  Future<bool> seekTo(Duration position) {
    return _boolMethod('seekToSeconds', {
      'seconds': position.inMilliseconds / 1000,
    });
  }

  Future<bool> seekToIndex(int index, {Duration position = Duration.zero}) {
    return _boolMethod('seekToIndex', {
      'index': index,
      'seconds': position.inMilliseconds / 1000,
    });
  }

  Future<AudioEqualizerApplyResult> setBandGains({
    required String presetName,
    required String displayName,
    required List<double> bandGainsDb,
    double preampDb = 0,
  }) async {
    if (!isSupported) {
      return AudioEqualizerApplyResult.unsupported(
        presetName: presetName,
        displayName: displayName,
        backend: defaultTargetPlatform.name,
        message: 'Native EQ player is not supported on this platform.',
        preampDb: preampDb,
      );
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setPreset',
        {'bandGainsDb': bandGainsDb, 'preampDb': preampDb},
      );
      final applyResult = AudioEqualizerApplyResult.fromMap(
        presetName: presetName,
        displayName: displayName,
        map: result,
      );
      _setFailure(applyResult.isApplied ? null : applyResult.message);
      if (applyResult.isApplied) {
        _setRuntimeState(
          presetName: presetName,
          displayName: displayName,
          bandGainsDb: bandGainsDb,
          preampDb: preampDb,
        );
      }
      return applyResult;
    } on PlatformException catch (error) {
      _setFailure(error.message ?? error.code);
      return AudioEqualizerApplyResult.unsupported(
        presetName: presetName,
        displayName: displayName,
        backend: error.code,
        message: error.message ?? 'Native EQ preset failed.',
        preampDb: preampDb,
      );
    } on MissingPluginException catch (error) {
      _setFailure(error.message ?? 'missing_plugin');
      return AudioEqualizerApplyResult.unsupported(
        presetName: presetName,
        displayName: displayName,
        backend: 'missing_plugin',
        message: error.message ?? 'Native EQ player bridge is unavailable.',
        preampDb: preampDb,
      );
    }
  }

  Future<bool> setVolume(double value) {
    return _boolMethod('setVolume', {'value': value.clamp(0, 1).toDouble()});
  }

  Future<NativeEqPlaybackSnapshot> snapshot() async {
    if (!isSupported) {
      return NativeEqPlaybackSnapshot.unsupported();
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('snapshot');
      return NativeEqPlaybackSnapshot.fromMap(result);
    } catch (_) {
      return NativeEqPlaybackSnapshot.unsupported();
    }
  }

  Future<bool> _boolMethod(String method, [Map<String, Object?> args = const {}]) async {
    if (!isSupported) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>(method, args);
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _cachedRemoteTrack(MusicMetadata metadata) async {
    final urlText = metadata.filePath;
    if (urlText == null || urlText.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(urlText);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    try {
      final cacheDir = await _eqCacheDirectory();
      await _trimCache(cacheDir);
      final extension = _extensionFromUri(uri);
      final cacheKey = sha1.convert(utf8.encode(metadata.sourceIdentityKey)).toString();
      final file = File('${cacheDir.path}/$cacheKey.$extension');
      if (await file.exists() && await file.length() > 0) {
        await file.setLastModified(DateTime.now());
        return file.path;
      }
      await _downloadToFile(uri, file);
      await _trimCache(cacheDir);
      return await file.exists() && await file.length() > 0 ? file.path : null;
    } catch (error, stackTrace) {
      _debugLogService.warning(
        'equalizer',
        'Remote EQ cache failed.',
        data: {
          'trackName': metadata.trackName,
          'sourceIdentity': metadata.sourceIdentityKey,
          'sourceType': metadata.sourceType.name,
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      return null;
    }
  }

  Future<Directory> _eqCacheDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/dope_native_eq_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _downloadToFile(Uri uri, File file) async {
    final partialFile = File('${file.path}.partial');
    if (await partialFile.exists()) {
      await partialFile.delete();
    }
    final request = await _httpClient.getUrl(uri).timeout(
      const Duration(seconds: 15),
    );
    final response = await request.close().timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final sink = partialFile.openWrite();
    try {
      await response.pipe(sink).timeout(const Duration(minutes: 3));
    } catch (_) {
      await sink.close();
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      rethrow;
    }
    if (!await partialFile.exists() || await partialFile.length() == 0) {
      throw const FileSystemException('Downloaded EQ cache file was empty');
    }
    if (await file.exists()) {
      await file.delete();
    }
    await partialFile.rename(file.path);
  }

  Future<void> _trimCache(Directory dir) async {
    final files = await dir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    var total = 0;
    final entries = <({File file, int length, DateTime modified})>[];
    for (final file in files) {
      final stat = await file.stat();
      total += stat.size;
      entries.add((file: file, length: stat.size, modified: stat.modified));
    }
    if (total <= _maxCacheBytes) {
      return;
    }
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= _maxCacheBytes) {
        break;
      }
      try {
        await entry.file.delete();
        total -= entry.length;
      } catch (_) {}
    }
  }

  String _extensionFromUri(Uri uri) {
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = segment.lastIndexOf('.');
    if (dot == -1 || dot == segment.length - 1) {
      return 'mp3';
    }
    final ext = segment.substring(dot + 1).toLowerCase();
    return ext.length > 5 ? 'mp3' : ext;
  }
}

class NativeEqPlaybackSnapshot {
  final bool isSupported;
  final bool isLoaded;
  final bool isPlaying;
  final int currentIndex;
  final Duration position;
  final Duration duration;
  final int completionSerial;
  final int completedIndex;
  final String? error;
  final double preampDb;

  const NativeEqPlaybackSnapshot({
    required this.isSupported,
    required this.isLoaded,
    required this.isPlaying,
    required this.currentIndex,
    required this.position,
    required this.duration,
    required this.completionSerial,
    required this.completedIndex,
    this.error,
    this.preampDb = 0,
  });

  factory NativeEqPlaybackSnapshot.unsupported() {
    return const NativeEqPlaybackSnapshot(
      isSupported: false,
      isLoaded: false,
      isPlaying: false,
      currentIndex: 0,
      position: Duration.zero,
      duration: Duration.zero,
      completionSerial: 0,
      completedIndex: -1,
      preampDb: 0,
    );
  }

  factory NativeEqPlaybackSnapshot.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return NativeEqPlaybackSnapshot.unsupported();
    }
    return NativeEqPlaybackSnapshot(
      isSupported: map['isSupported'] == true,
      isLoaded: map['isLoaded'] == true,
      isPlaying: map['isPlaying'] == true,
      currentIndex: _intValue(map['currentIndex']),
      position: _durationFromSeconds(map['positionSeconds']),
      duration: _durationFromSeconds(map['durationSeconds']),
      completionSerial: _intValue(map['completionSerial']),
      completedIndex: _intValue(map['completedIndex'], fallback: -1),
      error: map['error'] as String?,
      preampDb: _doubleValue(map['preampDb']),
    );
  }
}

List<double> _normalizeRuntimeBandGains(List<double> gains) {
  return List<double>.unmodifiable(
    List<double>.generate(NativeEqRuntimeState.bandCount, (index) {
      if (index >= gains.length || !gains[index].isFinite) {
        return 0;
      }
      return gains[index].clamp(-12, 12).toDouble();
    }),
  );
}

Duration _durationFromSeconds(Object? value) {
  if (value is int) {
    return Duration(milliseconds: value * 1000);
  }
  if (value is double && value.isFinite) {
    return Duration(milliseconds: (value * 1000).round());
  }
  return Duration.zero;
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

double _doubleValue(Object? value) {
  if (value is double && value.isFinite) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  return 0;
}
