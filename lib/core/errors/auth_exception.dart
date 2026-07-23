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
        case 'invalid-credential':
          return const AuthException(
            'The sign-in credential is invalid or has expired. Please try again.',
            code: 'invalid-credential',
          );
        case 'user-disabled':
          return const AuthException(
            'This account has been disabled. Please contact support.',
            code: 'user-disabled',
          );
        case 'operation-not-allowed':
          return const AuthException(
            'Google Sign-In is not enabled for this project. Enable it in the '
            'Firebase Console (Authentication > Sign-in method).',
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
}
