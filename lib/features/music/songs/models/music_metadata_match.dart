import 'package:dopi/core/models/music_metadata.dart';

enum MusicMetadataSource { itunes, deezer, appleMusic }

extension MusicMetadataSourceLabel on MusicMetadataSource {
  String get label {
    switch (this) {
      case MusicMetadataSource.itunes:
        return 'iTunes';
      case MusicMetadataSource.deezer:
        return 'Deezer';
      case MusicMetadataSource.appleMusic:
        return 'Apple Music';
    }
  }
}

class MusicMetadataMatch {
  final MusicMetadataSource source;
  final String id;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final List<String> genres;
  final String? artworkUrl;
  final DateTime? releaseDate;
  final int? trackNumber;
  final int? trackCount;
  final int? discNumber;
  final int? durationMs;
  final String? previewUrl;
  final String? catalogUrl;
  final String? isrc;
  final int? dateAddedEpochMs;
  final bool isExplicit;

  const MusicMetadataMatch({
    required this.source,
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist = '',
    this.genres = const [],
    this.artworkUrl,
    this.releaseDate,
    this.trackNumber,
    this.trackCount,
    this.discNumber,
    this.durationMs,
    this.previewUrl,
    this.catalogUrl,
    this.isrc,
    this.dateAddedEpochMs,
    this.isExplicit = false,
  });

  String get subtitle {
    final values = [artist, album]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return values.join(' - ');
  }

  MusicMetadata toAppleMusicMetadata({required int originalSongIndex}) {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    final cleanAlbum = album.trim();
    final cleanAlbumArtist = albumArtist.trim();
    return MusicMetadata(
      trackName: cleanTitle.isEmpty ? null : cleanTitle,
      trackArtistNames: cleanArtist.isEmpty ? null : [cleanArtist],
      albumArtistName: cleanAlbumArtist.isEmpty
          ? cleanArtist.isEmpty
              ? null
              : cleanArtist
          : cleanAlbumArtist,
      albumName: cleanAlbum.isEmpty ? null : cleanAlbum,
      genres: genres,
      thumbnailPath: artworkUrl,
      trackNumber: trackNumber,
      albumLength: trackCount,
      discNumber: discNumber,
      year: releaseDate?.year,
      trackDuration: durationMs,
      filePath: '${MusicMetadata.appleMusicCatalogPathPrefix}$id',
      originalSongIndex: originalSongIndex,
      isOnDevice: false,
      isExplicit: isExplicit,
      sourceCreatedAtEpochMs: dateAddedEpochMs,
      importedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  MusicMetadata applyTo(MusicMetadata current, {String? thumbnailPath}) {
    return current.copyWith(
      trackName: title.trim().isEmpty ? null : title.trim(),
      trackArtistNames: artist.trim().isEmpty ? null : [artist.trim()],
      albumArtistName: albumArtist.trim().isEmpty
          ? artist.trim().isEmpty
              ? null
              : artist.trim()
          : albumArtist.trim(),
      albumName: album.trim().isEmpty ? null : album.trim(),
      genres: genres.isEmpty ? null : genres,
      thumbnailPath: thumbnailPath,
      trackNumber: trackNumber,
      albumLength: trackCount,
      discNumber: discNumber,
      year: releaseDate?.year,
      trackDuration: durationMs,
      isExplicit: isExplicit,
    );
  }
}
