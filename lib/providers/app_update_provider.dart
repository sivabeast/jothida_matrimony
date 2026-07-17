import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_update_config.dart';

/// Live force-update configuration (admin-managed, `app_settings/app_update`).
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

/// The RUNNING app's version (from the platform package info).
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// Non-null when the force-update gate must block the app: force update is ON
/// and the running version is below the minimum supported version.
final forceUpdateRequiredProvider = Provider<AppUpdateConfig?>((ref) {
  final cfg = ref.watch(appUpdateConfigProvider).valueOrNull;
  final version = ref.watch(appVersionProvider).valueOrNull;
  if (cfg == null || version == null) return null;
  if (!cfg.forceUpdate) return null;
  if (cfg.minSupportedVersion.trim().isEmpty) return null;
  return isVersionBelow(version, cfg.minSupportedVersion) ? cfg : null;
});
