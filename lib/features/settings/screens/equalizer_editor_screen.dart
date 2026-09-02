import 'dart:async';

import 'package:dopi/core/models/music_metadata.dart';
import 'package:dopi/core/navigation/routes.dart';
import 'package:dopi/core/services/audio_player_service.dart';
import 'package:dopi/core/services/native_eq_player_service.dart';
import 'package:dopi/features/device/models/device_action.dart';
import 'package:dopi/features/device/services/device_buttons_service_provider.dart';
import 'package:dopi/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:dopi/features/settings/controller/settings_preferences_controller.dart';
import 'package:dopi/features/settings/models/custom_equalizer_preset.dart';
import 'package:dopi/features/settings/models/equalizer_preset.dart';
import 'package:dopi/features/settings/models/settings_preferences_model.dart';
import 'package:dopi/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class EqualizerEditorArgs {
  final String? presetId;
  final String initialName;
  final List<double> initialBandGainsDb;
  final bool duplicateSource;

  const EqualizerEditorArgs({
    this.presetId,
    required this.initialName,
    required this.initialBandGainsDb,
    this.duplicateSource = false,
  });

  factory EqualizerEditorArgs.create({
    required int customPresetCount,
    required List<double> initialBandGainsDb,
  }) {
    return EqualizerEditorArgs(
      initialName: 'Custom ${customPresetCount + 1}',
      initialBandGainsDb: initialBandGainsDb,
    );
  }

  factory EqualizerEditorArgs.edit(CustomEqualizerPreset preset) {
    return EqualizerEditorArgs(
      presetId: preset.id,
      initialName: preset.name,
      initialBandGainsDb: preset.bandGainsDb,
    );
  }

  factory EqualizerEditorArgs.duplicatePreset(EqualizerPreset preset) {
    return EqualizerEditorArgs(
      initialName: '${preset.title} Custom',
      initialBandGainsDb: preset.approximateBandGainsDb,
      duplicateSource: true,
    );
  }
}

class EqualizerEditorScreen extends ConsumerStatefulWidget {
  final EqualizerEditorArgs args;

  const EqualizerEditorScreen({required this.args, super.key});

  @override
  ConsumerState<EqualizerEditorScreen> createState() => _EqualizerEditorScreenState();
}

class _EqualizerEditorScreenState extends ConsumerState<EqualizerEditorScreen> {
  late final TextEditingController _nameController;
  late final _EqEditorSnapshot _originalSnapshot;
  late final List<double> _initialEditorBandGainsDb;
  late final String _initialEditorName;
  late List<double> _bandGainsDb;
  int _selectedBand = 0;
  bool _didCommit = false;
  bool _isComparingOriginal = false;
  bool _didPreview = false;
  Timer? _previewDebounce;
  ProviderSubscription<DeviceAction?>? _deviceButtonsSubscription;

  bool get _isEditingExisting =>
      widget.args.presetId != null && !widget.args.duplicateSource;

  bool get _bandsChanged =>
      !_listEquals(_bandGainsDb, _initialEditorBandGainsDb);

  bool get _nameChanged =>
      _nameController.text.trim() != _initialEditorName.trim();

  bool get _hasChanges => _bandsChanged || _nameChanged;

