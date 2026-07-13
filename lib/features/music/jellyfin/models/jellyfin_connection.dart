class JellyfinConnection {
  final String serverUrl;
  final String username;
  final String accessToken;
  final String userId;
  final String serverName;
  final String deviceId;

  const JellyfinConnection({
    required this.serverUrl,
    required this.username,
    required this.accessToken,
    required this.userId,
    required this.serverName,
    required this.deviceId,
  });

  bool get isComplete =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      accessToken.trim().isNotEmpty &&
      userId.trim().isNotEmpty &&
      deviceId.trim().isNotEmpty;

  JellyfinConnection normalized() {
    return JellyfinConnection(
      serverUrl: serverUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
      username: username.trim(),
      accessToken: accessToken.trim(),
      userId: userId.trim(),
      serverName: serverName.trim(),
      deviceId: deviceId.trim(),
    );
  }
}
