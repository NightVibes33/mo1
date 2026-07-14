import 'dart:async';
import 'dart:io';

import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final deepLinkServiceProvider = Provider<void>((ref) {
  if (kIsWeb || !Platform.isIOS) {
    return;
  }
  final controller = _DeepLinkController(ref);
  ref.onDispose(controller.dispose);
});

class _DeepLinkController {
  static const MethodChannel _channel = MethodChannel('mo1/deep_link');

  _DeepLinkController(this._ref) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'handleLink') {
        await _handle(call.arguments?.toString());
      }
    });
    unawaited(_loadInitialLink());
  }

  final Ref _ref;
  bool _disposed = false;

  Future<void> _loadInitialLink() async {
    try {
      final link = await _channel.invokeMethod<String>('getInitialLink');
      await _handle(link);
    } catch (_) {}
  }

  Future<void> _handle(String? rawLink) async {
    if (_disposed || rawLink == null || rawLink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(rawLink);
    if (uri == null || uri.scheme != 'dope') {
      return;
    }
    final router = _ref.read(routerProvider);
    final parts = <String>[
      if (uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments,
    ];
    if (parts.isEmpty) {
      router.goNamed(Routes.menu.name);
      return;
    }
    if (parts.first == 'action') {
      await _handleAction(parts.length > 1 ? parts[1] : '');
      return;
    }
    switch (parts.first) {
      case 'now-playing':
        router.goNamed(Routes.nowPlaying.name);
        break;
      case 'songs':
      case 'queue':
        router.goNamed(Routes.songs.name);
        break;
      case 'eq':
        router.goNamed(Routes.equalizer.name);
        break;
      case 'source':
        _openSource(parts.length > 1 ? parts[1] : '');
        break;
      default:
        router.goNamed(Routes.menu.name);
        break;
    }
  }

  Future<void> _handleAction(String action) async {
    final audio = _ref.read(audioPlayerServiceProvider.notifier);
    switch (action) {
      case 'play-pause':
        await audio.togglePlayback();
        break;
      case 'next':
        await audio.nextSong();
        break;
      case 'previous':
        await audio.seekBackwards();
        break;
      default:
        _ref.read(routerProvider).goNamed(Routes.nowPlaying.name);
        break;
    }
  }

  void _openSource(String source) {
    final router = _ref.read(routerProvider);
    switch (source) {
      case 'apple-music':
        router.goNamed(Routes.appleMusic.name);
        break;
      case 'navidrome':
        router.goNamed(Routes.navidrome.name);
        break;
      case 'jellyfin':
        router.goNamed(Routes.jellyfin.name);
        break;
      default:
        router.goNamed(Routes.musicMenu.name);
        break;
    }
  }

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}
