import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_check_config.dart';
import 'core/navigation/root_navigator.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'models/master_data.dart';
import 'providers/locale_provider.dart';
import 'router/app_router.dart';
import 'screens/settings/language_screen.dart';
import 'services/firebase/fcm_service.dart';
import 'services/firebase/master_data_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Firebase core must be ready before any auth/Firestore call. Bound it so a
    // misconfigured or unreachable backend can't hang the launch indefinitely.
    await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 20));
    // Offline persistence + a generous cache make every page open from local
    // data instantly and cut repeat Firestore reads. Persistence is ON by
    // default on mobile, but we set it explicitly (and bump the cache to
    // unlimited) so cached lists/profiles survive between launches and heavy
    // scrolling. Must run before the first Firestore access.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
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
  // Warm the Religion/Caste/Subcaste master data (Firestore-first) in the
  // background so its Tamil names are registered with the value localizer
  // before any stored caste is rendered — a caste then displays in Tamil
  // app-wide (spec §13/§14), not only inside the profile wizard. Non-blocking
  // and best-effort: a failure just leaves English display until a screen that
  // uses the lists loads them itself.
  unawaited(
    MasterDataService().getReligions().catchError((Object e) {
      debugPrint('Master-data warm-up skipped (non-fatal): $e');
      return const <Religion>[];
    }),
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

    // Force update no longer replaces the router with a blocking screen —
    // the user lands on Home normally and a premium non-dismissible popup
    // (force_update_dialog.dart, wired in HomeScreen) carries the store link.

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
