import 'dart:async';

import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/features/device/models/device_action.dart';
import 'package:dope/features/device/services/device_buttons_service_provider.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/custom_equalizer_preset.dart';
import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
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
  late List<double> _bandGainsDb;
  int _selectedBand = 0;
  Timer? _previewDebounce;
  ProviderSubscription<DeviceAction?>? _deviceButtonsSubscription;

  bool get _isEditingExisting => widget.args.presetId != null && !widget.args.duplicateSource;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.args.initialName);
    _bandGainsDb = CustomEqualizerPreset.normalizeBandGains(widget.args.initialBandGainsDb);
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
    super.dispose();
  }

  Future<void> _deviceControlHandler(_, DeviceAction? action) async {
    if (action == null) {
      return;
    }
    switch (action) {
      case DeviceAction.menu:
        if (mounted) {
          context.pop();
        }
        break;
      case DeviceAction.rotateForward:
        _adjustSelectedBand(1);
        break;
      case DeviceAction.rotateBackward:
        _adjustSelectedBand(-1);
        break;
      case DeviceAction.seekForward:
        setState(() {
          _selectedBand = (_selectedBand + 1)
              .clamp(0, CustomEqualizerPreset.bandCount - 1)
              .toInt();
        });
        break;
      case DeviceAction.seekBackward:
        setState(() {
          _selectedBand = (_selectedBand - 1)
              .clamp(0, CustomEqualizerPreset.bandCount - 1)
              .toInt();
        });
        break;
      case DeviceAction.select:
        await _saveAndApply();
        break;
      case DeviceAction.selectLongPress:
        _setBandGain(_selectedBand, 0);
        break;
      case DeviceAction.playPause:
      case DeviceAction.seekForwardLongPress:
      case DeviceAction.seekBackwardLongPress:
      case DeviceAction.longPressEnd:
        break;
    }
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
    });
    _schedulePreview();
  }

  void _resetFlat() {
    setState(() {
      _bandGainsDb = CustomEqualizerPreset.normalizeBandGains(const []);
    });
    _schedulePreview();
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) {
        return;
      }
      unawaited(
        ref
            .read(audioPlayerServiceProvider.notifier)
            .previewEqualizerBandGains(_bandGainsDb),
      );
    });
  }

  Future<void> _saveAndApply({bool saveAsNew = false}) async {
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
    if (mounted) {
      context.pop();
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
        .read(settingsPreferencesControllerProvider.notifier)
        .deleteCustomEqualizerPreset(presetId);
    if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
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
                    ),
                    const SizedBox(height: 10),
                    _EqCurvePanel(bandGainsDb: _bandGainsDb),
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
                      onReset: _resetFlat,
                      onSave: () => _saveAndApply(),
                      onSaveAsNew: _isEditingExisting
                          ? () => _saveAndApply(saveAsNew: true)
                          : null,
                      onDelete: _isEditingExisting ? _deletePreset : null,
                      onCancel: () => context.pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final TextEditingController nameController;
  final String summary;

  const _HeaderCard({required this.nameController, required this.summary});

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
            const Text(
              'CUSTOM 10-BAND EQUALIZER',
              style: TextStyle(
                color: Color(0xFF7DBAFF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
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

class _EqCurvePanel extends StatelessWidget {
  final List<double> bandGainsDb;

  const _EqCurvePanel({required this.bandGainsDb});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
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
              showSections: true,
              showGrid: true,
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
          'left/right changes band; select saves. EQ works on MP3, '
          'Navidrome, and Jellyfin. Apple Music bypasses EQ.',
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
  final VoidCallback onReset;
  final VoidCallback onSave;
  final VoidCallback? onSaveAsNew;
  final VoidCallback? onDelete;
  final VoidCallback onCancel;

  const _ActionGrid({
    required this.isEditingExisting,
    required this.onReset,
    required this.onSave,
    required this.onCancel,
    this.onSaveAsNew,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _EqActionButton(label: 'Reset Flat', color: const Color(0xFF5A6472), onTap: onReset),
        _EqActionButton(
          label: isEditingExisting ? 'Update & Apply' : 'Save & Apply',
          color: const Color(0xFF2B8CFF),
          onTap: onSave,
        ),
        if (onSaveAsNew != null)
          _EqActionButton(label: 'Save As New', color: const Color(0xFF4FAF7A), onTap: onSaveAsNew!),
        if (onDelete != null)
          _EqActionButton(label: 'Delete', color: const Color(0xFFB84242), onTap: onDelete!),
        _EqActionButton(label: 'Cancel', color: const Color(0xFF343941), onTap: onCancel),
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
  final bool showSections;
  final bool showGrid;

  const _EqCurvePainter({
    required this.bandGainsDb,
    required this.showSections,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showSections) {
      _paintSections(canvas, size);
    }
    if (showGrid) {
      _paintGrid(canvas, size);
    }

    final path = Path();
    for (var index = 0; index < bandGainsDb.length; index++) {
      final x = bandGainsDb.length == 1 ? size.width / 2 : size.width * index / (bandGainsDb.length - 1);
      final normalized = (bandGainsDb[index] - CustomEqualizerPreset.minGainDb) /
          (CustomEqualizerPreset.maxGainDb - CustomEqualizerPreset.minGainDb);
      final y = size.height - normalized * size.height;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        final previousX = size.width * (index - 1) / (bandGainsDb.length - 1);
        final previousNormalized = (bandGainsDb[index - 1] - CustomEqualizerPreset.minGainDb) /
            (CustomEqualizerPreset.maxGainDb - CustomEqualizerPreset.minGainDb);
        final previousY = size.height - previousNormalized * size.height;
        final controlX = (previousX + x) / 2;
        path.cubicTo(controlX, previousY, controlX, y, x, y);
      }
    }

    final glowPaint = Paint()
      ..color = const Color(0xFF43B8FF).withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final curvePaint = Paint()
      ..color = const Color(0xFF82D8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, curvePaint);
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
  }

  double _gainToY(double gain, double height) {
    final normalized = (gain - CustomEqualizerPreset.minGainDb) /
        (CustomEqualizerPreset.maxGainDb - CustomEqualizerPreset.minGainDb);
    return height - normalized * height;
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    return oldDelegate.bandGainsDb != bandGainsDb ||
        oldDelegate.showSections != showSections ||
        oldDelegate.showGrid != showGrid;
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
