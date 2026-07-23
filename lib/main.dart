import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_check_config.dart';
import 'core/navigation/root_navigator.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'providers/app_update_provider.dart';
import 'providers/locale_provider.dart';
import 'router/app_router.dart';
import 'screens/common/update_required_screen.dart';
import 'screens/settings/language_screen.dart';
import 'services/firebase/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Firebase core must be ready before any auth/Firestore call. Bound it so a
    // misconfigured or unreachable backend can't hang the launch indefinitely.
    await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 20));
    // App Check must be installed BEFORE the first Auth/Firestore call.
    // With enforcement ON in the console and no provider, a brand-new Google
    // account fails to sign in with "Firebase App Check token is invalid".
    // Awaited (bounded to 10s inside) so the very first sign-in already carries
    // a token; it never throws.
    await AppCheckConfig.activate();
  } catch (e, st) {
    // Don't block the UI if Firebase isn't fully configured/reachable yet
    // (e.g. while reviewing the frontend before a real Firebase project exists).
    debugPrint('Firebase init failed (continuing): $e\n$st');
  }
  // FCM setup must NOT block first paint: requestPermission() shows a system
  // dialog and token registration can be slow. Initialise it in the background
  // so a slow/denied notification permission never delays app start or login.
  unawaited(
    FcmService()
        .initialize()
        .timeout(const Duration(seconds: 15))
        .catchError((Object e) =>
            debugPrint('FCM initialize skipped (non-fatal): $e')),
  );
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

    // Force-update gate: when the admin has force update ON and this build is
    // below the minimum supported version, the ONLY screen is "Update Now" —
    // no router, no skip. A missing/unreadable config never blocks the app.
    final updateRequired = ref.watch(forceUpdateRequiredProvider);
    if (updateRequired != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: locale,
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: supportedLocales,
        home: UpdateRequiredScreen(config: updateRequired),
      );
    }

    // Normal app, localized.
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
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
