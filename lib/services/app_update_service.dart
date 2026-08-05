import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Google Play **In-App Updates** (Immediate flow).
///
/// This fully replaces the old admin-managed force-update gate: nothing is
/// stored in Firestore, no admin ever publishes a version number, and there is
/// no configuration to keep in sync. Google Play itself is the single source of
/// truth for "is a newer build live?".
///
/// Contract (spec §9):
///   • checked automatically every time the app opens — cold start AND every
///     return from the background;
///   • when Play reports a newer version, the IMMEDIATE update dialog is shown,
///     which blocks the app until the user updates;
///   • once updated, Play stops reporting an available update, so the dialog
///     never appears again until the next release;
///   • completely silent on any failure — a device with no Play Store, a
///     sideloaded/debug build, or no network must never be blocked from using
///     the app.
///
/// IMPORTANT (testing): `InAppUpdate.checkForUpdate()` only ever reports an
/// update for a build that was **installed by Google Play** and whose version
/// code is lower than the one live on a Play track. It always reports
/// "no update" for a locally-installed debug/release APK — that is Play's
/// behaviour, not a bug in this code.
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  /// Guards against overlapping checks: the immediate flow is a full-screen
  /// Play activity, and starting a second one while the first is showing
  /// throws.
  bool _inFlight = false;

  /// Android-only. On any other platform the Play API does not exist, so the
  /// check is skipped rather than throwing.
  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Checks Play for a newer version and, if there is one, starts the
  /// IMMEDIATE update flow. Safe to call as often as you like — concurrent
  /// calls collapse into the one already running.
  ///
  /// Never throws: every failure path is logged and swallowed.
  Future<void> checkAndPromptImmediate() async {
    if (!_supported || _inFlight) return;
    _inFlight = true;
    try {
      final info = await InAppUpdate.checkForUpdate()
          .timeout(const Duration(seconds: 15));
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        debugPrint('[AppUpdate] no update available '
            '(${info.updateAvailability}).');
        return;
      }
      if (!info.immediateUpdateAllowed) {
        // Play can veto the immediate flow (e.g. staleness/priority rules).
        // Nothing else to do — we never fall back to a home-grown blocking
        // screen; the next launch checks again.
        debugPrint('[AppUpdate] immediate update not allowed by Play.');
        return;
      }
      debugPrint('[AppUpdate] newer version '
          '${info.availableVersionCode} — starting immediate update.');
      await InAppUpdate.performImmediateUpdate();
    } on TimeoutException {
      debugPrint('[AppUpdate] check timed out (non-fatal).');
    } catch (e) {
      // Not installed from Play, no Play Services, offline, user cancelled the
      // Play dialog… all non-fatal: the app keeps working and re-checks on the
      // next open.
      debugPrint('[AppUpdate] check/flow skipped (non-fatal): $e');
    } finally {
      _inFlight = false;
    }
  }
}
