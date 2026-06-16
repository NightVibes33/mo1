import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:flutter/cupertino.dart';

enum ClickWheelSensitivity {
  veryLow,
  low,
  medium,
  high;

  String title(BuildContext context) {
    switch (this) {
      case veryLow:
        return context.localization.veryLow;
      case low:
        return context.localization.low;
      case medium:
        return context.localization.medium;
      case high:
        return context.localization.high;
    }
  }
}
