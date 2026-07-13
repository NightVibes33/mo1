enum NavidromeAudioQuality {
  original,
  high,
  dataSaver;

  String get label {
    switch (this) {
      case NavidromeAudioQuality.original:
        return 'Original Quality';
      case NavidromeAudioQuality.high:
        return 'High Quality';
      case NavidromeAudioQuality.dataSaver:
        return 'Data Saver';
    }
  }

  String get description {
    switch (this) {
      case NavidromeAudioQuality.original:
        return 'Streams the original file when the server allows it';
      case NavidromeAudioQuality.high:
        return 'Requests server transcoding up to 320 kbps';
      case NavidromeAudioQuality.dataSaver:
        return 'Requests server transcoding up to 128 kbps';
    }
  }

  String? get maxBitRateKbps {
    switch (this) {
      case NavidromeAudioQuality.original:
        return null;
      case NavidromeAudioQuality.high:
        return '320';
      case NavidromeAudioQuality.dataSaver:
        return '128';
    }
  }

  static NavidromeAudioQuality fromName(String? name) {
    for (final quality in NavidromeAudioQuality.values) {
      if (quality.name == name) {
        return quality;
      }
    }
    return NavidromeAudioQuality.original;
  }
}

class NavidromeConnection {
  final String serverUrl;
  final String username;
  final String password;
  final NavidromeAudioQuality audioQuality;

  const NavidromeConnection({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.audioQuality = NavidromeAudioQuality.original,
  });

  bool get isComplete =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  NavidromeConnection normalized() {
    final cleanServerUrl = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return copyWith(
      serverUrl: cleanServerUrl,
      username: username.trim(),
      password: password,
    );
  }

  NavidromeConnection copyWith({
    String? serverUrl,
    String? username,
    String? password,
    NavidromeAudioQuality? audioQuality,
  }) {
    return NavidromeConnection(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      audioQuality: audioQuality ?? this.audioQuality,
    );
  }
}
