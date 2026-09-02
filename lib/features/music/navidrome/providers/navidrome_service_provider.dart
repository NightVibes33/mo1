import 'package:dopi/features/music/navidrome/services/navidrome_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final navidromeServiceProvider = Provider<NavidromeService>((ref) {
  return NavidromeService();
});
