import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/extensions/go_router_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/crash_log_service.dart';
import 'package:dope/core/services/debug_log_service.dart';
import 'package:dope/core/services/source_health_service.dart';
import 'package:dope/core/services/storage_diagnostics_service.dart';
import 'package:dope/features/device/models/device_action.dart';
import 'package:dope/features/device/services/device_buttons_service_provider.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DebugLogsScreen extends ConsumerStatefulWidget {
  const DebugLogsScreen({super.key});

  @override
  ConsumerState<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends ConsumerState<DebugLogsScreen> {
  final ScrollController _scrollController = ScrollController();
  late Future<String> _logsFuture;

  @override
  void initState() {
    super.initState();
    _logsFuture = _readLogs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<String> _readLogs() async {
    final debugLogs = await ref.read(debugLogServiceProvider).readLogs();
    final crashLogs = await ref.read(crashLogServiceProvider).readCrashLogs();
    return '== debug.log ==\n$debugLogs\n\n== crash.log ==\n$crashLogs';
  }

  void _refreshLogs() {
    setState(() => _logsFuture = _readLogs());
  }

  Future<String> _readExportBundle(String logs) async {
    final sourceHealth = await ref.read(sourceHealthProvider.future);
    final storage = await ref.read(storageDiagnosticsServiceProvider).snapshot();
    final sourceText = sourceHealth.items
        .map((item) => '- ${item.name}: ${item.status} | healthy=${item.isHealthy} | ${item.detail}')
        .join('\n');
    final storageText = storage.entries
        .map((entry) => '- ${entry.label}: ${entry.displaySize} | ${entry.path}')
        .join('\n');
    return [
      '== døPe Debug Bundle ==',
      'createdAt=${DateTime.now().toIso8601String()}',
      '',
      '== source-health ==',
      sourceText,
      '',
      '== storage ==',
      'total=${formatBytes(storage.totalBytes)}',
      storageText,
      '',
      logs,
    ].join('\n');
  }

  Future<void> _copyLogs(String logs) async {
    await Clipboard.setData(ClipboardData(text: logs));
    if (!mounted) {
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Copied'),
        content: const Text('Logs copied to clipboard.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyBundle(String logs) async {
    final bundle = await _readExportBundle(logs);
    await _copyLogs(bundle);
  }

  Future<void> _clearLogs() async {
    await ref.read(debugLogServiceProvider).clear();
    await ref.read(crashLogServiceProvider).clear();
    _refreshLogs();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(deviceButtonsServiceProvider, (prevState, newState) {
      if (newState == null ||
          context.router.locationNamed != Routes.debugLogs.name) {
        return;
      }
      if (newState == DeviceAction.menu) {
        context.pop();
      }
    });

    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.debugLogs.title(context)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: FutureBuilder<String>(
              future: _logsFuture,
              builder: (context, snapshot) {
                final logs = snapshot.data ?? 'Loading debug logs...';
                return Row(
                  children: [
                    _DebugLogButton(
                      label: 'Copy',
                      onPressed: snapshot.hasData ? () => _copyLogs(logs) : null,
                    ),
                    const SizedBox(width: 6),
                    _DebugLogButton(label: 'Refresh', onPressed: _refreshLogs),
                    const SizedBox(width: 6),
                    _DebugLogButton(
                      label: 'Bundle',
                      onPressed: snapshot.hasData ? () => _copyBundle(logs) : null,
                    ),
                    const SizedBox(width: 6),
                    _DebugLogButton(label: 'Clear', onPressed: _clearLogs),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<String>(
              future: _logsFuture,
              builder: (context, snapshot) {
                final logs = snapshot.data ?? 'Loading debug logs...';
                return CupertinoScrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      logs,
                      style: CupertinoTheme.of(context).textTheme.textStyle
                          .copyWith(
                            fontSize: 11,
                            color: context.appPrimaryTextColor,
                          ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugLogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _DebugLogButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: CupertinoButton(
        minSize: 28,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        onPressed: onPressed,
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            color: onPressed == null
                ? CupertinoColors.inactiveGray
                : context.appPrimaryTextColor,
          ),
        ),
      ),
    );
  }
}
