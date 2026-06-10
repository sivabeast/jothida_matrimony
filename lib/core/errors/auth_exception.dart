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
          // ApiException 10 = DEVELOPER_ERROR (SHA-1 / OAuth client mismatch).
          final isDeveloperError = (error.message ?? '').contains('10');
          return AuthException(
            isDeveloperError
                ? 'Google Sign-In is not configured correctly for this app '
                    '(missing SHA-1 fingerprint or OAuth client). See FIREBASE_SETUP.md.'
                : 'Google Sign-In failed. Please try again.',
            code: 'sign_in_failed',
          );
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

    return AuthException('Something went wrong. Please try again. ($error)');
  }
}
