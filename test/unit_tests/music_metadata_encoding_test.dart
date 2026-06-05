import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String expectedValue = 'Le curé de Ambon';
  const String malformedValue = '￾䰀攀 挀甀爀 搀攀 䄀洀戀漀渀';

  test('normalizeMetadataString keeps already valid strings unchanged', () {
    expect(normalizeMetadataString(expectedValue), expectedValue);
  });

  test('normalizeMetadataString repairs swapped UTF-16 metadata strings', () {
    expect(normalizeMetadataString(malformedValue), expectedValue);
  });

  test(
    'MusicMetadata.fromAudioMetadata normalizes malformed metadata fields',
    () {
      final audioMetadata = AudioMetadata(
        album: malformedValue,
        artist: malformedValue,
        title: malformedValue,
        file: File('test.mp3'),
      );

      final metadata = MusicMetadata.fromAudioMetadata(audioMetadata, null, 0);

      expect(metadata.trackName, expectedValue);
      expect(metadata.albumName, expectedValue);
      expect(metadata.albumArtistName, expectedValue);
      expect(metadata.trackArtistNames, [expectedValue]);
    },
  );

  test('MusicMetadata falls back to file names when tags are unknown', () {
    final audioMetadata = AudioMetadata(
      album: 'Unknown Album',
      artist: 'Unknown Artist',
      title: 'Unknown Song',
      file: File('/music/Album Name/01 - Real Artist - Real Title.mp3'),
    );

    final metadata = MusicMetadata.fromAudioMetadata(
      audioMetadata,
      null,
      0,
      fallbackLyrics: '[00:01.00] lyric line',
    );

    expect(metadata.trackName, 'Real Title');
    expect(metadata.trackArtistNames, ['Real Artist']);
    expect(metadata.albumName, 'Album Name');
    expect(metadata.albumArtistName, 'Real Artist');
    expect(metadata.lyrics, '[00:01.00] lyric line');
  });

}
