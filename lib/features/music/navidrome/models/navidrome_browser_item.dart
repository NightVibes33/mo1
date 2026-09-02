import 'package:dopi/core/models/music_metadata.dart';

enum NavidromeBrowserItemType {
  action,
  artist,
  album,
  playlist,
  genre,
  folder,
  song,
}

class NavidromeBrowserItem {
  final NavidromeBrowserItemType type;
  final String id;
  final String title;
  final String? subtitle;
  final MusicMetadata? song;

  const NavidromeBrowserItem({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.song,
  });

  const NavidromeBrowserItem.action({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = NavidromeBrowserItemType.action,
       song = null;

  const NavidromeBrowserItem.artist({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = NavidromeBrowserItemType.artist,
       song = null;

  const NavidromeBrowserItem.album({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = NavidromeBrowserItemType.album,
       song = null;

  const NavidromeBrowserItem.playlist({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = NavidromeBrowserItemType.playlist,
       song = null;

  const NavidromeBrowserItem.genre({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = NavidromeBrowserItemType.genre,
       song = null;

  const NavidromeBrowserItem.folder({
    required this.id,
    required this.title,
    this.subtitle,
  }) : type = NavidromeBrowserItemType.folder,
       song = null;

  const NavidromeBrowserItem.song({
    required this.id,
    required this.title,
    this.subtitle,
    required this.song,
  }) : type = NavidromeBrowserItemType.song;
}
