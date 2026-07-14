import 'package:dope/features/settings/models/custom_equalizer_preset.dart';
import 'package:dope/features/settings/models/equalizer_preset.dart';
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

  test('Boosted EQ presets apply negative preamp headroom', () {
    expect(EqualizerPreset.off.preampDb, 0);
    expect(EqualizerPreset.flat.preampDb, 0);
    expect(EqualizerPreset.bassBooster.preampDb, lessThan(0));
    expect(EqualizerPreset.trebleBooster.preampDb, lessThan(0));
    expect(EqualizerPreset.bassBooster.preampDb, greaterThanOrEqualTo(-9));
  });

  test('Custom EQ band gains are normalized and clamped', () {
    final normalized = CustomEqualizerPreset.normalizeBandGains(
      const [99, -99, 1],
    );

    expect(normalized, hasLength(CustomEqualizerPreset.bandCount));
    expect(normalized[0], CustomEqualizerPreset.maxGainDb);
    expect(normalized[1], CustomEqualizerPreset.minGainDb);
    expect(normalized[2], 1);
    expect(normalized[9], 0);
  });

  test('Custom EQ preamp follows strongest positive boost', () {
    expect(CustomEqualizerPreset.recommendedPreampDb(const [-6, -3]), 0);
    expect(
      CustomEqualizerPreset.recommendedPreampDb(const [6]),
      closeTo(-3.9, 0.001),
    );
    expect(
      CustomEqualizerPreset.recommendedPreampDb(const [99]),
      CustomEqualizerPreset.minPreampDb,
    );
  });

  test('Custom EQ IDs include microsecond entropy', () async {
    final first = CustomEqualizerPreset.create(
      name: 'Studio',
      bandGainsDb: const [1, 2, 3],
    );
    await Future<void>.delayed(const Duration(microseconds: 1));
    final second = CustomEqualizerPreset.create(
      name: 'Studio',
      bandGainsDb: const [1, 2, 3],
    );

    expect(first.id, isNot(second.id));
  });
}
