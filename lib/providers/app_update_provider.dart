import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_update_config.dart';
import '../services/app_update_service.dart';
import 'auth_provider.dart';
import 'service_providers.dart';

/// Live admin-managed release config (`app_config/update`).
///
/// A stream, so raising the version in the admin panel reaches open apps
/// without a restart. An error or missing document yields the safe default
/// (nothing configured → nobody is prompted).
final appUpdateConfigProvider =
    StreamProvider<AppUpdateConfig>((ref) {
  // Re-subscribe when the session lands — see the note on activeBannersProvider.
  ref.watch(firebaseAuthStreamProvider);
  return ref.watch(firestoreServiceProvider).watchAppUpdateConfig();
});

/// This build's version code, read once from the platform.
final installedVersionCodeProvider = FutureProvider<int>(
    (ref) => AppUpdateService.instance.installedVersionCode());

/// Remembers what the member has already been shown, so an optional prompt is
/// not repeated every time the app comes back to the foreground.
///
/// Everything is keyed by the version code being offered, so a NEW release
/// always gets a fresh chance to prompt even if the previous one was snoozed.
class UpdatePromptStore {
  static const _snoozeKey = 'update_snoozed_version';
  static const _snoozeAtKey = 'update_snoozed_at';
  static const _lastCheckKey = 'update_last_check_at';

  /// How long "Later" silences an OPTIONAL prompt for. Long enough not to
  /// nag, short enough that an important release still gets seen.
  static const Duration snooze = Duration(hours: 24);

  /// Minimum gap between config-driven prompts, so returning to the foreground
  /// repeatedly cannot produce a burst of dialogs.
  static const Duration checkInterval = Duration(minutes: 30);

  /// True when an OPTIONAL prompt for [versionCode] is currently snoozed.
  /// A FORCED update never consults this — it cannot be postponed.
  static Future<bool> isSnoozed(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_snoozeKey) != versionCode) return false;
    final at = prefs.getInt(_snoozeAtKey) ?? 0;
    final since = DateTime.now().millisecondsSinceEpoch - at;
    return since < snooze.inMilliseconds;
  }

  static Future<void> snoozeVersion(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_snoozeKey, versionCode);
    await prefs.setInt(
        _snoozeAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Throttle: true when enough time has passed to prompt again.
  static Future<bool> mayCheckNow() async {
    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getInt(_lastCheckKey) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - at >=
        checkInterval.inMilliseconds;
  }

  static Future<void> markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _lastCheckKey, DateTime.now().millisecondsSinceEpoch);
  }
}

/// What this build should do about updating, right now.
///
/// Resolves to [AppUpdateRequirement.none] whenever anything is unknown — the
/// config is still loading, the document does not exist, or the installed
/// version could not be read. Being unsure must never block the app.
final updateRequirementProvider =
    Provider<AppUpdateRequirement>((ref) {
  final config = ref.watch(appUpdateConfigProvider).valueOrNull;
  final installed = ref.watch(installedVersionCodeProvider).valueOrNull;
  if (config == null || installed == null) return AppUpdateRequirement.none;
  return config.requirementFor(installed);
});

/// Bumped every time the app returns to the foreground.
///
/// The config itself is a live Firestore stream, so a release published while
/// the app is open reaches it on its own. This covers the other case: the app
/// was backgrounded for a long time, the config changed meanwhile, and nothing
/// would otherwise re-run the prompt logic on the way back in (spec §8).
final updateRecheckTickProvider = StateProvider<int>((ref) => 0);

/// Admin controller for the release config.
class AppUpdateConfigController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> save(Map<String, dynamic> fields) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(firestoreServiceProvider).saveAppUpdateConfig(fields));
  }
}

final appUpdateConfigControllerProvider =
    NotifierProvider<AppUpdateConfigController, AsyncValue<void>>(
        AppUpdateConfigController.new);
