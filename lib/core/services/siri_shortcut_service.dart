import 'dart:async';
import 'dart:io';

import 'package:dopi/core/services/debug_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final siriShortcutServiceProvider = Provider<void>((ref) {
  if (kIsWeb || !Platform.isIOS) {
    return;
  }
  final controller = _SiriShortcutController(ref);
  controller.donateDefaultShortcuts();
});

class _SiriShortcutController {
  static const MethodChannel _channel = MethodChannel('mo1/siri_shortcuts');

  const _SiriShortcutController(this._ref);

  final Ref _ref;

  void donateDefaultShortcuts() {
    const shortcuts = [
      _ShortcutDonation(
        identifier: 'now-playing',
        title: 'Open doPi Now Playing',
        suggestedPhrase: 'Open doPi now playing',
        url: 'dopi://now-playing',
      ),
      _ShortcutDonation(
        identifier: 'play-pause',
        title: 'Play or Pause doPi',
        suggestedPhrase: 'Play or pause doPi',
        url: 'dopi://action/play-pause',
      ),
      _ShortcutDonation(
        identifier: 'next',
        title: 'Next doPi Song',
        suggestedPhrase: 'Skip in doPi',
        url: 'dopi://action/next',
      ),
      _ShortcutDonation(
        identifier: 'previous',
        title: 'Previous doPi Song',
        suggestedPhrase: 'Go back in doPi',
        url: 'dopi://action/previous',
      ),
      _ShortcutDonation(
        identifier: 'eq',
        title: 'Open doPi EQ',
        suggestedPhrase: 'Open doPi EQ',
        url: 'dopi://eq',
      ),
      _ShortcutDonation(
        identifier: 'apple-music',
        title: 'Open doPi Apple Music',
        suggestedPhrase: 'Open Apple Music in doPi',
        url: 'dopi://source/apple-music',
      ),
      _ShortcutDonation(
        identifier: 'navidrome',
        title: 'Open doPi Navidrome',
        suggestedPhrase: 'Open Navidrome in doPi',
        url: 'dopi://source/navidrome',
      ),
      _ShortcutDonation(
        identifier: 'jellyfin',
        title: 'Open doPi Jellyfin',
        suggestedPhrase: 'Open Jellyfin in doPi',
        url: 'dopi://source/jellyfin',
      ),
    ];

    for (final shortcut in shortcuts) {
      unawaited(_donate(shortcut));
    }
  }

  Future<void> _donate(_ShortcutDonation shortcut) async {
    try {
      await _channel.invokeMethod<bool>('donateShortcut', shortcut.toMap());
    } catch (error) {
      _ref.read(debugLogServiceProvider).warning(
        'siri',
        'Shortcut donation failed',
        data: {'identifier': shortcut.identifier, 'error': error},
      );
    }
  }
}

class _ShortcutDonation {
  final String identifier;
  final String title;
  final String suggestedPhrase;
  final String url;

  const _ShortcutDonation({
    required this.identifier,
    required this.title,
    required this.suggestedPhrase,
    required this.url,
  });

  Map<String, Object?> toMap() => {
        'identifier': identifier,
        'title': title,
        'suggestedPhrase': suggestedPhrase,
        'url': url,
      };
}
