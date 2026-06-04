import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/services/music_metadata_lookup_service.dart';
import 'package:classipod/features/music/songs/screens/song_edit_screen.dart';
import 'package:classipod/features/music/songs/widgets/lyrics_search_sheet.dart';
import 'package:classipod/features/music/songs/widgets/metadata_match_sheet.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<MusicMetadata?> editSongMetadata(
  BuildContext context,
  MusicMetadata metadata,
) {
  return showCupertinoDialog<MusicMetadata>(
    context: context,
    builder: (_) => SongEditScreen(songMetadata: metadata),
  );
}

Future<MusicMetadata?> matchSongMetadata(
  BuildContext context,
  WidgetRef ref,
  MusicMetadata metadata,
) async {
  final match = await showMetadataMatchSheet(context, metadata);
  if (match == null || !context.mounted) {
    return null;
  }

  String? thumbnailPath;
  try {
    thumbnailPath = await ref
        .read(musicMetadataLookupServiceProvider)
        .cacheArtworkForMatch(match, metadata);
  } catch (_) {
    thumbnailPath = null;
  }

  if (!context.mounted) {
    return null;
  }

  final updatedMetadata = match.applyTo(
    metadata,
    thumbnailPath: thumbnailPath,
  );
  await ref
      .read(nowPlayingDetailsProvider.notifier)
      .updateMetadata(updatedMetadata);
  return updatedMetadata;
}

Future<MusicMetadata?> findLyricsForSong(
  BuildContext context,
  WidgetRef ref,
  MusicMetadata metadata,
) async {
  final lyrics = await showLyricsSearchSheet(context, metadata);
  if (lyrics == null || !context.mounted) {
    return null;
  }

  final updatedMetadata = metadata.copyWith(lyrics: lyrics);
  await ref
      .read(nowPlayingDetailsProvider.notifier)
      .updateMetadata(updatedMetadata);
  return updatedMetadata;
}
