import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'providers/locale_provider.dart';
import 'router/app_router.dart';
import 'screens/settings/language_screen.dart';
import 'services/firebase/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FcmService().initialize();
  } catch (e, st) {
    // Don't block the UI if Firebase isn't fully configured yet
    // (e.g. while reviewing the frontend before a real Firebase project exists).
    debugPrint('Firebase init skipped: $e\n$st');
  }
  runApp(const ProviderScope(child: JothidaMatrimonyApp()));
}

class JothidaMatrimonyApp extends ConsumerWidget {
  const JothidaMatrimonyApp({super.key});

  // Shared localization config so both the first-launch language screen and the
  // main router app render correctly.
  static const _localizationsDelegates = [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = ref.watch(initialLocaleProvider);
    final locale = ref.watch(localeProvider);

    // While the saved locale is still loading, show a tiny splash.
    if (initial.isLoading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // First launch — no language chosen yet → show the language selector.
    if (locale == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: supportedLocales,
        home: const LanguageScreen(),
      );
    }

    // Normal app, localized.
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      locale: locale,
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: supportedLocales,
      routerConfig: router,
    );
  }
}
