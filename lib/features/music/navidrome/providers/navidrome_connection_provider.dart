import 'dart:async';

import 'package:dopi/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:dopi/features/music/navidrome/models/navidrome_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final navidromeConnectionProvider =
    NotifierProvider<NavidromeConnectionNotifier, NavidromeConnection?>(
      NavidromeConnectionNotifier.new,
    );

class NavidromeConnectionNotifier extends Notifier<NavidromeConnection?> {
  static const String _serverUrlKey = 'navidrome.serverUrl';
  static const String _usernameKey = 'navidrome.username';
  static const String _passwordKey = 'navidrome.password';
  static const String _audioQualityKey = 'navidrome.audioQuality';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  @override
  NavidromeConnection? build() {
    final preferences = ref
        .watch(sharedPreferencesWithCacheProvider)
        .value;
    if (preferences == null) {
      return null;
    }

    final connection = NavidromeConnection(
      serverUrl: preferences.getString(_serverUrlKey) ?? '',
      username: preferences.getString(_usernameKey) ?? '',
      password: preferences.getString(_passwordKey) ?? '',
      audioQuality: NavidromeAudioQuality.fromName(
        preferences.getString(_audioQualityKey),
      ),
    ).normalized();

    final legacyConnection = connection.isComplete ? connection : null;
    unawaited(_restoreSecureConnection(legacyConnection));
    return legacyConnection;
  }

  Future<void> _restoreSecureConnection(
    NavidromeConnection? legacyConnection,
  ) async {
    try {
      final securePassword = await _secureStorage.read(key: _passwordKey);
      final password = securePassword ?? legacyConnection?.password ?? '';
      if (securePassword == null && password.isNotEmpty) {
        await _secureStorage.write(key: _passwordKey, value: password);
      }
      final preferences = await ref.read(
        sharedPreferencesWithCacheProvider.future,
      );
      if (preferences.containsKey(_passwordKey)) {
        await preferences.remove(_passwordKey);
      }
      final restored = NavidromeConnection(
        serverUrl: preferences.getString(_serverUrlKey) ?? '',
        username: preferences.getString(_usernameKey) ?? '',
        password: password,
        audioQuality: NavidromeAudioQuality.fromName(
          preferences.getString(_audioQualityKey),
        ),
      ).normalized();
      state = restored.isComplete ? restored : null;
    } catch (_) {
      // Keep the legacy connection for this session if Keychain is unavailable.
    }
  }

  Future<void> save(NavidromeConnection connection) async {
    final preferences = await ref.read(
      sharedPreferencesWithCacheProvider.future,
    );
    final normalizedConnection = connection.normalized();
    await preferences.setString(_serverUrlKey, normalizedConnection.serverUrl);
    await preferences.setString(_usernameKey, normalizedConnection.username);
    await _secureStorage.write(
      key: _passwordKey,
      value: normalizedConnection.password,
    );
    await preferences.remove(_passwordKey);
    await preferences.setString(
      _audioQualityKey,
      normalizedConnection.audioQuality.name,
    );
    state = normalizedConnection;
  }

  Future<void> disconnect() async {
    final preferences = await ref.read(
      sharedPreferencesWithCacheProvider.future,
    );
    await preferences.remove(_serverUrlKey);
    await preferences.remove(_usernameKey);
    await preferences.remove(_passwordKey);
    await _secureStorage.delete(key: _passwordKey);
    await preferences.remove(_audioQualityKey);
    state = null;
  }
}


extension NavidromeConnectionQualityActions on NavidromeConnectionNotifier {
  Future<void> updateAudioQuality(NavidromeAudioQuality quality) async {
    final current = state;
    if (current == null) {
      return;
    }
    await save(current.copyWith(audioQuality: quality));
  }
}
