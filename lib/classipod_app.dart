import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:dope/core/navigation/routes.dart';
import 'package:dope/core/services/native_now_playing_sync_service.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:dope/l10n/generated/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ClassipodApp extends ConsumerWidget {
  const ClassipodApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(nativeNowPlayingSyncProvider);
    final languageLocaleCode = ref.watch(
      settingsPreferencesControllerProvider.select(
        (value) => value.languageLocaleCode,
      ),
    );
    final appTheme = ref.watch(
      settingsPreferencesControllerProvider.select((value) => value.appTheme),
    );
    final appTextSize = ref.watch(
      settingsPreferencesControllerProvider.select(
        (value) => value.appTextSize,
      ),
    );
    final router = ref.watch(routerProvider);
    return CupertinoApp.router(
      onGenerateTitle: (context) => context.localization.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: Locale(languageLocaleCode),
      theme: appTheme.toCupertinoTheme(),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final systemScale = mediaQuery.textScaler.scale(1);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(systemScale * appTextSize.scale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
