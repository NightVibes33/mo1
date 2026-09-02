import 'package:dopi/core/models/music_metadata.dart';

enum SongSortOrder {
  title,
  artist,
  album,
  importOrder;

  String get titleText {
    switch (this) {
      case SongSortOrder.title:
        return 'Title';
      case SongSortOrder.artist:
        return 'Artist';
      case SongSortOrder.album:
        return 'Album';
      case SongSortOrder.importOrder:
        return 'Date Added';
    }
  }

  SongSortOrder get next {
    switch (this) {
      case SongSortOrder.title:
        return SongSortOrder.artist;
      case SongSortOrder.artist:
        return SongSortOrder.album;
      case SongSortOrder.album:
        return SongSortOrder.importOrder;
      case SongSortOrder.importOrder:
        return SongSortOrder.title;
    }
  }

  int compare(MusicMetadata a, MusicMetadata b) {
    switch (this) {
      case SongSortOrder.title:
        return _compareByValues(a, b, [
          (song) => song.getTrackName,
          (song) => song.getTrackArtistNames ?? '',
          (song) => song.getAlbumName,
        ]);
      case SongSortOrder.artist:
        return _compareByValues(a, b, [
          (song) => song.getTrackArtistNames ?? '',
          (song) => song.getTrackName,
          (song) => song.getAlbumName,
        ]);
      case SongSortOrder.album:
        return _compareByValues(a, b, [
          (song) => song.getAlbumName,
          (song) => song.getTrackNumber.toString().padLeft(5, '0'),
          (song) => song.getTrackName,
        ]);
      case SongSortOrder.importOrder:
        final dateComparison =
            b.effectiveAddedAtEpochMs.compareTo(a.effectiveAddedAtEpochMs);
        if (dateComparison != 0) {
          return dateComparison;
        }
        return b.originalSongIndex.compareTo(a.originalSongIndex);
    }
  }

  static SongSortOrder fromName(String? name) {
    return SongSortOrder.values.firstWhere(
      (order) => order.name == name,
      orElse: () => SongSortOrder.title,
    );
  }
}

typedef _SongSortValue = String Function(MusicMetadata metadata);

int _compareByValues(
  MusicMetadata a,
  MusicMetadata b,
  List<_SongSortValue> values,
) {
  for (final value in values) {
    final comparison = _normalized(value(a)).compareTo(_normalized(value(b)));
    if (comparison != 0) {
      return comparison;
    }
  }
  return a.originalSongIndex.compareTo(b.originalSongIndex);
}

String _normalized(String value) => value.trim().toLowerCase();
