enum JellyfinAudioQuality {
  original,
  high,
  dataSaver;

  String get label {
    switch (this) {
      case JellyfinAudioQuality.original:
        return 'Original Quality';
      case JellyfinAudioQuality.high:
        return 'High Quality';
      case JellyfinAudioQuality.dataSaver:
        return 'Data Saver';
    }
  }

  String get description {
    switch (this) {
      case JellyfinAudioQuality.original:
        return 'Direct stream when Jellyfin allows it';
      case JellyfinAudioQuality.high:
        return 'Transcode up to 320 kbps';
      case JellyfinAudioQuality.dataSaver:
        return 'Transcode up to 128 kbps';
    }
  }

  String? get maxStreamingBitrate {
    switch (this) {
      case JellyfinAudioQuality.original:
        return null;
      case JellyfinAudioQuality.high:
        return '320000';
      case JellyfinAudioQuality.dataSaver:
        return '128000';
    }
  }

  static JellyfinAudioQuality fromName(String? name) {
    for (final quality in JellyfinAudioQuality.values) {
      if (quality.name == name) {
        return quality;
      }
    }
    return JellyfinAudioQuality.original;
  }
}

class JellyfinConnection {
  final String serverUrl;
  final String username;
  final String accessToken;
  final String userId;
  final String serverName;
  final String deviceId;
  final JellyfinAudioQuality audioQuality;

  const JellyfinConnection({
    required this.serverUrl,
    required this.username,
    required this.accessToken,
    required this.userId,
    required this.serverName,
    required this.deviceId,
    this.audioQuality = JellyfinAudioQuality.original,
  });

  bool get isComplete =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      accessToken.trim().isNotEmpty &&
      userId.trim().isNotEmpty &&
      deviceId.trim().isNotEmpty;

  JellyfinConnection normalized() {
    return copyWith(
      serverUrl: serverUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
      username: username.trim(),
      accessToken: accessToken.trim(),
      userId: userId.trim(),
      serverName: serverName.trim(),
      deviceId: deviceId.trim(),
    );
  }

  JellyfinConnection copyWith({
    String? serverUrl,
    String? username,
    String? accessToken,
    String? userId,
    String? serverName,
    String? deviceId,
    JellyfinAudioQuality? audioQuality,
  }) {
    return JellyfinConnection(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      serverName: serverName ?? this.serverName,
      deviceId: deviceId ?? this.deviceId,
      audioQuality: audioQuality ?? this.audioQuality,
    );
  }
}
