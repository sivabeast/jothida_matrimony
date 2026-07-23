import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Firebase **App Check** bootstrap.
///
/// ## Why this exists
///
/// App Check was enabled (and *enforced*) for this project in the Firebase
/// console, but the app never installed a provider. With enforcement ON and no
/// provider, Identity Toolkit rejects the very first `signInWithCredential`
/// call from a brand-new account with:
///
/// ```
/// An internal error has occurred. Firebase App Check token is invalid.
/// ```
///
/// Registering a provider here makes every Firebase SDK attach a valid App
/// Check token to its requests, which is what unblocks first-time Google
/// sign-in.
///
/// ## Provider choice
///
/// * **Release (Android)** → Play Integrity. Requires the app's Play/upload
///   signing SHA-256 to be registered in
///   *Firebase Console → App Check → your Android app*.
/// * **Debug / profile** → the debug provider. On first run it prints a line
///   like `Enter this debug secret into the allow list…` to logcat; that token
///   must be pasted into *App Check → Manage debug tokens* once per machine.
/// * **iOS** → App Attest on release, debug provider otherwise.
/// * **Web** → skipped entirely (no reCAPTCHA site key is configured), so the
///   web build behaves exactly as before.
///
/// ## Failure policy
///
/// Initialisation is **best-effort and bounded**. A misconfigured console, an
/// offline device or a Play-Integrity hiccup must never prevent the app from
/// starting — the sign-in path already surfaces a readable error if App Check
/// then rejects the request.
class AppCheckConfig {
  AppCheckConfig._();

  /// How long activation may take before we stop waiting for it.
  static const Duration _timeout = Duration(seconds: 10);

  /// True once [activate] has completed successfully at least once.
  static bool get isActive => _active;
  static bool _active = false;

  /// Installs the App Check provider for the current platform.
  ///
  /// Safe to call more than once (subsequent calls are no-ops) and safe to call
  /// when Firebase itself failed to initialise — it simply reports and returns.
  static Future<void> activate() async {
    if (_active) return;
    if (kIsWeb) {
      debugPrint('[AppCheck] web build — no provider configured, skipping.');
      return;
    }
    try {
      await FirebaseAppCheck.instance
          .activate(
            // Play Integrity in release; the debug provider elsewhere so
            // emulators and `flutter run` builds keep working.
            androidProvider:
                kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
            appleProvider:
                kReleaseMode ? AppleProvider.appAttest : AppleProvider.debug,
          )
          .timeout(_timeout);
      _active = true;
      debugPrint('[AppCheck] activated '
          '(${kReleaseMode ? 'Play Integrity / App Attest' : 'debug provider'}).');

      // Auto-refresh keeps a valid token in place for long sessions, so a
      // token that expires mid-session can't turn into a spurious
      // "App Check token is invalid" on the next Firestore/Auth call.
      unawaited(
        FirebaseAppCheck.instance
            .setTokenAutoRefreshEnabled(true)
            .catchError((Object e) =>
                debugPrint('[AppCheck] auto-refresh not enabled: $e')),
      );
    } on TimeoutException {
      debugPrint('[AppCheck] activate() timed out after ${_timeout.inSeconds}s '
          '— continuing without App Check. If App Check enforcement is ON in '
          'the Firebase console, sign-in will fail with '
          '"App Check token is invalid".');
    } catch (e, st) {
      debugPrint('[AppCheck] activate() FAILED (continuing): $e\n$st');
    }
  }
}
