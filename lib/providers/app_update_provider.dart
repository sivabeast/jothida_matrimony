import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/release_config.dart';
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

/// This build's version NAME ("1.14.0"), for the admin's read-only display
/// (spec §10). Empty when the platform cannot answer.
final installedVersionNameProvider = FutureProvider<String>(
    (ref) => AppUpdateService.instance.installedVersionName());

/// What Google Play says is live on the track right now, or 0 when Play cannot
/// answer (spec §10).
///
/// The second, independent source for "latest published version" — independent
/// because it needs no Firestore document and no admin to have opened the app.
/// A release rolled out on Play is therefore noticed by every device on its
/// own, which is exactly what "version information must be automatically
/// determined from release metadata" asks for.
final playAvailableVersionCodeProvider = FutureProvider<int>(
    (ref) => AppUpdateService.instance.playAvailableVersionCode());

/// The MINIMUM SUPPORTED version this build was compiled with — the floor that
/// travels with the release. Surfaced as a provider purely so the admin screen
/// can display it alongside everything else.
final compiledMinimumVersionCodeProvider =
    Provider<int>((ref) => kMinimumSupportedVersionCode);

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
/// Two sources are consulted and the STRONGER answer wins:
///
///  1. the `app_config/update` document — the minimum supported floor and the
///     admin's Force Update policy (spec §10A);
///  2. Google Play itself — if Play has a newer build live, an update genuinely
///     is available even when nothing has been published to Firestore yet.
///
/// Play can only ever RAISE the outcome from `none` to `optional`; whether that
/// becomes `forced` is the admin's policy decision, never Play's.
///
/// Resolves to [AppUpdateRequirement.none] whenever everything is unknown — the
/// config is still loading, the document does not exist, or the installed
/// version could not be read. Being unsure must never block the app.
final updateRequirementProvider =
    Provider<AppUpdateRequirement>((ref) {
  final config = ref.watch(appUpdateConfigProvider).valueOrNull;
  final installed = ref.watch(installedVersionCodeProvider).valueOrNull;
  if (installed == null || installed <= 0) return AppUpdateRequirement.none;

  final fromConfig =
      config?.requirementFor(installed) ?? AppUpdateRequirement.none;
  if (fromConfig == AppUpdateRequirement.forced) return fromConfig;

  final playLatest = ref.watch(playAvailableVersionCodeProvider).valueOrNull ?? 0;
  if (playLatest > installed) {
    // Play has a newer build. Mandatory only if the admin has said so.
    return (config?.forceUpdate ?? false)
        ? AppUpdateRequirement.forced
        : AppUpdateRequirement.optional;
  }
  return fromConfig;
});

/// Bumped every time the app returns to the foreground.
///
/// The config itself is a live Firestore stream, so a release published while
/// the app is open reaches it on its own. This covers the other case: the app
/// was backgrounded for a long time, the config changed meanwhile, and nothing
/// would otherwise re-run the prompt logic on the way back in (spec §8).
final updateRecheckTickProvider = StateProvider<int>((ref) => 0);

/// Admin controller for the release config.
///
/// The admin has exactly ONE lever here — Force Update on or off (spec §10A).
/// Version NUMBERS are never accepted from a form; they are published by
/// [publishRunningRelease] from the build's own metadata.
class AppUpdateConfigController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Turns the mandatory-update policy on or off. Nothing else is written.
  Future<void> setForceUpdate(bool enabled) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(firestoreServiceProvider)
        .saveAppUpdateConfig({'forceUpdate': enabled}));
  }

  /// Publishes THIS build's own release metadata to `app_config/update`, so
  /// older installs learn what the latest version is (spec §10/§10D).
  ///
  /// The numbers come from the running binary — `PackageInfo` for the version
  /// code and name, [kMinimumSupportedVersionCode] for the floor — so nobody
  /// types them. It only ever moves the recorded version FORWARD: an admin who
  /// happens to open an older build cannot drag the published version back down
  /// and re-prompt everybody.
  ///
  /// Called from the admin App Version screen because the security rules make
  /// `app_config` admin-writable, which is also what stops an ordinary client
  /// from publishing a bogus version and locking everyone out.
  ///
  /// Returns true when something was actually written.
  Future<bool> publishRunningRelease() async {
    final code = await AppUpdateService.instance.installedVersionCode();
    if (code <= 0) return false; // could not read our own build — do nothing
    final name = await AppUpdateService.instance.installedVersionName();
    final current = ref.read(appUpdateConfigProvider).valueOrNull;

    final fields = <String, dynamic>{};
    if (current == null || code > current.latestVersionCode) {
      fields['latestVersionCode'] = code;
      if (name.isNotEmpty) fields['latestVersionName'] = name;
    }
    // The floor is whatever the newest known build compiled with, and it is
    // allowed to move in either direction — lowering it only ever UNLOCKS
    // people, which is always safe.
    if (current == null ||
        current.minimumSupportedVersionCode != kMinimumSupportedVersionCode) {
      fields['minimumSupportedVersionCode'] = kMinimumSupportedVersionCode;
    }
    if (fields.isEmpty) return false;

    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).saveAppUpdateConfig(fields));
    return !state.hasError;
  }
}

final appUpdateConfigControllerProvider =
    NotifierProvider<AppUpdateConfigController, AsyncValue<void>>(
        AppUpdateConfigController.new);
