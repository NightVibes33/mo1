import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeColorPickerService {
  NativeColorPickerService._();

  static const MethodChannel _channel = MethodChannel('mo1/color_picker');

  static Future<Color?> pickColor({required Color initialColor}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }

    final hex = await _channel.invokeMethod<String>('pickColor', {
      'initialHex': _toHex(initialColor),
    });
    if (hex == null || hex.isEmpty) {
      return null;
    }
    return _fromHex(hex);
  }

  static String _toHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static Color _fromHex(String hex) {
    final normalized = hex.replaceAll('#', '').trim();
    final value = int.tryParse(normalized, radix: 16) ?? 0xFFFFFF;
    return Color(0xFF000000 | value);
  }
}
