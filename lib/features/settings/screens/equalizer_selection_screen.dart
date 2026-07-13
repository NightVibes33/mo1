import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/custom_equalizer_preset.dart';
import 'package:dope/features/settings/models/equalizer_preset.dart';
import 'package:dope/features/settings/models/settings_preferences_model.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final customPreset = entries[selectedDisplayItem].customPreset;
    if (customPreset == null) {
      return;
    }
    _showCustomEqActions(customPreset);
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
        await _showCustomEqDialog();
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

  Future<void> _showCustomEqDialog({CustomEqualizerPreset? existingPreset}) async {
    final settings = ref.read(settingsPreferencesControllerProvider);
    final nameController = TextEditingController(
      text: existingPreset?.name ?? 'Custom ${settings.customEqualizerPresets.length + 1}',
    );
    final bandGains = [
      ...(existingPreset?.bandGainsDb ?? settings.activeEqualizerBandGainsDb),
    ];

    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CupertinoAlertDialog(
              title: Text(existingPreset == null ? 'Create Custom EQ' : 'Edit Custom EQ'),
              content: Column(
                children: [
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: nameController,
                    placeholder: 'Preset Name',
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '10-band EQ for MP3 and Navidrome playback. Save applies it right away.',
                    style: TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 330,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var index = 0; index < CustomEqualizerPreset.bandCount; index++)
                            _EqBandSlider(
                              label: CustomEqualizerPreset.bandLabels[index],
                              value: bandGains[index],
                              onChanged: (value) {
                                setDialogState(() => bandGains[index] = value);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setDialogState(() {
                        for (var index = 0; index < bandGains.length; index++) {
                          bandGains[index] = 0;
                        }
                      });
                    },
                    child: const Text('Reset Flat'),
                  ),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () async {
                    final notifier = ref.read(settingsPreferencesControllerProvider.notifier);
                    final preset = existingPreset == null
                        ? await notifier.saveCustomEqualizerPreset(
                            name: nameController.text,
                            bandGainsDb: bandGains,
                          )
                        : await notifier.updateCustomEqualizerPreset(
                            presetId: existingPreset.id,
                            name: nameController.text,
                            bandGainsDb: bandGains,
                          );
                    if (!mounted || preset == null) {
                      return;
                    }
                    Navigator.of(context).pop();
                    final settingsAfterSave = ref.read(settingsPreferencesControllerProvider);
                    final customIndex = settingsAfterSave.customEqualizerPresets
                        .indexWhere((savedPreset) => savedPreset.id == preset.id);
                    if (customIndex >= 0) {
                      setState(() => selectedDisplayItem = 1 + customIndex);
                    }
                  },
                  child: Text(existingPreset == null ? 'Save & Apply' : 'Update & Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCustomEqActions(CustomEqualizerPreset preset) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(preset.name),
        message: const Text('Edit this curve or delete it from this device.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('edit'),
            child: const Text('Edit Custom EQ'),
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
    if (action == 'edit') {
      await _showCustomEqDialog(existingPreset: preset);
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
                  subtitle: 'Bass +0 dB  Mid +0 dB  High +0 dB',
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
                    isSelected: selectedDisplayItem == index,
                    isCreateAction: entry.type == _EqualizerSelectionEntryType.createCustom,
                    isActive: isActive,
                    onTap: () async => _handleEntrySelection(index),
                    onEdit: entry.customPreset == null
                        ? null
                        : () async => _showCustomEqDialog(existingPreset: entry.customPreset),
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
        return 'Build your own 10-band curve';
      case _EqualizerSelectionEntryType.preset:
        return preset!.hasNeutralCurve ? 'Neutral curve' : 'Built-in EQ preset';
      case _EqualizerSelectionEntryType.custom:
        return customPreset!.curveSummary;
    }
  }
}

class _EqualizerOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isCreateAction;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _EqualizerOptionTile({
    required this.title,
    required this.subtitle,
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
        height: 54,
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
                  height: 28,
                  width: 28,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isCreateAction
                            ? const [Color(0xFFEDF4FF), Color(0xFF85B9FF)]
                            : const [Color(0xFF2D2D2F), Color(0xFF09090A)],
                      ),
                      border: Border.all(color: const Color(0xFF5F94D8), width: 1.2),
                    ),
                    child: Icon(
                      isCreateAction ? CupertinoIcons.add : CupertinoIcons.slider_horizontal_3,
                      size: 16,
                      color: isCreateAction ? const Color(0xFF205AA3) : CupertinoColors.white,
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
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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

class _EqBandSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _EqBandSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final signedValue = value > 0 ? '+${value.round()}' : value.round().toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: CupertinoSlider(
              min: CustomEqualizerPreset.minGainDb,
              max: CustomEqualizerPreset.maxGainDb,
              value: value,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '$signedValue dB',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
