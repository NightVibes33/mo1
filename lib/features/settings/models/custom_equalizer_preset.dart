import 'package:flutter/foundation.dart';

class CustomEqualizerPreset {
  static const int bandCount = 10;
  static const double minGainDb = -12;
  static const double maxGainDb = 12;
  static const double minPreampDb = -9;
  static const List<String> bandLabels = [
    '32 Hz',
    '64 Hz',
    '125 Hz',
    '250 Hz',
    '500 Hz',
    '1 kHz',
    '2 kHz',
    '4 kHz',
    '8 kHz',
    '16 kHz',
  ];

  final String id;
  final String name;
  final List<double> bandGainsDb;
  final int createdAtEpochMs;
  final int updatedAtEpochMs;

  const CustomEqualizerPreset({
    required this.id,
    required this.name,
    required this.bandGainsDb,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
  });

  factory CustomEqualizerPreset.create({
    required String name,
    required List<double> bandGainsDb,
  }) {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final normalizedName = _normalizedName(name);
    return CustomEqualizerPreset(
      id: '${now.microsecondsSinceEpoch}_${normalizedName.hashCode.abs()}',
      name: normalizedName,
      bandGainsDb: normalizeBandGains(bandGainsDb),
      createdAtEpochMs: nowMs,
      updatedAtEpochMs: nowMs,
    );
  }

  factory CustomEqualizerPreset.fromJson(Map<String, dynamic> json) {
    return CustomEqualizerPreset(
      id: _stringValue(json['id'], fallback: ''),
      name: _normalizedName(_stringValue(json['name'], fallback: 'Custom EQ')),
      bandGainsDb: normalizeBandGains(_doubleListValue(json['bandGainsDb'])),
      createdAtEpochMs: _intValue(json['createdAtEpochMs']),
      updatedAtEpochMs: _intValue(json['updatedAtEpochMs']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'bandGainsDb': bandGainsDb,
      'createdAtEpochMs': createdAtEpochMs,
      'updatedAtEpochMs': updatedAtEpochMs,
    };
  }

  CustomEqualizerPreset copyWith({
    String? name,
    List<double>? bandGainsDb,
  }) {
    return CustomEqualizerPreset(
      id: id,
      name: _normalizedName(name ?? this.name),
      bandGainsDb: normalizeBandGains(bandGainsDb ?? this.bandGainsDb),
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool get hasNeutralCurve => bandGainsDb.every((gain) => gain == 0);

  double get preampDb => recommendedPreampDb(bandGainsDb);

  String get curveSummary {
    final bass = _average(0, 3);
    final mids = _average(3, 7);
    final treble = _average(7, 10);
    return 'Bass ${_signed(bass)}  Mid ${_signed(mids)}  High ${_signed(treble)}';
  }

  double _average(int start, int end) {
    final values = bandGainsDb.sublist(start, end);
    return values.reduce((a, b) => a + b) / values.length;
  }

  static List<double> normalizeBandGains(List<double> gains) {
    final normalized = <double>[];
    for (var index = 0; index < bandCount; index++) {
      final value = index < gains.length ? gains[index] : 0;
      normalized.add(value.clamp(minGainDb, maxGainDb).toDouble());
    }
    return List.unmodifiable(normalized);
  }

  static double recommendedPreampDb(List<double> gains) {
    final normalized = normalizeBandGains(gains);
    final maxBoost = normalized.fold<double>(0, (max, gain) {
      return gain > max ? gain : max;
    });
    if (maxBoost <= 0) {
      return 0;
    }
    return (-maxBoost * 0.65).clamp(minPreampDb, 0).toDouble();
  }

  static String _normalizedName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Custom EQ' : trimmed;
  }

  static String _signed(double value) {
    final rounded = value.round();
    if (rounded > 0) {
      return '+$rounded dB';
    }
    return '$rounded dB';
  }

  @override
  bool operator ==(Object other) {
    return other is CustomEqualizerPreset &&
        other.id == id &&
        other.name == name &&
        listEquals(other.bandGainsDb, bandGainsDb) &&
        other.createdAtEpochMs == createdAtEpochMs &&
        other.updatedAtEpochMs == updatedAtEpochMs;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(bandGainsDb),
    createdAtEpochMs,
    updatedAtEpochMs,
  );
}

String _stringValue(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return fallback;
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return DateTime.now().millisecondsSinceEpoch;
}

List<double> _doubleListValue(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map((item) => item is num ? item.toDouble() : null)
      .whereType<double>()
      .toList(growable: false);
}
