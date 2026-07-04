import 'package:flutter/cupertino.dart';

enum WheelStyle {
  modern,
  classic;

  static WheelStyle fromName(String raw) {
    try {
      return WheelStyle.values.byName(raw);
    } catch (_) {
      return WheelStyle.modern;
    }
  }

  String title(BuildContext context) {
    switch (this) {
      case WheelStyle.modern:
        return 'Modern';
      case WheelStyle.classic:
        return 'Classic';
    }
  }
}
