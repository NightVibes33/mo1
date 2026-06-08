import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:classipod/core/services/app_documents_service.dart';
import 'package:classipod/core/services/debug_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final crashLogServiceProvider = Provider<CrashLogService>((ref) {
  final appDocumentsService = ref.read(appDocumentsServiceProvider);
  final service = CrashLogService(
    crashLogPath: appDocumentsService.crashLogPath,
    sessionStatePath: appDocumentsService.sessionStatePath,
    debugLogService: ref.read(debugLogServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class CrashLogService with WidgetsBindingObserver {
  static const int _maxLogBytes = 2 * 1024 * 1024;
  static const int _trimmedLogBytes = 1024 * 1024;
  static CrashLogService? _activeService;

  final String crashLogPath;
  final String sessionStatePath;
  final DebugLogService debugLogService;
  final String _sessionId = DateTime.now().microsecondsSinceEpoch.toString();

  bool _isInitialized = false;
  bool _isDisposed = false;
  Map<String, Object?> _sessionState = const {};

  CrashLogService({
    required this.crashLogPath,
    required this.sessionStatePath,
    required this.debugLogService,
  });

  static void recordGlobalZoneError(Object error, StackTrace stackTrace) {
    final activeService = _activeService;
    if (activeService == null) {
      debugPrint('Uncaught zone error before crash log startup: $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }
    activeService.recordZoneError(error, stackTrace);
  }

  Future<void> initialize() async {
    if (_isInitialized || _isDisposed) {
      return;
    }

    _activeService = this;
    await File(crashLogPath).parent.create(recursive: true);
    await _appendPreviousSessionIfUnclean();
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
    await _updateSessionState(
      {
        'sessionId': _sessionId,
        'active': true,
        'startedAt': DateTime.now().toIso8601String(),
        'lastHeartbeatAt': DateTime.now().toIso8601String(),
        'lastLifecycleState': WidgetsBinding.instance.lifecycleState?.name,
      },
      appendBreadcrumb: true,
      breadcrumbMessage: 'App session started',
    );
  }

  void installFlutterErrorHandlers() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      recordFlutterError(details);
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
      recordPlatformError(error, stackTrace);
      return false;
    };
  }

  void recordFlutterError(FlutterErrorDetails details) {
    _appendCrash(
      'ERROR',
      'flutter',
      details.exceptionAsString(),
      data: {
        'library': details.library,
        'context': details.context?.toString(),
        'stackTrace': details.stack,
      },
    );
    debugLogService.error(
      'crash',
      'Flutter error captured',
      error: details.exception,
      stackTrace: details.stack,
      data: {
        'library': details.library,
        'context': details.context?.toString(),
      },
    );
  }

  void recordPlatformError(Object error, StackTrace stackTrace) {
    _appendCrash(
      'ERROR',
      'platform',
      'Uncaught platform error',
      data: {
        'error': error,
        'stackTrace': stackTrace,
      },
    );
    debugLogService.error(
      'crash',
      'Platform error captured',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void recordZoneError(Object error, StackTrace stackTrace) {
    _appendCrash(
      'ERROR',
      'zone',
      'Uncaught zone error',
      data: {
        'error': error,
        'stackTrace': stackTrace,
      },
    );
    debugLogService.error(
      'crash',
      'Zone error captured',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void recordPlaybackBreadcrumb(
    String message, {
    Map<String, Object?> data = const {},
    bool appendToCrashLog = true,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    unawaited(
      _updateSessionState(
        {
          'lastHeartbeatAt': timestamp,
          'lastPlaybackEvent': message,
          'lastPlaybackEventAt': timestamp,
          'playback': _jsonSafe(data),
        },
        appendBreadcrumb: appendToCrashLog,
        breadcrumbMessage: message,
      ),
    );
    debugLogService.info('playback', message, data: data);
  }

  void recordPlaybackError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  }) {
    _appendCrash(
      'ERROR',
      'playback',
      message,
      data: {
        ...data,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
      },
    );
    debugLogService.error(
      'playback',
      message,
      error: error,
      stackTrace: stackTrace,
      data: data,
    );
    recordPlaybackBreadcrumb(
      message,
      data: {
        ...data,
        if (error != null) 'error': error.toString(),
      },
      appendToCrashLog: false,
    );
  }

  Future<String> readCrashLogs() async {
    final file = File(crashLogPath);
    if (!await file.exists()) {
      return 'No crash logs yet.';
    }
    return file.readAsString();
  }

  Future<void> clear() async {
    for (final path in [crashLogPath, sessionStatePath]) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _updateSessionState(
      {
        'sessionId': _sessionId,
        'active': true,
        'startedAt': _sessionState['startedAt'] ??
            DateTime.now().toIso8601String(),
        'lastHeartbeatAt': DateTime.now().toIso8601String(),
        'lastLifecycleState': WidgetsBinding.instance.lifecycleState?.name,
      },
      appendBreadcrumb: true,
      breadcrumbMessage: 'Crash logs cleared',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      _updateSessionState(
        {
          'lastHeartbeatAt': DateTime.now().toIso8601String(),
          'lastLifecycleState': state.name,
          if (state == AppLifecycleState.detached) 'active': false,
        },
        appendBreadcrumb: state == AppLifecycleState.detached,
        breadcrumbMessage: 'Lifecycle changed to ${state.name}',
      ),
    );
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_activeService, this)) {
      _activeService = null;
    }
  }

  Future<void> _appendPreviousSessionIfUnclean() async {
    final file = File(sessionStatePath);
    if (!await file.exists()) {
      return;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      if (decoded['active'] != true) {
        return;
      }
      await _appendCrashLine(
        _formatLine(
          'WARN',
          'session',
          'Previous session ended without a clean shutdown',
          {
            'previousSession': decoded,
          },
        ),
      );
    } catch (error, stackTrace) {
      _appendCrash(
        'ERROR',
        'session',
        'Failed to read previous session state',
        data: {
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    }
  }

  Future<void> _updateSessionState(
    Map<String, Object?> updates, {
    bool appendBreadcrumb = false,
    String? breadcrumbMessage,
  }) async {
    if (_isDisposed) {
      return;
    }

    final updatedState = <String, Object?>{
      ..._sessionState,
      ...updates,
      'sessionId': _sessionId,
    };
    _sessionState = updatedState;

    try {
      final file = File(sessionStatePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_jsonSafe(updatedState)),
      );
    } catch (_) {
      // Logging must never crash playback or startup.
    }

    if (appendBreadcrumb) {
      _appendCrash(
        'INFO',
        'session',
        breadcrumbMessage ?? 'Session updated',
        data: updates,
      );
    }
  }

  void _appendCrash(
    String level,
    String category,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    final line = _formatLine(level, category, message, data);
    debugPrint(line);
    unawaited(_appendCrashLine(line));
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
        .map((entry) => '${entry.key}=${_formatValue(entry.value)}')
        .join(' | ');
    return dataText.isEmpty
        ? '[$timestamp][$level][$category] $message'
        : '[$timestamp][$level][$category] $message | $dataText';
  }

  Future<void> _appendCrashLine(String line) async {
    try {
      final file = File(crashLogPath);
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

  String _formatValue(Object? value) {
    final safeValue = _jsonSafe(value);
    if (safeValue is Map || safeValue is Iterable) {
      return jsonEncode(safeValue);
    }
    return safeValue?.toString() ?? '';
  }

  Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Duration) {
      return value.inMilliseconds;
    }
    if (value is StackTrace) {
      return value.toString();
    }
    if (value is Map) {
      return value.map<String, Object?>(
        (key, nestedValue) => MapEntry(key.toString(), _jsonSafe(nestedValue)),
      );
    }
    if (value is Iterable) {
      return value.map(_jsonSafe).toList(growable: false);
    }
    return value.toString();
  }
}
