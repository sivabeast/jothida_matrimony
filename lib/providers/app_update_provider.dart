import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_update_config.dart';

/// Live update configuration (admin-managed, `app_settings/app_update`).
/// Yields null while the doc doesn't exist or Firebase is unreachable — the
/// gate treats null as "don't block", so a backend hiccup can never lock the
/// app.
final appUpdateConfigProvider = StreamProvider<AppUpdateConfig?>((ref) {
  return FirebaseFirestore.instance
      .collection('app_settings')
      .doc('app_update')
      .snapshots()
      .map((snap) {
    final data = snap.data();
    return (snap.exists && data != null)
        ? AppUpdateConfig.fromMap(data)
        : null;
  }).handleError((_) => null);
});

/// The RUNNING build's package info — the single source of truth for "which
/// version am I". Nothing in the app (or the admin panel) ever asks a human to
/// type a version number.
final appPackageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

/// The running app's version NAME (e.g. `1.2.0`) — display only.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await ref.watch(appPackageInfoProvider.future);
  return info.version;
});

/// The running app's version CODE (Android `versionCode` / iOS build number).
/// This is the value the update gate compares. Non-numeric build numbers
/// (which shouldn't happen on Android) read as 0 — see
/// [forceUpdateRequiredProvider] for why that is safe.
final appVersionCodeProvider = FutureProvider<int>((ref) async {
  final info = await ref.watch(appPackageInfoProvider.future);
  return int.tryParse(info.buildNumber.trim()) ?? 0;
});

/// Non-null when the force-update gate must BLOCK the app: force update is ON
/// and the installed version code is lower than the published one.
///
/// Deliberately conservative — it returns null (don't block) whenever anything
/// is unknown: config still loading, package info unavailable, or a published
/// code of 0 ("never released"). An installed code of 0 likewise never blocks,
/// so a build with a malformed build number degrades to "no gate" instead of
/// locking every user out.
final forceUpdateRequiredProvider = Provider<AppUpdateConfig?>((ref) {
  final cfg = ref.watch(appUpdateConfigProvider).valueOrNull;
  final installed = ref.watch(appVersionCodeProvider).valueOrNull;
  if (cfg == null || installed == null || installed <= 0) return null;
  if (!cfg.forceUpdate) return null;
  return cfg.isOutdated(installed) ? cfg : null;
});

/// True when a NEWER build is published but the hard gate does not apply —
/// drives the soft, dismissible "Update Available" prompt.
final updateAvailableConfigProvider = Provider<AppUpdateConfig?>((ref) {
  final cfg = ref.watch(appUpdateConfigProvider).valueOrNull;
  final installed = ref.watch(appVersionCodeProvider).valueOrNull;
  if (cfg == null || installed == null || installed <= 0) return null;
  if (!cfg.isOutdated(installed)) return null;
  return cfg.forceUpdate ? null : cfg; // the blocking popup covers force mode
});
