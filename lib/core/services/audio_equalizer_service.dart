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
  EqualizerPreset? _lastPreset;
  AudioEqualizerApplyResult? _lastResult;

  AudioEqualizerService(this._debugLogService);

  Future<AudioEqualizerApplyResult> applyPreset(
    EqualizerPreset preset,
  ) async {
    if (_lastPreset == preset && _lastResult != null) {
      return _lastResult!;
    }

    final result = await _applyPreset(preset);
    _lastPreset = preset;
    _lastResult = result;
    _logResult(result);
    return result;
  }

  Future<AudioEqualizerApplyResult> _applyPreset(
    EqualizerPreset preset,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      if (preset.hasNeutralCurve) {
        return AudioEqualizerApplyResult.applied(
          preset: preset,
          backend: 'neutral',
          message: 'Neutral equalizer curve does not require native support.',
        );
      }
      return AudioEqualizerApplyResult.unsupported(
        preset: preset,
        backend: defaultTargetPlatform.name,
        message: 'Native equalizer is not implemented on this platform.',
      );
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setPreset',
        {
          'presetName': preset.name,
          'bandGainsDb': preset.approximateBandGainsDb,
        },
      );
      return AudioEqualizerApplyResult.fromMap(
        preset: preset,
        map: result,
      );
    } on MissingPluginException catch (error) {
      return AudioEqualizerApplyResult.unsupported(
        preset: preset,
        backend: 'missing_plugin',
        message: error.message ?? 'Equalizer native plugin is unavailable.',
      );
    } on PlatformException catch (error) {
      return AudioEqualizerApplyResult.unsupported(
        preset: preset,
        backend: error.code,
        message: error.message ?? 'Equalizer native call failed.',
      );
    }
  }

  void _logResult(AudioEqualizerApplyResult result) {
    final data = {
      'preset': result.preset.name,
      'backend': result.backend,
      'message': result.message,
    };
    if (result.isApplied) {
      _debugLogService.info('equalizer', 'Preset applied', data: data);
    } else {
      _debugLogService.warning('equalizer', 'Preset not applied', data: data);
    }
  }
}

class AudioEqualizerApplyResult {
  final EqualizerPreset preset;
  final bool isApplied;
  final String backend;
  final String message;

  const AudioEqualizerApplyResult({
    required this.preset,
    required this.isApplied,
    required this.backend,
    required this.message,
  });

  factory AudioEqualizerApplyResult.applied({
    required EqualizerPreset preset,
    required String backend,
    required String message,
  }) {
    return AudioEqualizerApplyResult(
      preset: preset,
      isApplied: true,
      backend: backend,
      message: message,
    );
  }

  factory AudioEqualizerApplyResult.unsupported({
    required EqualizerPreset preset,
    required String backend,
    required String message,
  }) {
    return AudioEqualizerApplyResult(
      preset: preset,
      isApplied: false,
      backend: backend,
      message: message,
    );
  }

  factory AudioEqualizerApplyResult.fromMap({
    required EqualizerPreset preset,
    required Map<String, dynamic>? map,
  }) {
    if (map == null) {
      return AudioEqualizerApplyResult.unsupported(
        preset: preset,
        backend: 'unknown',
        message: 'Equalizer native call returned no result.',
      );
    }

    return AudioEqualizerApplyResult(
      preset: preset,
      isApplied: map['isApplied'] == true,
      backend: _stringValue(map['backend'], fallback: 'native'),
      message: _stringValue(map['message']),
    );
  }
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return fallback;
}
