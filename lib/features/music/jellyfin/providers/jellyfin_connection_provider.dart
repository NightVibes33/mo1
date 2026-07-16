import 'dart:async';

import 'package:dope/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:dope/features/music/jellyfin/models/jellyfin_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final jellyfinConnectionProvider =
    NotifierProvider<JellyfinConnectionNotifier, JellyfinConnection?>(
      JellyfinConnectionNotifier.new,
    );

class JellyfinConnectionNotifier extends Notifier<JellyfinConnection?> {
  static const String _serverUrlKey = 'jellyfin.serverUrl';
  static const String _usernameKey = 'jellyfin.username';
  static const String _accessTokenKey = 'jellyfin.accessToken';
  static const String _userIdKey = 'jellyfin.userId';
  static const String _serverNameKey = 'jellyfin.serverName';
  static const String _deviceIdKey = 'jellyfin.deviceId';
  static const String _audioQualityKey = 'jellyfin.audioQuality';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  @override
  JellyfinConnection? build() {
    final preferences = ref.watch(sharedPreferencesWithCacheProvider).value;
    if (preferences == null) {
      return null;
    }

    final connection = JellyfinConnection(
      serverUrl: preferences.getString(_serverUrlKey) ?? '',
      username: preferences.getString(_usernameKey) ?? '',
      accessToken: preferences.getString(_accessTokenKey) ?? '',
      userId: preferences.getString(_userIdKey) ?? '',
      serverName: preferences.getString(_serverNameKey) ?? '',
      deviceId: preferences.getString(_deviceIdKey) ?? '',
      audioQuality: JellyfinAudioQuality.fromName(
        preferences.getString(_audioQualityKey),
      ),
    ).normalized();

    final legacyConnection = connection.isComplete ? connection : null;
    unawaited(_restoreSecureConnection(legacyConnection));
    return legacyConnection;
  }

  Future<void> _restoreSecureConnection(
    JellyfinConnection? legacyConnection,
  ) async {
    try {
      final secureToken = await _secureStorage.read(key: _accessTokenKey);
      final accessToken = secureToken ?? legacyConnection?.accessToken ?? '';
      if (secureToken == null && accessToken.isNotEmpty) {
        await _secureStorage.write(key: _accessTokenKey, value: accessToken);
      }
      final preferences = await ref.read(
        sharedPreferencesWithCacheProvider.future,
      );
      if (preferences.containsKey(_accessTokenKey)) {
        await preferences.remove(_accessTokenKey);
      }
      final restored = JellyfinConnection(
        serverUrl: preferences.getString(_serverUrlKey) ?? '',
        username: preferences.getString(_usernameKey) ?? '',
        accessToken: accessToken,
        userId: preferences.getString(_userIdKey) ?? '',
        serverName: preferences.getString(_serverNameKey) ?? '',
        deviceId: preferences.getString(_deviceIdKey) ?? '',
        audioQuality: JellyfinAudioQuality.fromName(
          preferences.getString(_audioQualityKey),
        ),
      ).normalized();
      state = restored.isComplete ? restored : null;
    } catch (_) {
      // Keep the legacy connection for this session if Keychain is unavailable.
    }
  }

  Future<void> save(JellyfinConnection connection) async {
    final preferences = await ref.read(sharedPreferencesWithCacheProvider.future);
    final normalizedConnection = connection.normalized();
    await preferences.setString(_serverUrlKey, normalizedConnection.serverUrl);
    await preferences.setString(_usernameKey, normalizedConnection.username);
    await _secureStorage.write(
      key: _accessTokenKey,
      value: normalizedConnection.accessToken,
    );
    await preferences.remove(_accessTokenKey);
    await preferences.setString(_userIdKey, normalizedConnection.userId);
    await preferences.setString(_serverNameKey, normalizedConnection.serverName);
    await preferences.setString(_deviceIdKey, normalizedConnection.deviceId);
    await preferences.setString(
      _audioQualityKey,
      normalizedConnection.audioQuality.name,
    );
    state = normalizedConnection;
  }

  Future<void> disconnect() async {
    final preferences = await ref.read(sharedPreferencesWithCacheProvider.future);
    await preferences.remove(_serverUrlKey);
    await preferences.remove(_usernameKey);
    await preferences.remove(_accessTokenKey);
    await _secureStorage.delete(key: _accessTokenKey);
    await preferences.remove(_userIdKey);
    await preferences.remove(_serverNameKey);
    await preferences.remove(_deviceIdKey);
    await preferences.remove(_audioQualityKey);
    state = null;
  }
}


extension JellyfinConnectionQualityActions on JellyfinConnectionNotifier {
  Future<void> updateAudioQuality(JellyfinAudioQuality quality) async {
    final current = state;
    if (current == null) {
      return;
    }
    await save(current.copyWith(audioQuality: quality));
  }
}
