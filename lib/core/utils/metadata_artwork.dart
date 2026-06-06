import 'dart:io';

import 'package:classipod/core/constants/assets.dart';
import 'package:flutter/cupertino.dart';

bool isRemoteArtworkPath(String path) {
  return path.startsWith('http://') || path.startsWith('https://');
}

bool isFileArtworkUri(String path) {
  return path.startsWith('file://');
}

ImageProvider<Object> metadataArtworkProvider(String? path) {
  final cleanPath = path?.trim();
  if (cleanPath == null || cleanPath.isEmpty) {
    return const AssetImage(Assets.defaultAlbumCoverImage);
  }
  if (isRemoteArtworkPath(cleanPath)) {
    return NetworkImage(cleanPath);
  }
  final file = _artworkFile(cleanPath);
  if (file.existsSync()) {
    return FileImage(file);
  }
  return const AssetImage(Assets.defaultAlbumCoverImage);
}

Uri? metadataArtworkUri(String? path) {
  final cleanPath = path?.trim();
  if (cleanPath == null || cleanPath.isEmpty) {
    return null;
  }
  if (isRemoteArtworkPath(cleanPath)) {
    return Uri.tryParse(cleanPath);
  }
  final file = _artworkFile(cleanPath);
  return file.existsSync() ? file.uri : null;
}

File _artworkFile(String path) {
  if (isFileArtworkUri(path)) {
    return File.fromUri(Uri.parse(path));
  }
  return File(path);
}
