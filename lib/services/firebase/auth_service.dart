import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/utils/sign_in_watchdog.dart';

/// Thin wrapper around Firebase Auth + Google Sign-In.
///
/// This class is intentionally limited to *authentication* concerns only —
/// it produces/clears a [User] credential. All Firestore user-document logic
/// lives in `FirestoreService`, and orchestration lives in `AuthRepository`.
/// Every failure is normalised to [AuthException].
class AuthService {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  AuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        // Request the e-mail scope so we always receive the account e-mail.
        // `serverClientId` is the "Web client (auto-created by Google
        // Service)" OAuth client (client_type 3) from
        // android/app/google-services.json. Passing it explicitly makes the
        // ID-token exchange reliable across Play Services versions — without
        // it some devices return a null idToken or fail with
        // PlatformException(sign_in_failed).
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: const ['email'],
              serverClientId:
                  '560906592127-r147po3abrkrppf46bqkaneg1s39815u.apps.googleusercontent.com',
            );

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUser?.uid;

  // ── Phone OTP ─────────────────────────────────────────────────────────────
  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
    required Function(PhoneAuthCredential credential) onAutoVerified,
  }) async {
    debugPrint('[AuthService] verifyPhone: requesting OTP for +91$phoneNumber');
    await _auth.verifyPhoneNumber(
      phoneNumber: '+91$phoneNumber',
      verificationCompleted: (credential) {
        debugPrint('[AuthService] verifyPhone: auto-verification completed.');
        onAutoVerified(credential);
      },
      verificationFailed: (e) {
        final msg = AuthException.from(e).message;
        debugPrint('[AuthService] verifyPhone: verificationFailed: '
            '${e.code} — $msg');
        onError(msg);
      },
      codeSent: (verificationId, resendToken) {
        debugPrint('[AuthService] verifyPhone: codeSent '
            '(verificationId=$verificationId)');
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        debugPrint('[AuthService] verifyPhone: auto-retrieval timeout '
            '(verificationId=$verificationId)');
      },
      timeout: const Duration(seconds: 60),
    );
  }

  Future<UserCredential> signInWithOTP(String verificationId, String otp) {
    debugPrint('[AuthService] signInWithOTP: verifying OTP...');
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    return _guard(() async {
      final cred = await _auth.signInWithCredential(credential);
      debugPrint('[AuthService] signInWithOTP: success. '
          'uid=${cred.user?.uid}, isNewUser=${cred.additionalUserInfo?.isNewUser}');
      return cred;
    });
  }

  // ── Email / Password ──────────────────────────────────────────────────────
  Future<UserCredential> registerWithEmail(String email, String password) {
    debugPrint('[AuthService] registerWithEmail: creating account for $email');
    return _guard(() async {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      debugPrint('[AuthService] registerWithEmail: success. '
          'uid=${cred.user?.uid}');
      return cred;
    });
  }

  Future<UserCredential> signInWithEmail(String email, String password) {
    debugPrint('[AuthService] signInWithEmail: signing in $email');
    return _guard(() async {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      debugPrint('[AuthService] signInWithEmail: success. '
          'uid=${cred.user?.uid}');
      return cred;
    });
  }

  Future<void> sendPasswordReset(String email) {
    debugPrint('[AuthService] sendPasswordReset: sending to $email');
    return _guard(() => _auth.sendPasswordResetEmail(email: email));
  }

  // ── Google ────────────────────────────────────────────────────────────────

  /// How long the *whole* interactive picker step may take before we declare
  /// the result lost. Generous, because the user paces this step — the
  /// watchdog inside [pickWithRecovery] is what catches a lost result quickly.
  static const _pickerTimeout = Duration(minutes: 3);
  static const _tokenTimeout = Duration(seconds: 30);
  static const _credentialTimeout = Duration(seconds: 30);

  /// Runs the full Google → Firebase credential exchange.
  ///
  /// Returns `null` only when the user dismisses the account picker. Any real
  /// failure is thrown as an [AuthException] with a friendly message.
  ///
  /// **Every step is bounded.** This method can never leave the caller waiting
  /// forever: it either returns an account, returns `null` (cancelled), or
  /// throws. That guarantee is what keeps the login spinner from becoming an
  /// infinite loading state.
  Future<UserCredential?> signInWithGoogle() async {
    final sw = Stopwatch()..start();
    void log(String message) =>
        debugPrint('[GoogleSignIn +${sw.elapsedMilliseconds}ms] $message');

    try {
      // 0. Drop any cached Google session first.
      //
      // Two reasons: the account chooser is then always shown (so a user can
      // switch accounts), and — critically — it guarantees Play Services holds
      // NO account, which makes the step-1 recovery probe unambiguous: anything
      // `signInSilently()` returns afterwards can only be the account the user
      // just picked. Best-effort and bounded; a wedged Play Services here must
      // not block the sign-in that follows.
      await _googleSignIn
          .signOut()
          .timeout(const Duration(seconds: 6))
          .catchError((Object e) {
        log('pre-sign-in signOut skipped ($e)');
        return null;
      });

      // 1. Trigger the native Google account chooser.
      log('opening the Google account picker...');
      final googleUser = await pickWithRecovery<GoogleSignInAccount>(
        pick: () => _googleSignIn.signIn(),
        recover: () => _googleSignIn.signInSilently(),
        log: (m) => log('watchdog: $m'),
        timeout: _pickerTimeout,
      ).timeout(
        // Defence in depth: pickWithRecovery already self-bounds, but a hang in
        // its own plumbing must not become an eternal spinner either.
        _pickerTimeout + const Duration(seconds: 10),
        onTimeout: () => throw const AuthException(
          'Google Sign-In did not respond. Please close the app and try again.',
          code: 'google-picker-timeout',
        ),
      );

      if (googleUser == null) {
        // IMPORTANT: `signIn()` returns null for TWO very different things —
        // the user dismissed the chooser, AND Play Services refused to complete
        // the sign-in (most often because this build's signing certificate is
        // not registered as an Android OAuth client, so Google will not issue
        // an ID token). The plugin gives us no way to tell them apart, and the
        // second case used to look like "I picked my account and nothing
        // happened": no navigation, no error, no log.
        //
        // Log both possibilities explicitly, with the elapsed time — a
        // sub-second null means the chooser could not have been interacted
        // with, i.e. it is a configuration failure, not a cancel.
        log('signIn() returned NO account after ${sw.elapsedMilliseconds}ms. '
            'Either the user dismissed the chooser, or Google refused to issue '
            'an ID token for this build. If this was not a dismissal, verify '
            "this build's SHA-1 is registered in Firebase: "
            'dart run tool/check_google_signin_config.dart');
        return null;
      }
      log('account selected: ${googleUser.email}');

      // 2. Obtain the OAuth tokens for the chosen account.
      //
      // After the account is picked, token retrieval is a Play-Services call
      // that normally returns in well under a second. On a misconfigured
      // signing key (SHA-1 not registered in Firebase), a stale Play-Services
      // cache, or a flaky network it can *hang indefinitely* — neither
      // returning nor throwing — which freezes the login spinner forever
      // ("selected the account, then stuck loading"). Bound it so a hang turns
      // into a real, actionable error instead of an eternal spinner.
      final googleAuth = await googleUser.authentication.timeout(
        _tokenTimeout,
        onTimeout: () => throw const AuthException(
          'Google Sign-In timed out while verifying your account. This usually '
          "means this build's SHA-1 fingerprint is not registered in Firebase, "
          'or the network is unstable. Please try again.',
          code: 'google-auth-timeout',
        ),
      );
      log('tokens received (idToken=${googleAuth.idToken != null}, '
          'accessToken=${googleAuth.accessToken != null})');

      // A null idToken almost always means the OAuth client / SHA-1 is not
      // configured in Firebase — surface a clear, actionable error.
      if (googleAuth.idToken == null) {
        throw const AuthException(
          'Google Sign-In could not return an ID token. This usually means the '
          'SHA-1 fingerprint or OAuth client is missing in Firebase. '
          'See FIREBASE_SETUP.md.',
          code: 'missing-id-token',
        );
      }

      // 3. Build a Firebase credential and sign in.
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      log('exchanging the Google credential with Firebase...');
      final userCred = await _auth.signInWithCredential(credential).timeout(
        _credentialTimeout,
        onTimeout: () => throw const AuthException(
          'Signing in took too long. Please check your internet connection and '
          'try again.',
          code: 'firebase-credential-timeout',
        ),
      );
      log('Firebase sign-in succeeded. uid=${userCred.user?.uid}, '
          'isNewUser=${userCred.additionalUserInfo?.isNewUser}');
      return userCred;
    } catch (e, st) {
      final failure = AuthException.from(e);
      debugPrint('[GoogleSignIn +${sw.elapsedMilliseconds}ms] FAILED '
          '(${failure.code}): $e\n$st');
      // Clear the half-finished Google session so the next attempt starts
      // clean — detached, because awaiting a wedged Play Services here would
      // swallow this failure into the very spinner we are trying to kill.
      unawaited(_googleSignIn.signOut().catchError((Object e) {
        debugPrint('[GoogleSignIn] cleanup signOut failed (ignored): $e');
        return null;
      }));
      throw failure;
    }
  }

  // ── Sign out ───────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    // Bounded + best-effort: a wedged Play Services must never trap the user on
    // an authenticated screen. The Firebase sign-out below is the one that
    // actually ends the session.
    await _googleSignIn
        .signOut()
        .timeout(const Duration(seconds: 6))
        .catchError((Object e) {
      debugPrint('[AuthService] signOut: Google sign-out skipped ($e)');
      return null;
    });
    await _auth.signOut();
  }

  /// Permanently deletes the Firebase Auth account, then clears the Google +
  /// Firebase sessions.
  ///
  /// `currentUser.delete()` can fail with `requires-recent-login` when the
  /// credential is stale; in that case the account doc is already gone from
  /// Firestore, so we log and fall through to a normal sign-out rather than
  /// blocking the user. Either way the local session is fully ended.
  Future<void> deleteCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await user.delete();
        debugPrint('[AuthService] deleteCurrentUser: auth account deleted.');
      } on FirebaseAuthException catch (e) {
        debugPrint('[AuthService] deleteCurrentUser: delete failed '
            '(${e.code}); signing out instead.');
      } catch (e) {
        debugPrint('[AuthService] deleteCurrentUser: unexpected error: $e');
      }
    }
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  // ── Helper ──────────────────────────────────────────────────────────────────
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw AuthException.from(e);
    }
  }
}
