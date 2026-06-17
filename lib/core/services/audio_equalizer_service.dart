import 'dart:io';

import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

final audioEqualizerServiceProvider = Provider<AudioEqualizerService>(
  AudioEqualizerService.new,
);

/// Applies EQ presets to the active audio player.
///
/// On iOS: uses just_audio's [DarwinEqualizer] which is wired directly
/// into the AVAudioEngine graph — no MethodChannel, no native code.
///
/// On other platforms: no-op (EQ handled by platform plugin or not supported).
class AudioEqualizerService {
  AudioEqualizerService(this._ref);

  final Ref _ref;

  Future<void> applyPreset(EqualizerPreset preset) async {
    if (!Platform.isIOS) return;

    final equalizer = _ref.read(iosEqualizerProvider);
    if (equalizer == null) return;

    try {
      final params = await equalizer.parameters;
      final bands = params.bands;

      if (preset == EqualizerPreset.off) {
        // Reset all bands to 0 dB and disable the EQ.
        for (final band in bands) {
          await band.setGain(0.0);
        }
        await equalizer.setEnabled(false);
        return;
      }

      final gains = preset.approximateBandGainsDb;

      // Map preset gains to the equalizer's bands by index.
      // DarwinEqualizer bands are ordered low-to-high frequency,
      // matching the order in approximateBandGainsDb.
      for (var i = 0; i < bands.length && i < gains.length; i++) {
        await bands[i].setGain(gains[i]);
      }
      await equalizer.setEnabled(true);
    } catch (e) {
      // ignore: avoid_print
      print('[AudioEqualizerService] applyPreset failed: $e');
    }
  }
}
