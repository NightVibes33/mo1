import 'dart:io';

import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

final audioEqualizerServiceProvider = Provider<AudioEqualizerService>(
  AudioEqualizerService.new,
);

class AudioEqualizerService {
  AudioEqualizerService(this._ref);

  final Ref _ref;
  static const _channel = MethodChannel('mo1/equalizer');

  /// Applies [preset] to the native EQ.
  ///
  /// On iOS this sends the band gains to [AudioEngineManager] via
  /// MethodChannel. The manager applies them to the AVAudioUnitEQ node
  /// that is wired into just_audio's AVAudioEngine graph.
  ///
  /// On other platforms this is a no-op (EQ is handled by the platform
  /// plugin or not supported).
  Future<void> applyPreset(EqualizerPreset preset) async {
    if (!Platform.isIOS) return;
    try {
      // Attempt to wire our EQ node into just_audio's AVAudioEngine first.
      // This is idempotent — if already wired the native side no-ops.
      await _tryWireEngine();

      final gains = preset == EqualizerPreset.off
          ? <double>[]
          : preset.approximateBandGainsDb;

      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setPreset',
        {'bandGainsDb': gains},
      );

      final isApplied = result?['isApplied'] as bool? ?? false;
      if (!isApplied && preset != EqualizerPreset.off) {
        // ignore: avoid_print
        print(
          '[AudioEqualizerService] iOS EQ not applied — '
          'backend: ${result?["backend"]}',
        );
      }
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[AudioEqualizerService] setPreset failed: $e');
    }
  }

  /// Tells the native side to wire its eqNode into just_audio's engine.
  /// Called before every setPreset so the graph is always up to date.
  Future<void> _tryWireEngine() async {
    try {
      await _channel.invokeMethod<void>('wireEngine');
    } catch (_) {
      // Best-effort; setPreset still applies gain values even if wiring fails.
    }
  }
}
