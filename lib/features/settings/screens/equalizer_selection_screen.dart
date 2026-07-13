import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/custom_equalizer_preset.dart';
import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:dope/features/settings/models/settings_preferences_model.dart';
import 'package:dope/features/settings/screens/equalizer_editor_screen.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class EqualizerSelectionScreen extends ConsumerStatefulWidget {
  const EqualizerSelectionScreen({super.key});

  @override
  ConsumerState createState() => _EqualizerSelectionScreenState();
}

class _EqualizerSelectionScreenState extends ConsumerState<EqualizerSelectionScreen>
    with CustomScreen {
  bool _didSeedSelection = false;

  @override
  String get routeName => Routes.equalizer.name;

  @override
  double get displayTileHeight => 64;

  @override
  List<_EqualizerSelectionEntry> get displayItems {
    final settings = ref.read(settingsPreferencesControllerProvider);
    return [
      const _EqualizerSelectionEntry.createCustom(),
      ...settings.customEqualizerPresets.map(_EqualizerSelectionEntry.custom),
      ...EqualizerPreset.values.map(_EqualizerSelectionEntry.preset),
    ];
  }

  @override
  Future<void> onSelectPressed() => _handleEntrySelection(selectedDisplayItem);

  @override
  void onSelectLongPress() {
    final entries = displayItems;
    if (selectedDisplayItem < 0 || selectedDisplayItem >= entries.length) {
      return;
    }
    final entry = entries[selectedDisplayItem];
    if (entry.customPreset != null) {
      _showCustomEqActions(entry.customPreset!);
    } else if (entry.preset != null) {
      _openEditor(EqualizerEditorArgs.duplicatePreset(entry.preset!));
    }
  }

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsPreferencesControllerProvider);
    selectedDisplayItem = _selectedIndexForSettings(settings);
    _didSeedSelection = true;
  }

  int _selectedIndexForSettings(SettingsPreferencesModel settings) {
    if (settings.activeCustomEqualizerPreset != null) {
      final customIndex = settings.customEqualizerPresets.indexWhere(
        (preset) => preset.id == settings.activeCustomEqualizerPreset!.id,
      );
      if (customIndex >= 0) {
        return 1 + customIndex;
      }
    }
    final presetIndex = EqualizerPreset.values.indexOf(settings.equalizerPreset);
    return 1 + settings.customEqualizerPresets.length +
        (presetIndex < 0 ? 0 : presetIndex);
  }

  Future<void> _handleEntrySelection(int index) async {
    if (index < 0 || index >= displayItems.length) {
      return;
    }
    final entry = displayItems[index];
    setState(() => selectedDisplayItem = index);
    switch (entry.type) {
      case _EqualizerSelectionEntryType.createCustom:
        final settings = ref.read(settingsPreferencesControllerProvider);
        _openEditor(
          EqualizerEditorArgs.create(
            customPresetCount: settings.customEqualizerPresets.length,
            initialBandGainsDb: settings.activeEqualizerBandGainsDb,
          ),
        );
        break;
      case _EqualizerSelectionEntryType.preset:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .setEqualizerPreset(entry.preset!);
        break;
      case _EqualizerSelectionEntryType.custom:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .selectCustomEqualizerPreset(entry.customPreset!.id);
        break;
    }
  }

  void _openEditor(EqualizerEditorArgs args) {
    context.goNamed(Routes.equalizerEditor.name, extra: args);
  }

  Future<void> _showCustomEqActions(CustomEqualizerPreset preset) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(preset.name),
        message: const Text('Apply, edit, duplicate, or delete this custom curve.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('apply'),
            child: const Text('Apply Custom EQ'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('edit'),
            child: const Text('Edit Custom EQ'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('duplicate'),
            child: const Text('Duplicate'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop('delete'),
            child: const Text('Delete Custom EQ'),
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
    if (action == 'apply') {
      await ref
          .read(settingsPreferencesControllerProvider.notifier)
          .selectCustomEqualizerPreset(preset.id);
    } else if (action == 'edit') {
      _openEditor(EqualizerEditorArgs.edit(preset));
    } else if (action == 'duplicate') {
      _openEditor(
        EqualizerEditorArgs(
          initialName: '${preset.name} Copy',
          initialBandGainsDb: preset.bandGainsDb,
          duplicateSource: true,
        ),
      );
    } else if (action == 'delete') {
      await _deleteCustomEq(preset);
    }
  }

  Future<void> _deleteCustomEq(CustomEqualizerPreset preset) async {
    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete Custom EQ?'),
        content: Text('Remove "${preset.name}" from this device?'),
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
        .deleteCustomEqualizerPreset(preset.id);
    final settingsAfterDelete = ref.read(settingsPreferencesControllerProvider);
    setState(() => selectedDisplayItem = _selectedIndexForSettings(settingsAfterDelete));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsPreferencesControllerProvider);
    final entries = displayItems;
    if (_didSeedSelection && entries.isNotEmpty) {
      final safeIndex = selectedDisplayItem.clamp(0, entries.length - 1) as int;
      if (safeIndex != selectedDisplayItem) {
        selectedDisplayItem = safeIndex;
      }
    }

    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.equalizer.title(context)),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                padding: listViewPadding,
                itemCount: entries.length,
                prototypeItem: _EqualizerOptionTile(
                  title: 'Custom EQ',
                  subtitle: 'Bass +0 dB  Mid +0 dB  Treble +0 dB',
                  bandGainsDb: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                  isSelected: false,
                  isCreateAction: false,
                  isActive: false,
                  onTap: () {},
                ),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final isActive = entry.type == _EqualizerSelectionEntryType.custom
                      ? settings.activeCustomEqualizerPreset?.id == entry.customPreset?.id
                      : entry.type == _EqualizerSelectionEntryType.preset
                          ? settings.activeCustomEqualizerPreset == null &&
                              settings.equalizerPreset == entry.preset
                          : false;
                  return _EqualizerOptionTile(
                    title: entry.title,
                    subtitle: entry.subtitle,
                    bandGainsDb: entry.bandGainsDb(settings),
                    isSelected: selectedDisplayItem == index,
                    isCreateAction: entry.type == _EqualizerSelectionEntryType.createCustom,
                    isActive: isActive,
                    onTap: () async => _handleEntrySelection(index),
                    onEdit: entry.customPreset == null
                        ? null
                        : () => _openEditor(EqualizerEditorArgs.edit(entry.customPreset!)),
                    onDelete: entry.customPreset == null
                        ? null
                        : () async => _deleteCustomEq(entry.customPreset!),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _EqualizerSelectionEntryType { createCustom, preset, custom }

class _EqualizerSelectionEntry {
  final _EqualizerSelectionEntryType type;
  final EqualizerPreset? preset;
  final CustomEqualizerPreset? customPreset;

  const _EqualizerSelectionEntry._({
    required this.type,
    this.preset,
    this.customPreset,
  });

  const _EqualizerSelectionEntry.createCustom()
      : this._(type: _EqualizerSelectionEntryType.createCustom);

  const _EqualizerSelectionEntry.preset(EqualizerPreset preset)
      : this._(type: _EqualizerSelectionEntryType.preset, preset: preset);

  const _EqualizerSelectionEntry.custom(CustomEqualizerPreset customPreset)
      : this._(type: _EqualizerSelectionEntryType.custom, customPreset: customPreset);

  String get title {
    switch (type) {
      case _EqualizerSelectionEntryType.createCustom:
        return 'Create Custom EQ';
      case _EqualizerSelectionEntryType.preset:
        return preset!.title;
      case _EqualizerSelectionEntryType.custom:
        return customPreset!.name;
    }
  }

  String get subtitle {
    switch (type) {
      case _EqualizerSelectionEntryType.createCustom:
        return 'Open the full 10-band editor';
      case _EqualizerSelectionEntryType.preset:
        return preset!.hasNeutralCurve ? 'Neutral curve' : _presetDescription(preset!);
      case _EqualizerSelectionEntryType.custom:
        return customPreset!.curveSummary.replaceAll('High', 'Treble');
    }
  }

  List<double> bandGainsDb(SettingsPreferencesModel settings) {
    switch (type) {
      case _EqualizerSelectionEntryType.createCustom:
        return settings.activeEqualizerBandGainsDb;
      case _EqualizerSelectionEntryType.preset:
        return preset!.approximateBandGainsDb;
      case _EqualizerSelectionEntryType.custom:
        return customPreset!.bandGainsDb;
    }
  }
}

class _EqualizerOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<double> bandGainsDb;
  final bool isSelected;
  final bool isCreateAction;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _EqualizerOptionTile({
    required this.title,
    required this.subtitle,
    required this.bandGainsDb,
    required this.isSelected,
    required this.isCreateAction,
    required this.isActive,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = isSelected ? CupertinoColors.white : CupertinoColors.black;
    final subtitleColor = isSelected
        ? CupertinoColors.white.withValues(alpha: 0.82)
        : CupertinoColors.black.withValues(alpha: 0.56);
    final actionColor = isSelected
        ? CupertinoColors.white.withValues(alpha: 0.94)
        : CupertinoColors.black.withValues(alpha: 0.62);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 64,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: isSelected
                ? const Border(
                    top: BorderSide(color: AppPalette.selectedTileTopBorderColor),
                    bottom: BorderSide(color: AppPalette.selectedTileBottomBorderColor),
                  )
                : null,
            gradient: isSelected
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppPalette.selectedTileGradientColor1,
                      AppPalette.selectedTileGradientColor2,
                    ],
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                SizedBox(
                  height: 42,
                  width: 58,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isCreateAction
                          ? const Color(0xFFD9ECFF)
                          : const Color(0xFF11151A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF5F94D8), width: 1.2),
                    ),
                    child: isCreateAction
                        ? const Icon(CupertinoIcons.add, size: 22, color: Color(0xFF205AA3))
                        : Padding(
                            padding: const EdgeInsets.all(5),
                            child: CustomPaint(
                              painter: _MiniEqCurvePainter(bandGainsDb: bandGainsDb),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isActive ? '$title  Active' : title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: subtitleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  _InlineActionButton(
                    icon: CupertinoIcons.pencil,
                    color: actionColor,
                    onTap: onEdit!,
                  ),
                if (onDelete != null)
                  _InlineActionButton(
                    icon: CupertinoIcons.delete,
                    color: actionColor,
                    onTap: onDelete!,
                  ),
                if (isSelected)
                  const Icon(CupertinoIcons.right_chevron, color: CupertinoColors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _InlineActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

class _MiniEqCurvePainter extends CustomPainter {
  final List<double> bandGainsDb;

  const _MiniEqCurvePainter({required this.bandGainsDb});

  @override
  void paint(Canvas canvas, Size size) {
    final zeroPaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), zeroPaint);

    final path = Path();
    for (var index = 0; index < bandGainsDb.length; index++) {
      final x = bandGainsDb.length == 1 ? size.width / 2 : size.width * index / (bandGainsDb.length - 1);
      final normalized = (bandGainsDb[index] - CustomEqualizerPreset.minGainDb) /
          (CustomEqualizerPreset.maxGainDb - CustomEqualizerPreset.minGainDb);
      final y = size.height - normalized * size.height;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final glowPaint = Paint()
      ..color = const Color(0xFF41BFFF).withValues(alpha: 0.28)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final curvePaint = Paint()
      ..color = const Color(0xFF84D8FF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, curvePaint);
  }

  @override
  bool shouldRepaint(covariant _MiniEqCurvePainter oldDelegate) {
    return oldDelegate.bandGainsDb != bandGainsDb;
  }
}

String _presetDescription(EqualizerPreset preset) {
  switch (preset) {
    case EqualizerPreset.bassBooster:
      return 'More low-end punch';
    case EqualizerPreset.bassReducer:
      return 'Cuts heavy lows';
    case EqualizerPreset.trebleBooster:
      return 'Brighter high-end detail';
    case EqualizerPreset.trebleReducer:
      return 'Softens sharp highs';
    case EqualizerPreset.vocalBooster:
    case EqualizerPreset.spokenWord:
      return 'Brings vocals forward';
    case EqualizerPreset.smallSpeakers:
      return 'Compensates for tiny speakers';
    case EqualizerPreset.flat:
    case EqualizerPreset.off:
      return 'Neutral curve';
    default:
      return 'Built-in EQ curve';
  }
}
