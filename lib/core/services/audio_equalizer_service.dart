import 'dart:io';

import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioEqualizerServiceProvider =
    AsyncNotifierProvider<AudioEqualizerServiceNotifier, void>(
      AudioEqualizerServiceNotifier.new,
    );

class AudioEqualizerServiceNotifier extends AsyncNotifier<void> {
  static const _channel = MethodChannel('mo1/equalizer');

  @override
  Future<void> build() async {}

  Future<void> applyPreset(EqualizerPreset preset) async {
    if (!Platform.isIOS) return;

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setPreset',
        {
          'presetName': preset.title,
          'bandGainsDb': preset.approximateBandGainsDb,
        },
      );
      final isApplied = result?['isApplied'] as bool? ?? false;
      if (!isApplied) {
        final msg = result?['message'] as String? ?? 'unknown reason';
        // ignore: avoid_print
        print('[EQ] Preset "${preset.title}" not applied: $msg');
      }
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[EQ] PlatformException applying preset: ${e.message}');
    }
  }
}
