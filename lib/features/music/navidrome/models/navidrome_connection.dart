class NavidromeConnection {
  final String serverUrl;
  final String username;
  final String password;

  const NavidromeConnection({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  bool get isComplete =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  NavidromeConnection normalized() {
    final cleanServerUrl = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return NavidromeConnection(
      serverUrl: cleanServerUrl,
      username: username.trim(),
      password: password,
    );
  }
}
