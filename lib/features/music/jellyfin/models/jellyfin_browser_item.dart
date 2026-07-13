import 'package:dope/core/models/music_metadata.dart';

enum JellyfinBrowserItemType {
  action,
  artist,
  album,
  playlist,
  folder,
  song,
}

class JellyfinBrowserItem {
  final JellyfinBrowserItemType type;
  final String id;
  final String title;
  final String? subtitle;
  final MusicMetadata? song;

  const JellyfinBrowserItem({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.song,
  });

  const JellyfinBrowserItem.action({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = JellyfinBrowserItemType.action,
       song = null;

  const JellyfinBrowserItem.artist({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = JellyfinBrowserItemType.artist,
       song = null;

  const JellyfinBrowserItem.album({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = JellyfinBrowserItemType.album,
       song = null;

  const JellyfinBrowserItem.playlist({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = JellyfinBrowserItemType.playlist,
       song = null;

  const JellyfinBrowserItem.folder({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = JellyfinBrowserItemType.folder,
       song = null;

  const JellyfinBrowserItem.song({
    required this.id,
    required this.title,
    this.subtitle,
    required this.song,
  }) : type = JellyfinBrowserItemType.song;
}
