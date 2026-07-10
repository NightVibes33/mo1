import 'package:dope/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:dope/features/music/navidrome/models/navidrome_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final navidromeConnectionProvider =
    NotifierProvider<NavidromeConnectionNotifier, NavidromeConnection?>(
      NavidromeConnectionNotifier.new,
    );

class NavidromeConnectionNotifier extends Notifier<NavidromeConnection?> {
  static const String _serverUrlKey = 'navidrome.serverUrl';
  static const String _usernameKey = 'navidrome.username';
  static const String _passwordKey = 'navidrome.password';

  @override
  NavidromeConnection? build() {
    final preferences = ref
        .watch(sharedPreferencesWithCacheProvider)
        .valueOrNull;
    if (preferences == null) {
      return null;
    }

    final connection = NavidromeConnection(
      serverUrl: preferences.getString(_serverUrlKey) ?? '',
      username: preferences.getString(_usernameKey) ?? '',
      password: preferences.getString(_passwordKey) ?? '',
    ).normalized();

    return connection.isComplete ? connection : null;
  }

  Future<void> save(NavidromeConnection connection) async {
    final preferences = await ref.read(
      sharedPreferencesWithCacheProvider.future,
    );
    final normalizedConnection = connection.normalized();
    await preferences.setString(_serverUrlKey, normalizedConnection.serverUrl);
    await preferences.setString(_usernameKey, normalizedConnection.username);
    await preferences.setString(_passwordKey, normalizedConnection.password);
    state = normalizedConnection;
  }

  Future<void> disconnect() async {
    final preferences = await ref.read(
      sharedPreferencesWithCacheProvider.future,
    );
    await preferences.remove(_serverUrlKey);
    await preferences.remove(_usernameKey);
    await preferences.remove(_passwordKey);
    state = null;
  }
}
