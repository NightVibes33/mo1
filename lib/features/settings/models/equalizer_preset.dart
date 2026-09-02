import 'package:dopi/features/settings/models/custom_equalizer_preset.dart';

enum EqualizerPreset {
  off,
  acoustic,
  bassBooster,
  bassReducer,
  classical,
  dance,
  deep,
  electronic,
  flat,
  hipHop,
  jazz,
  latin,
  loudness,
  lounge,
  piano,
  pop,
  rhythmAndBlues,
  rock,
  smallSpeakers,
  spokenWord,
  trebleBooster,
  trebleReducer,
  vocalBooster;

  String get title {
    switch (this) {
      case EqualizerPreset.off:
        return 'Off';
      case EqualizerPreset.acoustic:
        return 'Acoustic';
      case EqualizerPreset.bassBooster:
        return 'Bass Booster';
      case EqualizerPreset.bassReducer:
        return 'Bass Reducer';
      case EqualizerPreset.classical:
        return 'Classical';
      case EqualizerPreset.dance:
        return 'Dance';
      case EqualizerPreset.deep:
        return 'Deep';
      case EqualizerPreset.electronic:
        return 'Electronic';
      case EqualizerPreset.flat:
        return 'Flat';
      case EqualizerPreset.hipHop:
        return 'Hip Hop';
      case EqualizerPreset.jazz:
        return 'Jazz';
      case EqualizerPreset.latin:
        return 'Latin';
      case EqualizerPreset.loudness:
        return 'Loudness';
      case EqualizerPreset.lounge:
        return 'Lounge';
      case EqualizerPreset.piano:
        return 'Piano';
      case EqualizerPreset.pop:
        return 'Pop';
      case EqualizerPreset.rhythmAndBlues:
        return 'R&B';
      case EqualizerPreset.rock:
        return 'Rock';
      case EqualizerPreset.smallSpeakers:
        return 'Small Speakers';
      case EqualizerPreset.spokenWord:
        return 'Spoken Word';
      case EqualizerPreset.trebleBooster:
        return 'Treble Booster';
      case EqualizerPreset.trebleReducer:
        return 'Treble Reducer';
      case EqualizerPreset.vocalBooster:
        return 'Vocal Booster';
    }
  }

  List<double> get approximateBandGainsDb {
    switch (this) {
      case EqualizerPreset.off:
      case EqualizerPreset.flat:
        return const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      case EqualizerPreset.acoustic:
        return const [3, 2, 1, 0, 1, 2, 4, 4, 3, 2];
      case EqualizerPreset.bassBooster:
        return const [7, 6, 5, 3, 1, 0, 0, 0, 0, 0];
      case EqualizerPreset.bassReducer:
        return const [-7, -6, -5, -3, -1, 0, 0, 0, 0, 0];
      case EqualizerPreset.classical:
        return const [4, 3, 2, 0, -2, -2, 0, 2, 4, 5];
      case EqualizerPreset.dance:
        return const [6, 5, 3, 0, -2, -1, 1, 3, 4, 3];
      case EqualizerPreset.deep:
        return const [7, 6, 4, 2, 0, -1, -2, -3, -4, -5];
      case EqualizerPreset.electronic:
        return const [5, 4, 2, -1, -3, -2, 1, 3, 5, 6];
      case EqualizerPreset.hipHop:
        return const [6, 5, 4, 2, -1, -2, 0, 2, 4, 5];
      case EqualizerPreset.jazz:
        return const [3, 2, 1, 1, 0, 1, 3, 4, 3, 2];
      case EqualizerPreset.latin:
        return const [4, 3, 1, 0, -1, 1, 3, 5, 5, 3];
      case EqualizerPreset.loudness:
        return const [6, 5, 3, 0, -2, -1, 0, 2, 4, 5];
      case EqualizerPreset.lounge:
        return const [-3, -2, -1, 1, 3, 4, 3, 2, 1, 0];
      case EqualizerPreset.piano:
        return const [-2, -1, 1, 3, 4, 3, 2, 1, 0, -1];
      case EqualizerPreset.pop:
        return const [-2, -1, 0, 3, 5, 5, 4, 2, -1, -2];
      case EqualizerPreset.rhythmAndBlues:
        return const [5, 4, 3, 1, -1, 0, 2, 3, 3, 2];
      case EqualizerPreset.rock:
        return const [5, 4, 3, 0, -2, 0, 2, 4, 5, 5];
      case EqualizerPreset.smallSpeakers:
        return const [-6, -5, -3, 0, 3, 5, 5, 4, 3, 2];
      case EqualizerPreset.spokenWord:
        return const [-6, -5, -3, 0, 4, 6, 5, 3, 0, -2];
      case EqualizerPreset.trebleBooster:
        return const [-1, -1, 0, 0, 1, 2, 4, 5, 6, 7];
      case EqualizerPreset.trebleReducer:
        return const [1, 1, 0, 0, -1, -2, -4, -5, -6, -7];
      case EqualizerPreset.vocalBooster:
        return const [-3, -2, -1, 1, 4, 6, 5, 3, 0, -1];
    }
  }

  double get preampDb =>
      CustomEqualizerPreset.recommendedPreampDb(approximateBandGainsDb);

  bool get hasNeutralCurve {
    return approximateBandGainsDb.every((gain) => gain == 0);
  }

  EqualizerPreset get next {
    final values = EqualizerPreset.values;
    return values[(index + 1) % values.length];
  }

  static EqualizerPreset fromName(String? name) {
    return EqualizerPreset.values.firstWhere(
      (preset) => preset.name == name,
      orElse: () => EqualizerPreset.off,
    );
  }
}
