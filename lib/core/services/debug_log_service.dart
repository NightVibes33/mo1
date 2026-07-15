import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dope/core/services/app_documents_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final debugLogServiceProvider = Provider<DebugLogService>((ref) {
  return DebugLogService(ref.read(appDocumentsServiceProvider).debugLogPath);
});

class DebugLogService {
  static const int _maxLogBytes = 2 * 1024 * 1024;
  static const int _trimmedLogBytes = 1024 * 1024;

  final String logFilePath;
  final String sessionId;

  DebugLogService(this.logFilePath)
      : sessionId = _createSessionId();

  void info(
    String category,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    _write('INFO', category, message, data: data);
  }

  void warning(
    String category,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    _write('WARN', category, message, data: data);
  }

  void error(
    String category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  }) {
    _write(
      'ERROR',
      category,
      message,
      data: {
        ...data,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
      },
    );
  }

  Future<String> readLogs() async {
    final file = File(logFilePath);
    if (!await file.exists()) {
      return 'No debug logs yet.';
    }
    return file.readAsString();
  }

  Future<void> clear() async {
    final file = File(logFilePath);
    if (await file.exists()) {
      await file.delete();
    }
    info('debug', 'Debug logs cleared');
  }

  void _write(
    String level,
    String category,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    final line = _formatLine(level, category, message, data);
    debugPrint(line);
    unawaited(_append(line));
  }

  String _formatLine(
    String level,
    String category,
    String message,
    Map<String, Object?> data,
  ) {
    final timestamp = DateTime.now().toIso8601String();
    final dataText = data.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${_redactValue(entry.value)}')
        .join(' | ');
    return dataText.isEmpty
        ? '[$timestamp][$level][$category][$sessionId] $message'
        : '[$timestamp][$level][$category][$sessionId] $message | $dataText';
  }


  static String _createSessionId() {
    final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final random = Random().nextInt(0xFFFFF).toRadixString(36).padLeft(4, '0');
    return '$millis-$random';
  }

  Object? _redactValue(Object? value) {
    if (value is Map) {
      return value.map<String, Object?>(
        (key, nestedValue) => MapEntry(key.toString(), _redactValue(nestedValue)),
      );
    }
    if (value is Iterable) {
      return value.map(_redactValue).toList(growable: false);
    }
    if (value is Uri) {
      return _redactUri(value);
    }
    if (value is String) {
      final uri = Uri.tryParse(value);
      if (uri != null && uri.hasScheme && uri.hasAuthority) {
        return _redactUri(uri);
      }
      return value;
    }
    return value;
  }

  String _redactUri(Uri uri) {
    const sensitiveKeys = {
      'api_key',
      'apikey',
      'access_token',
      'token',
      'password',
      'pass',
      'p',
      'salt',
      's',
      't',
    };
    final redactedQuery = <String, dynamic>{};
    uri.queryParametersAll.forEach((key, values) {
      redactedQuery[key] = sensitiveKeys.contains(key.toLowerCase())
          ? '<redacted>'
          : values;
    });
    return uri.replace(queryParameters: redactedQuery).toString();
  }

  Future<void> _append(String line) async {
    try {
      final file = File(logFilePath);
      await file.parent.create(recursive: true);
      if (await file.exists() && await file.length() > _maxLogBytes) {
        final content = await file.readAsString();
        final start = content.length > _trimmedLogBytes
            ? content.length - _trimmedLogBytes
            : 0;
        await file.writeAsString(content.substring(start));
      }
      await file.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {
      // Logging must never crash playback or importing.
    }
  }
}
