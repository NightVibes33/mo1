import 'package:classipod/features/settings/models/equalizer_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EqualizerPreset.fromName falls back to off for unknown names', () {
    expect(EqualizerPreset.fromName('rock'), EqualizerPreset.rock);
    expect(EqualizerPreset.fromName('not-a-preset'), EqualizerPreset.off);
    expect(EqualizerPreset.fromName(null), EqualizerPreset.off);
  });

  test('Equalizer presets expose ten classic EQ bands', () {
    for (final preset in EqualizerPreset.values) {
      expect(preset.approximateBandGainsDb, hasLength(10));
    }
  });

  test('Only off and flat use neutral curves', () {
    expect(EqualizerPreset.off.hasNeutralCurve, isTrue);
    expect(EqualizerPreset.flat.hasNeutralCurve, isTrue);
    expect(EqualizerPreset.rock.hasNeutralCurve, isFalse);
  });
}
