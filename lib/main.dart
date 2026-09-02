import 'dart:async';

import 'package:dopi/classipod_app.dart';
import 'package:dopi/core/constants/app_palette.dart';
import 'package:dopi/core/services/crash_log_service.dart';
import 'package:dopi/features/app_startup/screens/app_startup_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runZonedGuarded<void>(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          systemNavigationBarColor: AppPalette.transparentColor,
          statusBarColor: AppPalette.transparentColor,
          systemNavigationBarIconBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      );

      runApp(const ProviderScope(child: AppStartupScreen(app: ClassipodApp())));
    },
    CrashLogService.recordGlobalZoneError,
  );
}
