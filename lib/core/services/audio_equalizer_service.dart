import 'package:dope/core/services/debug_log_service.dart';
import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioEqualizerServiceProvider = Provider<AudioEqualizerService>((ref) {
  return AudioEqualizerService(ref.read(debugLogServiceProvider));
});

class AudioEqualizerService {
  static const MethodChannel _channel = MethodChannel('mo1/equalizer');

  final DebugLogService _debugLogService;
  String? _lastPresetName;
  List<double>? _lastBandGainsDb;
  double? _lastPreampDb;
  AudioEqualizerApplyResult? _lastResult;

  AudioEqualizerService(this._debugLogService);

  Future<AudioEqualizerApplyResult> applyPreset(
    EqualizerPreset preset,
  ) async {
    return applyBandGains(
      presetName: preset.name,
      displayName: preset.title,
      bandGainsDb: preset.approximateBandGainsDb,
      preampDb: preset.preampDb,
    );
  }

  Future<AudioEqualizerApplyResult> applyBandGains({
    required String presetName,
    required String displayName,
    required List<double> bandGainsDb,
    double preampDb = 0,
  }) async {
    final normalizedBandGainsDb = List<double>.unmodifiable(
      bandGainsDb.map((gain) => gain.toDouble()),
    );
    if (_lastPresetName == presetName &&
        listEquals(_lastBandGainsDb, normalizedBandGainsDb) &&
        _lastPreampDb == preampDb &&
        _lastResult != null) {
      return _lastResult!;
    }

    final result = await _applyBandGains(
      presetName: presetName,
      displayName: displayName,
      bandGainsDb: normalizedBandGainsDb,
      preampDb: preampDb,
    );
    _lastPresetName = presetName;
    _lastBandGainsDb = normalizedBandGainsDb;
    _lastPreampDb = preampDb;
    _lastResult = result;
    _logResult(result);
    return result;
  }

  Future<AudioEqualizerApplyResult> _applyBandGains({
    required String presetName,
    required String displayName,
    required List<double> bandGainsDb,
    double preampDb = 0,
  }) async {
    final isNeutral = bandGainsDb.every((gain) => gain == 0);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      if (isNeutral) {
        return AudioEqualizerApplyResult.applied(
          presetName: presetName,
          displayName: displayName,
          backend: 'neutral',
          message: 'Neutral equalizer curve does not require native support.',
          preampDb: preampDb,
        );
      }
      return AudioEqualizerApplyResult.unsupported(
        presetName: presetName,
        displayName: displayName,
        backend: defaultTargetPlatform.name,
        message: 'Native equalizer is not implemented on this platform.',
        preampDb: preampDb,
      );
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setPreset',
        {
          'presetName': presetName,
          'bandGainsDb': bandGainsDb,
          'preampDb': preampDb,
        },
      );
      return AudioEqualizerApplyResult.fromMap(
        presetName: presetName,
        displayName: displayName,
        map: result,
      );
    } on MissingPluginException catch (error) {
      return AudioEqualizerApplyResult.unsupported(
        presetName: presetName,
        displayName: displayName,
        backend: 'missing_plugin',
        message: error.message ?? 'Equalizer native plugin is unavailable.',
        preampDb: preampDb,
      );
    } on PlatformException catch (error) {
      return AudioEqualizerApplyResult.unsupported(
        presetName: presetName,
        displayName: displayName,
        backend: error.code,
        message: error.message ?? 'Equalizer native call failed.',
        preampDb: preampDb,
      );
    }
  }

  void _logResult(AudioEqualizerApplyResult result) {
    final data = {
      'preset': result.presetName,
      'displayName': result.displayName,
      'backend': result.backend,
      'message': result.message,
      'preampDb': result.preampDb,
    };
    if (result.isApplied) {
      _debugLogService.info('equalizer', 'Preset applied', data: data);
    } else {
      _debugLogService.warning('equalizer', 'Preset not applied', data: data);
    }
  }
}

class AudioEqualizerApplyResult {
  final String presetName;
  final String displayName;
  final bool isApplied;
  final String backend;
  final String message;
  final double preampDb;

  const AudioEqualizerApplyResult({
    required this.presetName,
    required this.displayName,
    required this.isApplied,
    required this.backend,
    required this.message,
    this.preampDb = 0,
  });

  factory AudioEqualizerApplyResult.applied({
    required String presetName,
    required String displayName,
    required String backend,
    required String message,
    double preampDb = 0,
  }) {
    return AudioEqualizerApplyResult(
      presetName: presetName,
      displayName: displayName,
      isApplied: true,
      backend: backend,
      message: message,
      preampDb: preampDb,
    );
  }

  factory AudioEqualizerApplyResult.unsupported({
    required String presetName,
    required String displayName,
    required String backend,
    required String message,
    double preampDb = 0,
  }) {
    return AudioEqualizerApplyResult(
      presetName: presetName,
      displayName: displayName,
      isApplied: false,
      backend: backend,
      message: message,
      preampDb: preampDb,
    );
  }

  factory AudioEqualizerApplyResult.fromMap({
    required String presetName,
    required String displayName,
    required Map<String, dynamic>? map,
  }) {
    if (map == null) {
      return AudioEqualizerApplyResult.unsupported(
        presetName: presetName,
        displayName: displayName,
        backend: 'unknown',
        message: 'Equalizer native call returned no result.',
      );
    }

    return AudioEqualizerApplyResult(
      presetName: presetName,
      displayName: displayName,
      isApplied: map['isApplied'] == true,
      backend: _stringValue(map['backend'], fallback: 'native'),
      message: _stringValue(map['message']),
      preampDb: _doubleValue(map['preampDb']),
    );
  }
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
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
