import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:dope/core/models/music_metadata.dart';
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

  test(
    'MusicMetadata splits artist-title values when artist tags are missing',
    () {
      final audioMetadata = AudioMetadata(
        album: 'Unknown Album',
        artist: 'Unknown Artist',
        title: 'D4vd - Sleep Well',
        file: File('/music/imports/D4vd - Sleep Well.mp3'),
      );

      final metadata = MusicMetadata.fromAudioMetadata(audioMetadata, null, 0);

      expect(metadata.trackName, 'Sleep Well');
      expect(metadata.trackArtistNames, ['D4vd']);
      expect(metadata.albumArtistName, 'D4vd');
    },
  );

  test('MusicMetadata ignores converter container junk tags', () {
    final audioMetadata = AudioMetadata(
      album: 'dash',
      artist: 'Lavf61.7.100',
      title: 'mp42',
      file: File('/music/Rihanna - Diamonds.mp3'),
    );

    final metadata = MusicMetadata.fromAudioMetadata(audioMetadata, null, 0);

    expect(metadata.trackName, 'Diamonds');
    expect(metadata.trackArtistNames, ['Rihanna']);
    expect(metadata.albumName, isNull);
    expect(metadata.albumArtistName, 'Rihanna');
  });

  test('MusicMetadata repairs stored converter metadata from filename', () {
    final metadata = MusicMetadata(
      trackName: 'Unknown Song',
      trackArtistNames: ['Lavf61.7.100'],
      albumName: 'dash',
      albumArtistName: 'mp42',
      filePath: '/music/Joji - SLOW DANCING IN THE DARK.mp3',
    ).withFilenameFallbacks();

    expect(metadata.trackName, 'SLOW DANCING IN THE DARK');
    expect(metadata.trackArtistNames, ['Joji']);
    expect(metadata.albumName, isNull);
    expect(metadata.albumArtistName, 'Joji');
  });

  test('MusicMetadata uses original import display name before copied suffix', () {
    final audioMetadata = AudioMetadata(
      album: 'dash',
      artist: 'Lavf61.7.100',
      title: 'mp42',
      file: File('/documents/ClassiPod/imports/Rihanna - Diamonds 2.mp3'),
    );

    final metadata = MusicMetadata.fromAudioMetadata(
      audioMetadata,
      null,
      0,
      fallbackFileName: 'Rihanna - Diamonds.mp3',
    );

    expect(metadata.trackName, 'Diamonds');
    expect(metadata.trackArtistNames, ['Rihanna']);
  });

  test('MusicMetadata strips old import collision suffixes as fallback', () {
    final metadata = MusicMetadata(
      trackName: 'Unknown Song',
      trackArtistNames: ['Lavf61.7.100'],
      filePath: '/documents/ClassiPod/imports/Tate McRae - TIT FOR TAT 2.mp3',
    ).withFilenameFallbacks();

    expect(metadata.trackName, 'TIT FOR TAT');
    expect(metadata.trackArtistNames, ['Tate McRae']);
  });

}
