import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/extensions/go_router_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/services/debug_log_service.dart';
import 'package:classipod/core/widgets/liquid_glass.dart';
import 'package:classipod/features/device/models/device_action.dart';
import 'package:classipod/features/device/services/device_buttons_service_provider.dart';
import 'package:flutter/cupertino.dart';
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
  final TextEditingController _logsController = TextEditingController();
  Timer? _noticeTimer;
  bool _isLoading = true;
  String? _noticeText;
  DateTime? _loadedAt;

  String get _logs => _logsController.text;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLogs());
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _scrollController.dispose();
    _logsController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await ref.read(debugLogServiceProvider).readLogs();
    if (!mounted) {
      return;
    }
    _logsController.text = logs;
    setState(() {
      _isLoading = false;
      _loadedAt = DateTime.now();
    });
  }

  void _showNotice(String message) {
    _noticeTimer?.cancel();
    setState(() => _noticeText = message);
    _noticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _noticeText = null);
      }
    });
  }

  Future<void> _copyLogs() async {
    final logs = _logs;
    await Clipboard.setData(ClipboardData(text: logs));
    _showNotice('Copied ${_formattedBytes(logs.length)} to clipboard');
  }

  Future<void> _clearLogs() async {
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Clear Debug Logs?'),
        message: const Text('This deletes the current log file on this device.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear Logs'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(debugLogServiceProvider).clear();
    await _loadLogs();
    _showNotice('Logs cleared');
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  int get _lineCount {
    if (_logs.isEmpty) {
      return 0;
    }
    return '\n'.allMatches(_logs).length + 1;
  }

  String get _loadedAtLabel {
    final loadedAt = _loadedAt;
    if (loadedAt == null) {
      return 'Loading';
    }
    final hour = loadedAt.hour.toString().padLeft(2, '0');
    final minute = loadedAt.minute.toString().padLeft(2, '0');
    final second = loadedAt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _formattedBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
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
      backgroundColor: const Color(0xFFE9EEF6),
      child: Stack(
        children: [
          const Positioned.fill(
            child: AnimatedAuroraBackdrop(
              colors: [
                Color(0xFFEAF3FF),
                Color(0xFFFFDFF2),
                Color(0xFFDDF8F2),
                Color(0xFFF7F3DF),
              ],
              intensity: 0.45,
            ),
          ),
          SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 8),
                  _buildActionBar(),
                  const SizedBox(height: 8),
                  Expanded(child: _buildLogViewer(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return LiquidGlass(
      borderRadius: BorderRadius.circular(20),
      blur: 22,
      opacity: 0.62,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      borderColor: CupertinoColors.white.withValues(alpha: 0.72),
      shadows: [
        BoxShadow(
          color: CupertinoColors.black.withValues(alpha: 0.10),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
      child: Row(
        children: [
          _RoundIconButton(
            icon: CupertinoIcons.chevron_left,
            label: 'Done',
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Debug Logs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$_lineCount lines • ${_formattedBytes(_logs.length)} • $_loadedAtLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF344054).withValues(alpha: 0.76),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(left: 8, right: 4),
              child: CupertinoActivityIndicator(radius: 9),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return LiquidGlass(
      borderRadius: BorderRadius.circular(18),
      blur: 18,
      opacity: 0.54,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      borderColor: CupertinoColors.white.withValues(alpha: 0.60),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _GlassActionButton(
              icon: CupertinoIcons.doc_on_clipboard,
              label: 'Copy All',
              onPressed: _logs.isEmpty ? null : _copyLogs,
            ),
            _GlassActionButton(
              icon: CupertinoIcons.arrow_clockwise,
              label: 'Refresh',
              onPressed: _loadLogs,
            ),
            _GlassActionButton(
              icon: CupertinoIcons.trash,
              label: 'Clear',
              destructive: true,
              onPressed: _clearLogs,
            ),
            _GlassActionButton(
              icon: CupertinoIcons.arrow_up,
              label: 'Top',
              onPressed: _scrollToTop,
            ),
            _GlassActionButton(
              icon: CupertinoIcons.arrow_down,
              label: 'Bottom',
              onPressed: _scrollToBottom,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogViewer(BuildContext context) {
    return LiquidGlass(
      borderRadius: BorderRadius.circular(22),
      blur: 24,
      opacity: 0.58,
      padding: const EdgeInsets.all(8),
      borderColor: CupertinoColors.white.withValues(alpha: 0.66),
      shadows: [
        BoxShadow(
          color: CupertinoColors.black.withValues(alpha: 0.14),
          blurRadius: 24,
          offset: const Offset(0, 14),
        ),
      ],
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _noticeText == null
                ? const SizedBox(height: 0, key: ValueKey('emptyNotice'))
                : Padding(
                    key: const ValueKey('notice'),
                    padding: const EdgeInsets.only(bottom: 7),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827).withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              CupertinoIcons.check_mark_circled_solid,
                              size: 13,
                              color: CupertinoColors.white,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _noticeText!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: CupertinoColors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF07111F).withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: CupertinoColors.white.withValues(alpha: 0.22),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CupertinoScrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: CupertinoTextField(
                    controller: _logsController,
                    scrollController: _scrollController,
                    scrollPhysics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    readOnly: true,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    enableInteractiveSelection: true,
                    keyboardType: TextInputType.multiline,
                    placeholder: _isLoading
                        ? 'Loading debug logs...'
                        : 'No debug logs yet.',
                    placeholderStyle: TextStyle(
                      color: CupertinoColors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    padding: const EdgeInsets.all(11),
                    decoration: const BoxDecoration(color: Color(0x00000000)),
                    cursorColor: CupertinoColors.activeBlue,
                    style: const TextStyle(
                      color: Color(0xFFEAF6FF),
                      fontSize: 11,
                      height: 1.34,
                      fontFamily: 'Menlo',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  const _GlassActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final accent = destructive
        ? CupertinoColors.systemRed
        : const Color(0xFF1F6FEB);
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: CupertinoButton(
        minSize: 36,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        borderRadius: BorderRadius.circular(15),
        color: enabled
            ? CupertinoColors.white.withValues(alpha: 0.70)
            : CupertinoColors.white.withValues(alpha: 0.32),
        disabledColor: CupertinoColors.white.withValues(alpha: 0.30),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: enabled ? accent : const Color(0xFF98A2B3),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: enabled ? const Color(0xFF111827) : const Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _RoundIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minSize: 34,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      borderRadius: BorderRadius.circular(15),
      color: CupertinoColors.white.withValues(alpha: 0.66),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF111827)),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
