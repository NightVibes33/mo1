import 'package:dope/core/models/music_metadata.dart';
import 'package:dope/features/music/album/models/album_model.dart';
import 'package:dope/features/music/songs/models/music_metadata_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AlbumModel albumFor(MusicMetadata song) {
    return AlbumModel(
      albumName: 'Legends Never Die',
      albumArtistName: 'Juice WRLD',
      albumSongs: [song],
    );
  }

  test('albums with identical metadata remain separate by source', () {
    final local = albumFor(
      MusicMetadata(
        trackName: 'Track',
        albumName: 'Legends Never Die',
        albumArtistName: 'Juice WRLD',
        filePath: '/imports/track.mp3',
        isOnDevice: true,
      ),
    );
    final appleMusic = albumFor(
      MusicMetadata(
        trackName: 'Track',
        albumName: 'Legends Never Die',
        albumArtistName: 'Juice WRLD',
        filePath: '${MusicMetadata.appleMusicCatalogPathPrefix}1234',
        isOnDevice: false,
      ),
    );

    expect(local.sourceType, MusicSourceType.local);
    expect(appleMusic.sourceType, MusicSourceType.appleMusic);
    expect(local, isNot(equals(appleMusic)));
    expect({local, appleMusic}, hasLength(2));
  });

  test('albums from the same source still merge by album and artist', () {
    final first = albumFor(
      MusicMetadata(filePath: '/imports/one.mp3', isOnDevice: true),
    );
    final second = albumFor(
      MusicMetadata(filePath: '/imports/two.mp3', isOnDevice: true),
    );

    expect(first, equals(second));
    expect(first.hashCode, second.hashCode);
  });

  test('metadata matches preserve local MP3 source identity', () {
    final local = MusicMetadata(
      trackName: 'Unknown Track',
      filePath: '/imports/local-track.mp3',
      isOnDevice: true,
    );
    const match = MusicMetadataMatch(
      source: MusicMetadataSource.itunes,
      id: 'catalog-result',
      title: 'Matched Track',
      artist: 'Matched Artist',
      album: 'Matched Album',
    );

    final updated = match.applyTo(local, thumbnailPath: '/artwork/match.jpg');

    expect(updated.filePath, local.filePath);
    expect(updated.isOnDevice, isTrue);
    expect(updated.sourceType, MusicSourceType.local);
    expect(updated.appleMusicCatalogId, isNull);
  });

  test('empty placeholder albums have no source', () {
    final placeholder = AlbumModel(
      albumName: 'All Songs',
      albumArtistName: '',
      albumSongs: const [],
    );

    expect(placeholder.sourceType, isNull);
  });
}
