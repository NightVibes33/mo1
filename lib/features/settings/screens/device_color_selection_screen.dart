import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/native_color_picker_service.dart';
import 'package:dope/features/custom_screen_elements/custom_screen.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/features/settings/models/custom_device_theme.dart';
import 'package:dope/features/settings/models/device_color.dart';
import 'package:dope/features/settings/models/settings_preferences_model.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceColorSelectionScreen extends ConsumerStatefulWidget {
  const DeviceColorSelectionScreen({super.key});

  @override
  ConsumerState createState() => _DeviceColorSelectionScreenState();
}

class _DeviceColorSelectionScreenState extends ConsumerState
    with CustomScreen {
  bool _didSeedSelection = false;

  @override
  String get routeName => Routes.deviceColor.name;

  @override
  List<_ColorSelectionEntry> get displayItems {
    final settings = ref.read(settingsPreferencesControllerProvider);
    return [
      const _ColorSelectionEntry.createCustom(),
      ...settings.customDeviceThemes.map(_ColorSelectionEntry.custom),
      ...DeviceColor.values.map(_ColorSelectionEntry.preset),
    ];
  }

  @override
  Future<void> onSelectPressed() => _handleEntrySelection(selectedDisplayItem);

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsPreferencesControllerProvider);
    selectedDisplayItem = _selectedIndexForSettings(settings);
    _didSeedSelection = true;
  }

  int _selectedIndexForSettings(SettingsPreferencesModel settings) {
    if (settings.activeCustomDeviceTheme != null) {
      final customIndex = settings.customDeviceThemes.indexWhere(
        (theme) => theme.id == settings.activeCustomDeviceTheme!.id,
      );
      if (customIndex >= 0) {
        return 1 + customIndex;
      }
    }

    final presetIndex = DeviceColor.values.indexOf(settings.deviceColor);
    return 1 + settings.customDeviceThemes.length + (presetIndex < 0 ? 0 : presetIndex);
  }

  Future<void> _handleEntrySelection(int index) async {
    if (index < 0 || index >= displayItems.length) {
      return;
    }

    final entry = displayItems[index];
    setState(() => selectedDisplayItem = index);

    switch (entry.type) {
      case _ColorSelectionEntryType.createCustom:
        await _showCreateCustomThemeDialog();
        break;
      case _ColorSelectionEntryType.preset:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .setDeviceColor(entry.deviceColor!);
        break;
      case _ColorSelectionEntryType.custom:
        await ref
            .read(settingsPreferencesControllerProvider.notifier)
            .selectCustomDeviceTheme(entry.customTheme!.id);
        break;
    }
  }

  Future<void> _showCreateCustomThemeDialog() async {
    final settings = ref.read(settingsPreferencesControllerProvider);
    final defaultName = 'Custom ${settings.customDeviceThemes.length + 1}';
    final currentStyle = settings.resolveDeviceColorStyle();
    final nameController = TextEditingController(text: defaultName);
    Color primaryColor = currentStyle.frameGradientColors.first;
    Color secondaryColor = currentStyle.frameGradientColors.last;

    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickPrimary() async {
              final pickedColor = await NativeColorPickerService.pickColor(
                initialColor: primaryColor,
              );
              if (pickedColor != null) {
                setDialogState(() => primaryColor = pickedColor);
              }
            }

            Future<void> pickSecondary() async {
              final pickedColor = await NativeColorPickerService.pickColor(
                initialColor: secondaryColor,
              );
              if (pickedColor != null) {
                setDialogState(() => secondaryColor = pickedColor);
              }
            }

            return CupertinoAlertDialog(
              title: const Text('Create Custom Theme'),
              content: Column(
                children: [
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: nameController,
                    placeholder: 'Theme Name',
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 12),
                  _ColorPickerRow(
                    label: 'Primary',
                    color: primaryColor,
                    onTap: pickPrimary,
                  ),
                  const SizedBox(height: 8),
                  _ColorPickerRow(
                    label: 'Secondary',
                    color: secondaryColor,
                    onTap: pickSecondary,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Uses the native iOS color picker.',
                    style: TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
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
                    final theme = await ref
                        .read(settingsPreferencesControllerProvider.notifier)
                        .saveCustomDeviceTheme(
                          name: nameController.text,
                          primaryColor: primaryColor,
                          secondaryColor: secondaryColor,
                        );
                    if (!mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                    final settingsAfterSave = ref.read(
                      settingsPreferencesControllerProvider,
                    );
                    final customIndex = settingsAfterSave.customDeviceThemes
                        .indexWhere((savedTheme) => savedTheme.id == theme.id);
                    if (customIndex >= 0) {
                      setState(() => selectedDisplayItem = 1 + customIndex);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsPreferencesControllerProvider);
    final entries = displayItems;
    if (_didSeedSelection) {
      final safeIndex = selectedDisplayItem.clamp(0, entries.length - 1) as int;
      if (safeIndex != selectedDisplayItem) {
        selectedDisplayItem = safeIndex;
      }
    }

    final activeCustomThemeId = settings.activeCustomDeviceTheme?.id;
    final activePreset = settings.deviceColor;

    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.deviceColor.title(context)),
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                padding: listViewPadding,
                itemCount: entries.length,
                prototypeItem: _ThemeOptionTile(
                  title: 'Custom Theme',
                  previewStyle: DeviceColor.silver.style(),
                  isSelected: false,
                  isCreateAction: false,
                  onTap: () {},
                ),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final isSelected = selectedDisplayItem == index;
                  final previewStyle = entry.previewStyle(
                    useColorTextures: settings.useColorTextures,
                  );
                  final isActiveTheme = entry.type == _ColorSelectionEntryType.custom
                      ? activeCustomThemeId == entry.customTheme?.id
                      : entry.type == _ColorSelectionEntryType.preset
                      ? activeCustomThemeId == null && activePreset == entry.deviceColor
                      : false;

                  return _ThemeOptionTile(
                    title: entry.title(context),
                    previewStyle: previewStyle,
                    isSelected: isSelected,
                    isCreateAction: entry.type == _ColorSelectionEntryType.createCustom,
                    isActiveTheme: isActiveTheme,
                    onTap: () async => _handleEntrySelection(index),
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

enum _ColorSelectionEntryType { createCustom, preset, custom }

class _ColorSelectionEntry {
  final _ColorSelectionEntryType type;
  final DeviceColor? deviceColor;
  final CustomDeviceTheme? customTheme;

  const _ColorSelectionEntry._({
    required this.type,
    this.deviceColor,
    this.customTheme,
  });

  const _ColorSelectionEntry.createCustom()
    : this._(type: _ColorSelectionEntryType.createCustom);

  const _ColorSelectionEntry.preset(DeviceColor deviceColor)
    : this._(type: _ColorSelectionEntryType.preset, deviceColor: deviceColor);

  const _ColorSelectionEntry.custom(CustomDeviceTheme customTheme)
    : this._(type: _ColorSelectionEntryType.custom, customTheme: customTheme);

  String title(BuildContext context) {
    switch (type) {
      case _ColorSelectionEntryType.createCustom:
        return 'Create Custom Theme';
      case _ColorSelectionEntryType.preset:
        return deviceColor!.title(context);
      case _ColorSelectionEntryType.custom:
        return customTheme!.name;
    }
  }

  DeviceColorStyle previewStyle({required bool useColorTextures}) {
    switch (type) {
      case _ColorSelectionEntryType.createCustom:
        return DeviceColor.silver.style(useColorTextures: useColorTextures);
      case _ColorSelectionEntryType.preset:
        return deviceColor!.style(useColorTextures: useColorTextures);
      case _ColorSelectionEntryType.custom:
        return customTheme!.style(useColorTextures: useColorTextures);
    }
  }
}

class _ThemeOptionTile extends StatelessWidget {
  final String title;
  final DeviceColorStyle previewStyle;
  final bool isSelected;
  final bool isCreateAction;
  final bool isActiveTheme;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.title,
    required this.previewStyle,
    required this.isSelected,
    required this.onTap,
    this.isCreateAction = false,
    this.isActiveTheme = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = isSelected ? CupertinoColors.white : CupertinoColors.black;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 30,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: isSelected
                ? const Border(
                    top: BorderSide(
                      color: AppPalette.selectedTileTopBorderColor,
                    ),
                    bottom: BorderSide(
                      color: AppPalette.selectedTileBottomBorderColor,
                    ),
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
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isCreateAction
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFEDF4FF),
                              Color(0xFF85B9FF),
                            ],
                          )
                        : LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: previewStyle.frameGradientColors,
                          ),
                    border: Border.all(
                      color: isCreateAction
                          ? const Color(0xFF5F94D8)
                          : previewStyle.controlBorderColor,
                      width: 1.5,
                    ),
                  ),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: isCreateAction
                        ? const Icon(
                            CupertinoIcons.add,
                            size: 12,
                            color: Color(0xFF205AA3),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isActiveTheme ? '$title  Active' : title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  const Icon(
                    CupertinoIcons.right_chevron,
                    color: CupertinoColors.white,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorPickerRow extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ColorPickerRow({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: CupertinoColors.black.withValues(alpha: 0.12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
