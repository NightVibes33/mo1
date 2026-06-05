import 'package:classipod/classipod_app.dart';
import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/features/app_startup/screens/app_startup_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
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

  await JustAudioBackground.init(
    androidNotificationChannelId: 'mo1.audio.playback',
    androidNotificationChannelName: 'mo1 Playback',
    androidNotificationOngoing: true,
  );

  runApp(const ProviderScope(child: AppStartupScreen(app: ClassipodApp())));
}