  double get _preampDb => CustomEqualizerPreset.recommendedPreampDb(_bandGainsDb);

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsPreferencesControllerProvider);
    _originalSnapshot = _EqEditorSnapshot.fromSettings(settings);
    _initialEditorName = widget.args.initialName;
    _initialEditorBandGainsDb = CustomEqualizerPreset.normalizeBandGains(
      widget.args.initialBandGainsDb,
    );
    _nameController = TextEditingController(text: _initialEditorName);
    _nameController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _bandGainsDb = _initialEditorBandGainsDb;
    _deviceButtonsSubscription = ref.listenManual(
      deviceButtonsServiceProvider,
      _deviceControlHandler,
    );
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _deviceButtonsSubscription?.close();
    _nameController.dispose();
    if (!_didCommit && _didPreview) {
      unawaited(
        ref.read(audioPlayerServiceProvider.notifier).restoreEqualizerPreview(),
      );
    }
    super.dispose();
  }

  Future<void> _deviceControlHandler(_, DeviceAction? action) async {
    if (action == null) {
      return;
    }
    switch (action) {
      case DeviceAction.menu:
        await _handleExit();
        break;
      case DeviceAction.rotateForward:
        _adjustSelectedBand(1);
        break;
      case DeviceAction.rotateBackward:
        _adjustSelectedBand(-1);
        break;
      case DeviceAction.seekForward:
        _moveSelectedBand(1);
        break;
      case DeviceAction.seekBackward:
        _moveSelectedBand(-1);
        break;
      case DeviceAction.select:
        await _showActionMenu();
        break;
      case DeviceAction.selectLongPress:
        _resetBand(_selectedBand);
        break;
      case DeviceAction.playPause:
        await _toggleCompare();
        break;
      case DeviceAction.seekForwardLongPress:
      case DeviceAction.seekBackwardLongPress:
      case DeviceAction.longPressEnd:
        break;
    }
  }

  void _moveSelectedBand(int direction) {
    setState(() {
      _selectedBand = (_selectedBand + direction)
          .clamp(0, CustomEqualizerPreset.bandCount - 1)
          .toInt();
    });
  }

  void _adjustSelectedBand(int direction) {
    final current = _bandGainsDb[_selectedBand];
    _setBandGain(_selectedBand, current + direction);
  }

  void _setBandGain(int index, double value) {
    setState(() {
      final updated = [..._bandGainsDb];
      updated[index] = value
          .clamp(CustomEqualizerPreset.minGainDb, CustomEqualizerPreset.maxGainDb)
          .toDouble();
      _bandGainsDb = CustomEqualizerPreset.normalizeBandGains(updated);
      _isComparingOriginal = false;
    });
    _schedulePreview();
  }

  void _resetBand(int index) {
    _setBandGain(index, 0);
  }

  void _resetRange(int start, int end) {
    setState(() {
      final updated = [..._bandGainsDb];
      for (var index = start; index < end; index++) {
        updated[index] = 0;
      }
      _bandGainsDb = CustomEqualizerPreset.normalizeBandGains(updated);
      _isComparingOriginal = false;
    });
    _schedulePreview();
  }

  void _resetAll() {
    setState(() {
      _bandGainsDb = CustomEqualizerPreset.normalizeBandGains(const []);
      _isComparingOriginal = false;
    });
    _schedulePreview();
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || _isComparingOriginal) {
        return;
      }
      setState(() => _didPreview = true);
      unawaited(
        ref
            .read(audioPlayerServiceProvider.notifier)
            .previewEqualizerBandGains(_bandGainsDb),
      );
    });
  }

  Future<void> _toggleCompare() async {
    _previewDebounce?.cancel();
    final nextCompareState = !_isComparingOriginal;
    setState(() => _isComparingOriginal = nextCompareState);
    final previewBands = nextCompareState
        ? _originalSnapshot.bandGainsDb
        : _bandGainsDb;
    setState(() => _didPreview = true);
    await ref
        .read(audioPlayerServiceProvider.notifier)
        .previewEqualizerBandGains(previewBands);
  }

  Future<void> _saveAndApply({bool saveAsNew = false}) async {
    _previewDebounce?.cancel();
    await ref
        .read(audioPlayerServiceProvider.notifier)
        .settleEqualizerPreview();
    final notifier = ref.read(settingsPreferencesControllerProvider.notifier);
    if (_isEditingExisting && !saveAsNew) {
      await notifier.updateCustomEqualizerPreset(
        presetId: widget.args.presetId!,
        name: _nameController.text,
        bandGainsDb: _bandGainsDb,
      );
    } else {
      await notifier.saveCustomEqualizerPreset(
        name: _nameController.text,
        bandGainsDb: _bandGainsDb,
      );
    }
    _didCommit = true;
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _discardAndExit() async {
    _previewDebounce?.cancel();
    if (_didPreview) {
      await ref
          .read(audioPlayerServiceProvider.notifier)
          .restoreEqualizerPreview();
    }
    _didCommit = true;
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _handleExit() async {
    if (!_hasChanges) {
      await _discardAndExit();
      return;
    }
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Save EQ changes?'),
        message: Text('Previewing "${_displayName}" has not been saved.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard Changes'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop('keep'),
          child: const Text('Keep Editing'),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (action == 'save') {
      await _saveAndApply();
    } else if (action == 'discard') {
      await _discardAndExit();
    }
  }

  Future<void> _showActionMenu() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(_displayName),
        message: Text(
          _isComparingOriginal
              ? 'Compare is playing the original curve.'
              : 'Live preview is playing the edited curve.',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save'),
          ),
          if (_isEditingExisting)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop('save_new'),
              child: const Text('Save As New'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('compare'),
            child: Text(_isComparingOriginal ? 'Preview Edited EQ' : 'Compare Original'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('reset'),
            child: const Text('Reset Options'),
          ),
          if (_isEditingExisting)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop('delete'),
              child: const Text('Delete Custom EQ'),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard Changes'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop('cancel'),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case 'save':
        await _saveAndApply();
        break;
      case 'save_new':
        await _saveAndApply(saveAsNew: true);
        break;
      case 'compare':
        await _toggleCompare();
        break;
      case 'reset':
        await _showResetMenu();
        break;
      case 'delete':
        await _deletePreset();
        break;
      case 'discard':
        await _discardAndExit();
        break;
    }
  }

  Future<void> _showResetMenu() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Reset EQ'),
        message: const Text('Choose which part of the curve to flatten.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('band'),
            child: Text('Reset ${CustomEqualizerPreset.bandLabels[_selectedBand]}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('bass'),
            child: const Text('Reset Bass'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('mid'),
            child: const Text('Reset Mid'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('treble'),
            child: const Text('Reset Treble'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop('all'),
            child: const Text('Reset All'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop('cancel'),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case 'band':
        _resetBand(_selectedBand);
        break;
      case 'bass':
        _resetRange(0, 3);
        break;
      case 'mid':
        _resetRange(3, 7);
        break;
      case 'treble':
        _resetRange(7, 10);
        break;
      case 'all':
        _resetAll();
        break;
    }
  }

  Future<void> _deletePreset() async {
    final presetId = widget.args.presetId;
    if (presetId == null) {
      return;
    }
    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete Custom EQ?'),
        content: Text('Remove "${_nameController.text.trim()}" from this device?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) {
      return;
    }
    await ref
        .read(audioPlayerServiceProvider.notifier)
        .settleEqualizerPreview();
    await ref
        .read(settingsPreferencesControllerProvider.notifier)
        .deleteCustomEqualizerPreset(presetId);
    _didCommit = true;
    if (mounted) {
      context.pop();
    }
  }

  String get _displayName {
    final trimmed = _nameController.text.trim();
    return trimmed.isEmpty ? 'Custom EQ' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final nowPlaying = ref.watch(nowPlayingDetailsProvider);
    final currentMetadata = nowPlaying.currentMetadata;
    final nativeEqActive = ref.watch(nativeEqPlaybackActiveProvider);
    final nativeEqFailure = ref.watch(nativeEqFailureProvider);
    final previewStatus = _previewStatusFor(
      currentMetadata,
      didPreview: _didPreview,
      nativeEqActive: nativeEqActive,
      nativeEqFailure: nativeEqFailure,
    );
    final selectedBandLabel = CustomEqualizerPreset.bandLabels[_selectedBand];
    final selectedGain = _bandGainsDb[_selectedBand];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleExit());
        }
      },
      child: CupertinoPageScaffold(
        child: Column(
          children: [
            StatusBar(title: _isEditingExisting ? 'Edit EQ' : 'Create EQ'),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF121315), Color(0xFF050506)],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                    children: [
                      _HeaderCard(
                        nameController: _nameController,
                        summary: _curveSummary(_bandGainsDb),
                        status: previewStatus,
                        hasChanges: _hasChanges,
                        isComparingOriginal: _isComparingOriginal,
                      ),
                      const SizedBox(height: 10),
                      _FocusedBandCard(
                        label: selectedBandLabel,
                        gainDb: selectedGain,
                        sectionLabel: _sectionLabel(_selectedBand),
                        sectionColor: _sectionColor(_selectedBand),
                        preampDb: _preampDb,
                      ),
                      const SizedBox(height: 10),
                      _EqCurvePanel(
                        bandGainsDb: _bandGainsDb,
                        originalBandGainsDb: _originalSnapshot.bandGainsDb,
                        selectedBand: _selectedBand,
                        isComparingOriginal: _isComparingOriginal,
                      ),
                      const SizedBox(height: 10),
                      _EqFaderPanel(
                        bandGainsDb: _bandGainsDb,
                        selectedBand: _selectedBand,
                        onBandSelected: (index) => setState(() => _selectedBand = index),
                        onBandChanged: _setBandGain,
                      ),
                      const SizedBox(height: 12),
                      _EditorHelpCard(selectedBand: _selectedBand),
                      const SizedBox(height: 12),
                      _ActionGrid(
                        isEditingExisting: _isEditingExisting,
                        isComparingOriginal: _isComparingOriginal,
                        onReset: _showResetMenu,
                        onSave: () => _saveAndApply(),
                        onSaveAsNew: _isEditingExisting
                            ? () => _saveAndApply(saveAsNew: true)
                            : null,
                        onCompare: _toggleCompare,
                        onDelete: _isEditingExisting ? _deletePreset : null,
                        onCancel: _handleExit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EqEditorSnapshot {
  final List<double> bandGainsDb;

  const _EqEditorSnapshot({required this.bandGainsDb});

  factory _EqEditorSnapshot.fromSettings(SettingsPreferencesModel settings) {
    return _EqEditorSnapshot(
      bandGainsDb: CustomEqualizerPreset.normalizeBandGains(
        settings.activeEqualizerBandGainsDb,
      ),
    );
  }
}

class _PreviewStatus {
  final String label;
  final Color color;

  const _PreviewStatus({required this.label, required this.color});
}

_PreviewStatus _previewStatusFor(
  MusicMetadata? metadata, {
  required bool didPreview,
  required bool nativeEqActive,
  required String? nativeEqFailure,
}) {
  if (metadata == null) {
    return const _PreviewStatus(
      label: 'PREVIEW READY • PLAY A SONG TO HEAR IT',
      color: Color(0xFF8D98A8),
    );
  }
  if (metadata.isAppleMusicCatalogTrack) {
    return const _PreviewStatus(
      label: 'PREVIEW UNAVAILABLE • APPLE MUSIC',
      color: Color(0xFFFF6B6B),
    );
  }
  if (didPreview && nativeEqFailure != null) {
    return const _PreviewStatus(
      label: 'PREVIEW UNAVAILABLE - NATIVE EQ FAILED',
      color: Color(0xFFFF6B6B),
    );
  }
  if (!didPreview || !nativeEqActive) {
    return const _PreviewStatus(
      label: 'PREVIEW ARMED - MOVE A BAND TO ACTIVATE',
      color: Color(0xFF8D98A8),
    );
  }
  switch (metadata.sourceType) {
    case MusicSourceType.navidrome:
      return const _PreviewStatus(
        label: 'LIVE PREVIEW • NAVIDROME',
        color: Color(0xFF50F0CB),
      );
    case MusicSourceType.jellyfin:
      return const _PreviewStatus(
        label: 'LIVE PREVIEW • JELLYFIN',
        color: Color(0xFFAA83FF),
      );
    case MusicSourceType.local:
      return const _PreviewStatus(
        label: 'LIVE PREVIEW • MP3',
        color: Color(0xFF7DBAFF),
      );
    case MusicSourceType.remote:
      return const _PreviewStatus(
        label: 'LIVE PREVIEW • REMOTE',
        color: Color(0xFF7DBAFF),
      );
    case MusicSourceType.appleMusic:
      return const _PreviewStatus(
        label: 'PREVIEW UNAVAILABLE • APPLE MUSIC',
        color: Color(0xFFFF6B6B),
      );
  }
}

class _HeaderCard extends StatelessWidget {
  final TextEditingController nameController;
  final String summary;
  final _PreviewStatus status;
  final bool hasChanges;
  final bool isComparingOriginal;

  const _HeaderCard({
    required this.nameController,
    required this.summary,
    required this.status,
    required this.hasChanges,
    required this.isComparingOriginal,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1D20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3B4658)),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.38),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'CUSTOM 10-BAND EQUALIZER',
                    style: TextStyle(
                      color: Color(0xFF7DBAFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (hasChanges)
                  const Text(
                    'UNSAVED',
                    style: TextStyle(
                      color: Color(0xFFFFB340),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: nameController,
              placeholder: 'Preset Name',
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
              placeholderStyle: TextStyle(
                color: CupertinoColors.white.withValues(alpha: 0.45),
              ),
              decoration: BoxDecoration(
                color: CupertinoColors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CupertinoColors.white.withValues(alpha: 0.10)),
              ),
            ),
            const SizedBox(height: 8),
            _PreviewStatusPill(
              label: isComparingOriginal ? 'COMPARING • ORIGINAL EQ' : status.label,
              color: isComparingOriginal ? const Color(0xFFFFB340) : status.color,
            ),
            const SizedBox(height: 8),
            Text(
              summary,
              style: TextStyle(
                color: CupertinoColors.white.withValues(alpha: 0.72),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _PreviewStatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.46)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _FocusedBandCard extends StatelessWidget {
  final String label;
  final double gainDb;
  final String sectionLabel;
  final Color sectionColor;
  final double preampDb;

  const _FocusedBandCard({
    required this.label,
    required this.gainDb,
    required this.sectionLabel,
    required this.sectionColor,
    required this.preampDb,
  });

  @override
  Widget build(BuildContext context) {
    final signedGain = gainDb > 0 ? '+${gainDb.round()}' : gainDb.round().toString();
    final headroom = preampDb == 0 ? '0 dB' : '${preampDb.toStringAsFixed(1)} dB';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: sectionColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: sectionColor.withValues(alpha: 0.42)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sectionLabel,
                    style: TextStyle(
                      color: sectionColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$signedGain dB',
                  style: TextStyle(
                    color: sectionColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Headroom $headroom',
                  style: TextStyle(
                    color: CupertinoColors.white.withValues(alpha: 0.68),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EqCurvePanel extends StatelessWidget {
  final List<double> bandGainsDb;
  final List<double> originalBandGainsDb;
  final int selectedBand;
  final bool isComparingOriginal;

  const _EqCurvePanel({
    required this.bandGainsDb,
    required this.originalBandGainsDb,
    required this.selectedBand,
    required this.isComparingOriginal,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 126,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0D10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF26364A)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CustomPaint(
            painter: _EqCurvePainter(
              bandGainsDb: bandGainsDb,
              originalBandGainsDb: originalBandGainsDb,
              selectedBand: selectedBand,
              showSections: true,
              showGrid: true,
              isComparingOriginal: isComparingOriginal,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _EqFaderPanel extends StatelessWidget {
  final List<double> bandGainsDb;
  final int selectedBand;
  final ValueChanged<int> onBandSelected;
  final void Function(int index, double value) onBandChanged;

  const _EqFaderPanel({
    required this.bandGainsDb,
    required this.selectedBand,
    required this.onBandSelected,
    required this.onBandChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 315,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF111418),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF2F3D4E)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(
            children: [
              const _EqSectionLabels(),
              const SizedBox(height: 4),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _EqGridPainter(),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < CustomEqualizerPreset.bandCount; index++)
                          Expanded(
                            child: _VerticalEqBand(
                              label: CustomEqualizerPreset.bandLabels[index],
                              value: bandGainsDb[index],
                              isSelected: selectedBand == index,
                              sectionColor: _sectionColor(index),
                              onTap: () => onBandSelected(index),
                              onChanged: (value) => onBandChanged(index, value),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EqSectionLabels extends StatelessWidget {
  const _EqSectionLabels();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(flex: 3, child: _SectionPill(label: 'BASS', color: Color(0xFF3F8CFF))),
        SizedBox(width: 5),
        Expanded(flex: 4, child: _SectionPill(label: 'MID', color: Color(0xFFFFB340))),
        SizedBox(width: 5),
        Expanded(flex: 3, child: _SectionPill(label: 'TREBLE', color: Color(0xFF50F0CB))),
      ],
    );
  }
}

class _SectionPill extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.44)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _VerticalEqBand extends StatelessWidget {
  final String label;
  final double value;
  final bool isSelected;
  final Color sectionColor;
  final VoidCallback onTap;
  final ValueChanged<double> onChanged;

  const _VerticalEqBand({
    required this.label,
    required this.value,
    required this.isSelected,
    required this.sectionColor,
    required this.onTap,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final signedValue = value > 0 ? '+${value.round()}' : value.round().toString();
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected ? sectionColor.withValues(alpha: 0.12) : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? sectionColor.withValues(alpha: 0.7) : CupertinoColors.transparent,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Column(
            children: [
              SizedBox(
                height: 25,
                child: Center(
                  child: Text(
                    '$signedValue dB',
                    style: TextStyle(
                      color: isSelected ? sectionColor : CupertinoColors.white.withValues(alpha: 0.74),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: CupertinoSlider(
                    min: CustomEqualizerPreset.minGainDb,
                    max: CustomEqualizerPreset.maxGainDb,
                    value: value,
                    activeColor: sectionColor,
                    onChanged: onChanged,
                  ),
                ),
              ),
              SizedBox(
                height: 32,
                child: Center(
                  child: Text(
                    _shortBandLabel(label),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CupertinoColors.white.withValues(alpha: 0.82),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorHelpCard extends StatelessWidget {
  final int selectedBand;

  const _EditorHelpCard({required this.selectedBand});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF171A1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3645)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          'Wheel: rotate adjusts ${CustomEqualizerPreset.bandLabels[selectedBand]}; '
          'left/right changes band; select opens actions; play/pause compares.',
          style: TextStyle(
            color: CupertinoColors.white.withValues(alpha: 0.66),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  final bool isEditingExisting;
  final bool isComparingOriginal;
  final VoidCallback onReset;
  final VoidCallback onSave;
  final VoidCallback? onSaveAsNew;
  final VoidCallback onCompare;
  final VoidCallback? onDelete;
  final VoidCallback onCancel;

  const _ActionGrid({
    required this.isEditingExisting,
    required this.isComparingOriginal,
    required this.onReset,
    required this.onSave,
    required this.onSaveAsNew,
    required this.onCompare,
    required this.onCancel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _EqActionButton(
          label: isComparingOriginal ? 'Preview Edited' : 'Compare',
          color: const Color(0xFFFFB340),
          onTap: onCompare,
        ),
        _EqActionButton(label: 'Reset', color: const Color(0xFF5A6472), onTap: onReset),
        _EqActionButton(
          label: isEditingExisting ? 'Save' : 'Save New',
          color: const Color(0xFF2B8CFF),
          onTap: onSave,
        ),
        if (onSaveAsNew != null)
          _EqActionButton(
            label: 'Save As New',
            color: const Color(0xFF4FAF7A),
            onTap: onSaveAsNew!,
          ),
        if (onDelete != null)
          _EqActionButton(label: 'Delete', color: const Color(0xFFB84242), onTap: onDelete!),
        _EqActionButton(label: 'Exit', color: const Color(0xFF343941), onTap: onCancel),
      ],
    );
  }
}

class _EqActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _EqActionButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.26),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  final List<double> bandGainsDb;
  final List<double> originalBandGainsDb;
  final int selectedBand;
  final bool showSections;
  final bool showGrid;
  final bool isComparingOriginal;

  const _EqCurvePainter({
    required this.bandGainsDb,
    required this.originalBandGainsDb,
    required this.selectedBand,
    required this.showSections,
    required this.showGrid,
    required this.isComparingOriginal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showSections) {
      _paintSections(canvas, size);
    }
    if (showGrid) {
      _paintGrid(canvas, size);
    }

    if (!_listEquals(originalBandGainsDb, bandGainsDb)) {
      _drawCurve(
        canvas,
        size,
        originalBandGainsDb,
        Paint()
          ..color = CupertinoColors.white.withValues(alpha: 0.26)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    final displayedGains = isComparingOriginal
        ? originalBandGainsDb
        : bandGainsDb;
    final glowPaint = Paint()
      ..color = (isComparingOriginal ? const Color(0xFFFFB340) : const Color(0xFF43B8FF))
          .withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final curvePaint = Paint()
      ..color = isComparingOriginal ? const Color(0xFFFFB340) : const Color(0xFF82D8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    _drawCurve(canvas, size, displayedGains, glowPaint);
    _drawCurve(canvas, size, displayedGains, curvePaint);

    final selectedX = displayedGains.length == 1
        ? size.width / 2
        : size.width * selectedBand / (displayedGains.length - 1);
    final selectedY = _gainToY(displayedGains[selectedBand], size.height);
    final dotPaint = Paint()..color = _sectionColor(selectedBand);
    final ringPaint = Paint()
      ..color = CupertinoColors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset(selectedX, selectedY), 7, dotPaint);
    canvas.drawCircle(Offset(selectedX, selectedY), 8, ringPaint);
  }

  void _drawCurve(Canvas canvas, Size size, List<double> gains, Paint paint) {
    if (gains.isEmpty) {
      return;
    }
    final path = Path();
    for (var index = 0; index < gains.length; index++) {
      final x = gains.length == 1 ? size.width / 2 : size.width * index / (gains.length - 1);
      final y = _gainToY(gains[index], size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        final previousX = size.width * (index - 1) / (gains.length - 1);
        final previousY = _gainToY(gains[index - 1], size.height);
        final controlX = (previousX + x) / 2;
        path.cubicTo(controlX, previousY, controlX, y, x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _paintSections(Canvas canvas, Size size) {
    final sectionStarts = [0.0, 0.3, 0.7];
    final sectionEnds = [0.3, 0.7, 1.0];
    final sectionColors = const [
      Color(0xFF153B76),
      Color(0xFF60400D),
      Color(0xFF0D5248),
    ];
    for (var index = 0; index < sectionColors.length; index++) {
      final paint = Paint()..color = sectionColors[index].withValues(alpha: 0.22);
      canvas.drawRect(
        Rect.fromLTRB(
          size.width * sectionStarts[index],
          0,
          size.width * sectionEnds[index],
          size.height,
        ),
        paint,
      );
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.32)
      ..strokeWidth = 1.5;
    for (final db in const [-12, -6, 0, 6, 12]) {
      final y = _gainToY(db.toDouble(), size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), db == 0 ? zeroPaint : gridPaint);
    }
    final dividerPaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(size.width * 0.3, 0), Offset(size.width * 0.3, size.height), dividerPaint);
    canvas.drawLine(Offset(size.width * 0.7, 0), Offset(size.width * 0.7, size.height), dividerPaint);

    const labelStyle = TextStyle(
      color: CupertinoColors.white,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
    final painter = TextPainter(
      text: TextSpan(text: '0 dB', style: labelStyle.copyWith(color: CupertinoColors.white.withValues(alpha: 0.45))),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(size.width - painter.width - 4, _gainToY(0, size.height) + 3));
  }

  double _gainToY(double gain, double height) {
    final normalized = (gain - CustomEqualizerPreset.minGainDb) /
        (CustomEqualizerPreset.maxGainDb - CustomEqualizerPreset.minGainDb);
    return height - normalized * height;
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    return oldDelegate.bandGainsDb != bandGainsDb ||
        oldDelegate.originalBandGainsDb != originalBandGainsDb ||
        oldDelegate.selectedBand != selectedBand ||
        oldDelegate.showSections != showSections ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.isComparingOriginal != isComparingOriginal;
  }
}

class _EqGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final zeroPaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.5;
    final gridPaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (final db in const [-12, -6, 0, 6, 12]) {
      final normalized = (db - CustomEqualizerPreset.minGainDb) /
          (CustomEqualizerPreset.maxGainDb - CustomEqualizerPreset.minGainDb);
      final y = size.height - normalized * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), db == 0 ? zeroPaint : gridPaint);
    }
    final dividerPaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(size.width * 0.3, 0), Offset(size.width * 0.3, size.height), dividerPaint);
    canvas.drawLine(Offset(size.width * 0.7, 0), Offset(size.width * 0.7, size.height), dividerPaint);
  }

  @override
  bool shouldRepaint(covariant _EqGridPainter oldDelegate) => false;
}

Color _sectionColor(int index) {
  if (index <= 2) {
    return const Color(0xFF3F8CFF);
  }
  if (index <= 6) {
    return const Color(0xFFFFB340);
  }
  return const Color(0xFF50F0CB);
}

String _sectionLabel(int index) {
  if (index <= 2) {
    return 'BASS';
  }
  if (index <= 6) {
    return 'MID';
  }
  return 'TREBLE';
}

String _shortBandLabel(String label) {
  return label.replaceAll(' Hz', '').replaceAll(' kHz', 'k');
}

String _curveSummary(List<double> bandGainsDb) {
  String signed(double value) {
    final rounded = value.round();
    return rounded > 0 ? '+$rounded dB' : '$rounded dB';
  }

  double average(int start, int end) {
    final values = bandGainsDb.sublist(start, end);
    return values.reduce((a, b) => a + b) / values.length;
  }

  return 'Bass ${signed(average(0, 3))}  Mid ${signed(average(3, 7))}  Treble ${signed(average(7, 10))}';
}

bool _listEquals(List<double> a, List<double> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
