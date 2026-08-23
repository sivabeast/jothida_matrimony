import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_config.dart';

/// How an update attempt finished, so the caller can tell the member something
/// truthful instead of guessing.
enum UpdateLaunchOutcome {
  /// Play accepted the flow (flexible download started, or the immediate flow
  /// completed / is completing).
  started,

  /// Play could not run the flow, so the Play Store listing was opened.
  openedStore,

  /// The member backed out of Play's own dialog.
  cancelled,

  /// Nothing worked — neither Play nor the store link.
  failed,
}

/// Google Play **In-App Updates** plus a real Play Store fallback.
///
/// Two independent things decide whether a member is prompted:
///
///  * the admin-managed [AppUpdateConfig] decides IF and how urgently (that
///    lives in Firestore so a release can be announced without shipping code);
///  * Play decides HOW the update actually happens.
///
/// Everything here is best-effort and never throws. A device with no Play
/// Store, a sideloaded build, or no network must keep working — an OPTIONAL
/// update can always be skipped, and even a forced one falls back to opening
/// the store listing rather than trapping the member in a dead dialog.
///
/// IMPORTANT (testing): `InAppUpdate.checkForUpdate()` only reports an update
/// for a build **installed by Google Play** whose version code is lower than
/// one live on a Play track. It always reports "no update" for a locally
/// installed debug/release APK. That is Play's behaviour, not a bug — which is
/// exactly why the Firestore config exists as the decision source and Play is
/// used only to carry out the update.
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  /// Guards against overlapping flows: Play's update UI is a full-screen
  /// activity and starting a second one while the first is showing throws.
  bool _inFlight = false;

  /// Cached so the version is read from the platform once per process.
  int? _installedVersionCode;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// This build's version code (the `+N` in pubspec's `version:`).
  ///
  /// Returns 0 when it cannot be read, which every caller treats as "do not
  /// prompt" — never as "out of date".
  Future<int> installedVersionCode() async {
    final cached = _installedVersionCode;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      final code = int.tryParse(info.buildNumber.trim()) ?? 0;
      _installedVersionCode = code;
      return code;
    } catch (e) {
      debugPrint('[AppUpdate] could not read the installed version: $e');
      _installedVersionCode = 0;
      return 0;
    }
  }

  Future<String> installedVersionName() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '';
    }
  }

  /// Runs the update for [requirement].
  ///
  /// Forced → Play's IMMEDIATE flow (Play itself blocks the app until the
  /// update finishes). Optional → the FLEXIBLE flow, which downloads in the
  /// background and lets the member keep using the app.
  ///
  /// Whatever Play cannot do, the store listing does: every failure path ends
  /// in [openStoreListing] rather than a dead end.
  Future<UpdateLaunchOutcome> startUpdate({
    required AppUpdateRequirement requirement,
    required AppUpdateConfig config,
  }) async {
    if (_inFlight) return UpdateLaunchOutcome.started;
    _inFlight = true;
    try {
      if (!_supported) return await _fallback(config);

      AppUpdateInfo info;
      try {
        info = await InAppUpdate.checkForUpdate()
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        // No Play Services, sideloaded build, offline, timeout…
        debugPrint('[AppUpdate] Play check unavailable ($e) — opening store.');
        return await _fallback(config);
      }

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        // Play does not know about the release yet (staged rollout, or this
        // build was not installed by Play). The store listing still lets the
        // member update by hand.
        debugPrint('[AppUpdate] Play reports ${info.updateAvailability} — '
            'opening store instead.');
        return await _fallback(config);
      }

      final immediate = requirement == AppUpdateRequirement.forced;
      final allowed =
          immediate ? info.immediateUpdateAllowed : info.flexibleUpdateAllowed;
      if (!allowed) {
        debugPrint('[AppUpdate] Play vetoed the '
            '${immediate ? 'immediate' : 'flexible'} flow — opening store.');
        return await _fallback(config);
      }

      try {
        if (immediate) {
          await InAppUpdate.performImmediateUpdate();
        } else {
          await InAppUpdate.startFlexibleUpdate();
          // The bytes are downloaded; completing installs and restarts. A
          // failure here is not fatal — Play finishes the install on its own
          // schedule.
          try {
            await InAppUpdate.completeFlexibleUpdate();
          } catch (e) {
            debugPrint('[AppUpdate] flexible completion deferred: $e');
          }
        }
        return UpdateLaunchOutcome.started;
      } catch (e) {
        // The member dismissed Play's dialog, or the install failed.
        debugPrint('[AppUpdate] update flow ended early: $e');
        return UpdateLaunchOutcome.cancelled;
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<UpdateLaunchOutcome> _fallback(AppUpdateConfig config) async =>
      await openStoreListing(config)
          ? UpdateLaunchOutcome.openedStore
          : UpdateLaunchOutcome.failed;

  /// Opens the app's real Play listing. Tries the `market://` scheme first so
  /// the Play app handles it directly, then the https URL for devices without
  /// the Play app (or with it disabled).
  Future<bool> openStoreListing(AppUpdateConfig config) async {
    final https = config.effectivePlayStoreUrl;
    final market = https.startsWith('market://')
        ? https
        : https.replaceFirst(
            'https://play.google.com/store/apps/details', 'market://details');
    for (final url in {market, https}) {
      try {
        final ok = await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication);
        if (ok) return true;
      } catch (e) {
        debugPrint('[AppUpdate] could not open $url: $e');
      }
    }
    return false;
  }
}
