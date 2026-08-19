import 'dart:async' show TimeoutException;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show PlatformException;

/// Domain-level authentication error with a user-friendly [message].
///
/// All auth/firestore failures are normalised into this type by
/// [AuthException.from] so the UI never has to inspect raw Firebase/Google
/// exceptions. [cancelled] is true when the user simply dismissed the Google
/// account picker — callers usually want to ignore that silently.
class AuthException implements Exception {
  final String message;
  final String code;
  final bool cancelled;

  const AuthException(this.message, {this.code = 'unknown', this.cancelled = false});

  /// Sentinel used when the user dismisses the Google account chooser.
  static const AuthException userCancelled =
      AuthException('Sign-in cancelled.', code: 'cancelled', cancelled: true);

  @override
  String toString() => message;

  /// Convert any thrown error into a friendly [AuthException].
  factory AuthException.from(Object error) {
    // User dismissed the Google sheet (google_sign_in throws this code).
    if (error is PlatformException) {
      switch (error.code) {
        case 'sign_in_canceled':
        case 'canceled':
          return AuthException.userCancelled;
        case 'network_error':
          return const AuthException(
            'No internet connection. Please check your network and try again.',
            code: 'network_error',
          );
        case 'sign_in_failed':
          // The underlying com.google.android.gms.common.api.ApiException
          // code is embedded in the message, e.g. "ApiException: 10: ...".
          final msg = error.message ?? '';
          final apiCode = RegExp(r'ApiException:\s*(\d+)').firstMatch(msg)?.group(1)
              ?? (msg.contains('10') ? '10' : null);
          switch (apiCode) {
            case '10':
              // DEVELOPER_ERROR: SHA-1 fingerprint / OAuth client mismatch,
              // or the package name doesn't match google-services.json.
              return const AuthException(
                'Google Sign-In is not configured correctly for this app '
                '(missing/incorrect SHA-1 fingerprint or OAuth client). '
                'See FIREBASE_SETUP.md.',
                code: 'sign_in_failed_10',
              );
            case '12500':
              // SIGN_IN_FAILED: usually the OAuth consent screen is
              // unconfigured/unpublished, the signing account isn't a test
              // user, or Google Play Services on the device is outdated.
              return const AuthException(
                'Google Sign-In failed (12500). Check that the OAuth consent '
                'screen has a support email set and is published (or the '
                'account is added as a test user), and that Google Play '
                'Services is up to date on this device. See FIREBASE_SETUP.md.',
                code: 'sign_in_failed_12500',
              );
            case '7':
              return const AuthException(
                'No internet connection. Please check your network and try again.',
                code: 'sign_in_failed_network',
              );
            case '8':
              return const AuthException(
                'Google Sign-In hit a temporary internal error. Please try again.',
                code: 'sign_in_failed_internal',
              );
            default:
              return AuthException(
                'Google Sign-In failed${msg.isNotEmpty ? ' ($msg)' : ''}. '
                'Please try again.',
                code: 'sign_in_failed',
              );
          }
        default:
          return AuthException(
            error.message ?? 'Google Sign-In failed. Please try again.',
            code: error.code,
          );
      }
    }

    if (error is FirebaseAuthException) {
      // App Check enforcement rejects the request BEFORE the credential is even
      // considered. Firebase reports it as a generic `internal-error` whose
      // message names App Check, so match on the message rather than the code —
      // otherwise a brand-new account just sees "An internal error occurred".
      if (_mentionsAppCheck(error.message) ||
          error.code == 'firebase-app-check-token-is-invalid') {
        return const AuthException(
          'Sign-in was blocked by Firebase App Check — this build is not '
          'registered, and no app code can work around that.\n\n'
          'Fastest fix: Firebase Console > Build > App Check > APIs tab > '
          'Authentication > Unenforce.\n\n'
          'Proper fix: register this build — Play Integrity SHA-256 for a '
          'release build, or its debug token for a debug build. '
          'See FIREBASE_SETUP.md section 3b.',
          code: 'app-check-token-invalid',
        );
      }
      switch (error.code) {
        case 'network-request-failed':
          return const AuthException(
            'No internet connection. Please check your network and try again.',
            code: 'network-request-failed',
          );
        case 'account-exists-with-different-credential':
          return const AuthException(
            'An account already exists with the same email using a different '
            'sign-in method.',
            code: 'account-exists-with-different-credential',
          );
        // Password login. Modern Firebase projects have e-mail-enumeration
        // protection ON, which collapses "no such account" and "wrong password"
        // into `invalid-credential` — so all three get the same, deliberately
        // non-enumerating message.
        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
          return const AuthException(
            'Incorrect mobile number / email or password. Please check your '
            'details and try again.',
            code: 'invalid-credential',
          );
        case 'invalid-email':
          return const AuthException(
            'Enter a valid 10-digit mobile number or email address.',
            code: 'invalid-email',
          );
        case 'email-already-in-use':
          return const AuthException(
            'An account already exists with these details. Please sign in '
            'instead, or use Forgot Password.',
            code: 'email-already-in-use',
          );
        case 'weak-password':
          return const AuthException(
            'Choose a stronger password — at least 6 characters.',
            code: 'weak-password',
          );
        case 'too-many-requests':
          return const AuthException(
            'Too many attempts. Please wait a few minutes and try again.',
            code: 'too-many-requests',
          );
        case 'user-disabled':
          return const AuthException(
            'This account has been disabled. Please contact support.',
            code: 'user-disabled',
          );
        case 'operation-not-allowed':
          // Firebase raises this for ANY disabled sign-in method — email and
          // password, phone, anonymous, Google. Naming Google here was wrong
          // and actively misleading: it is what made the Forgot Password page,
          // which never touches Google, report "Google Sign-In is not enabled"
          // while Google was in fact enabled and some OTHER provider was not.
          return const AuthException(
            'This sign-in method is not enabled for this app. Please contact '
            'support.',
            code: 'operation-not-allowed',
          );
        default:
          return AuthException(
            error.message ?? 'Authentication failed. Please try again.',
            code: error.code,
          );
      }
    }

    if (error is AuthException) return error;

    // A step of the sign-in chain stopped responding. Every step is bounded, so
    // this surfaces as a real, retryable error rather than an endless spinner.
    if (error is TimeoutException) {
      return const AuthException(
        'Google Sign-In did not respond in time. Please check your internet '
        'connection and try again.',
        code: 'timeout',
      );
    }

    return AuthException('Something went wrong. Please try again. ($error)');
  }

  /// Whether [message] is a Firebase App Check rejection.
  static bool _mentionsAppCheck(String? message) {
    if (message == null) return false;
    final m = message.toLowerCase();
    return m.contains('app check');
  }
}
