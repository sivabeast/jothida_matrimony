import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLocaleKey = 'app_locale';

/// Loads the saved locale once at startup (null = user hasn't chosen yet).
/// Used to decide whether to show the first-launch language screen.
final initialLocaleProvider = FutureProvider<Locale?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(_kLocaleKey);
  return code != null ? Locale(code) : null;
});

/// The active app locale. Seeded from [initialLocaleProvider]; switching it
/// (via [LocaleNotifier.setLocale]) persists the choice. `null` means no
/// language chosen yet.
///
/// Adding a new language later = add an ARB file + extend [supportedLocales];
/// no other code change needed.
class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() => ref.watch(initialLocaleProvider).valueOrNull;

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

/// The languages the app supports. Extend this list to add more.
const supportedLocales = [Locale('en'), Locale('ta')];
