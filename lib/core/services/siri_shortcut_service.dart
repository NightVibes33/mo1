import 'dart:async';
import 'dart:io';

import 'package:dope/core/services/debug_log_service.dart';
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
        title: 'Open døPe Now Playing',
        suggestedPhrase: 'Open døPe now playing',
        url: 'dope://now-playing',
      ),
      _ShortcutDonation(
        identifier: 'play-pause',
        title: 'Play or Pause døPe',
        suggestedPhrase: 'Play or pause døPe',
        url: 'dope://action/play-pause',
      ),
      _ShortcutDonation(
        identifier: 'next',
        title: 'Next døPe Song',
        suggestedPhrase: 'Skip in døPe',
        url: 'dope://action/next',
      ),
      _ShortcutDonation(
        identifier: 'previous',
        title: 'Previous døPe Song',
        suggestedPhrase: 'Go back in døPe',
        url: 'dope://action/previous',
      ),
      _ShortcutDonation(
        identifier: 'eq',
        title: 'Open døPe EQ',
        suggestedPhrase: 'Open døPe EQ',
        url: 'dope://eq',
      ),
      _ShortcutDonation(
        identifier: 'apple-music',
        title: 'Open døPe Apple Music',
        suggestedPhrase: 'Open Apple Music in døPe',
        url: 'dope://source/apple-music',
      ),
      _ShortcutDonation(
        identifier: 'navidrome',
        title: 'Open døPe Navidrome',
        suggestedPhrase: 'Open Navidrome in døPe',
        url: 'dope://source/navidrome',
      ),
      _ShortcutDonation(
        identifier: 'jellyfin',
        title: 'Open døPe Jellyfin',
        suggestedPhrase: 'Open Jellyfin in døPe',
        url: 'dope://source/jellyfin',
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
