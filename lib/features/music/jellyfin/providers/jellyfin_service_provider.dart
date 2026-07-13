import 'package:dope/features/music/jellyfin/services/jellyfin_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final jellyfinServiceProvider = Provider<JellyfinService>((ref) {
  return JellyfinService();
});
