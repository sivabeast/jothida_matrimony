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
      // Upgrades a Guest Mode session in place rather than creating a second
      // account for the same person.
      final cred = await _signInOrLink(credential);
      debugPrint('[AuthService] signInWithOTP: success. '
          'uid=${cred.user?.uid}, isNewUser=${cred.additionalUserInfo?.isNewUser}');
      return cred;
    });
  }

  // ── Password recovery by OTP ────────────────────────────────────────────

  /// Sends (or RE-sends, with [forceResendingToken]) the recovery OTP.
  ///
  /// Kept apart from [verifyPhone] because recovery must never touch the
  /// current session's identity: the code is only verified later by
  /// [signInForRecovery], and nothing here links or signs in.
  Future<void> sendRecoveryOtp({
    required String mobile,
    int? forceResendingToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(AuthException error) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerified,
  }) async {
    debugPrint('[AuthService] sendRecoveryOtp: +91$mobile '
        '(resend=${forceResendingToken != null})');
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: '+91$mobile',
        forceResendingToken: forceResendingToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) => onAutoVerified?.call(credential),
        verificationFailed: (e) {
          debugPrint('[AuthService] sendRecoveryOtp failed: ${e.code} '
              '${e.message}');
          onError(AuthException.from(e));
        },
        codeSent: onCodeSent,
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      onError(AuthException.from(e));
    }
  }

  /// Verifies the recovery OTP by signing in to the PHONE identity directly —
  /// never linking it to a guest session, which would turn a throwaway
  /// verification into a permanent identity. Returns the phone identity and
  /// whether Firebase just created it.
  Future<({User user, bool isNew})> signInForRecovery({
    String? verificationId,
    String? smsCode,
    PhoneAuthCredential? credential,
  }) {
    return _guard(() async {
      final cred = credential ??
          PhoneAuthProvider.credential(
              verificationId: verificationId!, smsCode: smsCode!);
      final result = await _auth
          .signInWithCredential(cred)
          .timeout(_credentialTimeout);
      return (
        user: result.user!,
        isNew: result.additionalUserInfo?.isNewUser ?? false,
      );
    });
  }

  /// Changes the signed-in account's password after re-authenticating with
  /// the current one. Firebase ends the account's other sessions itself when
  /// the password changes.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await reauthenticateWithPassword(currentPassword);
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.',
          code: 'no-current-user');
    }
    try {
      await user.updatePassword(newPassword).timeout(_credentialTimeout);
      debugPrint('[AuthService] changePassword: ok (${user.uid}).');
    } on TimeoutException {
      throw const AuthException(
          'No internet connection. Please check your network and try again.',
          code: 'network-request-failed');
    } catch (e) {
      throw AuthException.from(e);
    }
  }

  // ── Email / Password ──────────────────────────────────────────────────────
  /// Creates an e-mail/password account. Delegates to
  /// [registerOrLinkWithEmail] so a Guest Mode session is upgraded in place
  /// instead of leaving the visitor with two accounts.
  Future<UserCredential> registerWithEmail(String email, String password) async {
    debugPrint('[AuthService] registerWithEmail: creating account for $email');
    final cred = await registerOrLinkWithEmail(email, password);
    debugPrint('[AuthService] registerWithEmail: success. uid=${cred.user?.uid}');
    return cred;
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

  // ── Guest Mode (anonymous) + account linking ──────────────────────────────

  /// Error codes meaning "this credential already belongs to a real account".
  static const _kAlreadyRegistered = {
    'credential-already-in-use',
    'email-already-in-use',
    'account-exists-with-different-credential',
    'provider-already-linked',
  };

  /// True when the live session is a GUEST (anonymous) one.
  bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

  /// Starts a guest session.
  ///
  /// Anonymous auth exists for exactly one purpose in this app: letting a
  /// visitor explore before registering. It is NEVER a data-storage identity —
  /// the Firestore and Storage rules reject every write whose sign-in provider
  /// is 'anonymous', so a guest physically cannot create a profile, a booking,
  /// an interest or any other permanent record.
  Future<UserCredential> signInAnonymously() {
    debugPrint('[AuthService] signInAnonymously: starting a guest session...');
    return _guard(() async {
      final cred = await _auth.signInAnonymously();
      debugPrint('[AuthService] signInAnonymously: guest uid=${cred.user?.uid}');
      return cred;
    });
  }

  /// Signs in with [credential], UPGRADING the current guest session in place
  /// when there is one — so a visitor who explores first and registers second
  /// keeps the SAME uid instead of collecting a second account.
  ///
  /// When the credential already belongs to a real account, the "guest" is just
  /// a returning member who tapped Continue as Guest first. There is nothing to
  /// migrate — Guest Mode never writes permanent data, and the security rules
  /// guarantee that — so the throwaway anonymous account is abandoned and they
  /// are signed into their real one. Without this fallback, tapping Continue as
  /// Guest would permanently lock a returning member out of their own account.
  Future<UserCredential> _signInOrLink(AuthCredential credential) async {
    final guest = _auth.currentUser;
    if (guest != null && guest.isAnonymous) {
      try {
        final linked = await guest.linkWithCredential(credential);
        debugPrint('[AuthService] _signInOrLink: guest ${guest.uid} upgraded '
            'in place — no duplicate account created.');
        return linked;
      } on FirebaseAuthException catch (e) {
        if (!_kAlreadyRegistered.contains(e.code)) rethrow;
        debugPrint('[AuthService] _signInOrLink: credential already belongs to '
            'an account (${e.code}) — discarding the guest session and signing '
            'into the existing account instead.');
      }
    }
    return _auth.signInWithCredential(credential);
  }

  /// Public, error-mapped form of [_signInOrLink].
  Future<UserCredential> signInOrLink(AuthCredential credential) =>
      _guard(() => _signInOrLink(credential));

  /// Creates an e-mail/password account, upgrading a guest session in place
  /// when there is one. Same duplicate-account guarantee as [_signInOrLink].
  Future<UserCredential> registerOrLinkWithEmail(String email, String password) {
    debugPrint('[AuthService] registerOrLinkWithEmail: $email '
        '(guest upgrade=${isGuest})');
    return _guard(() async {
      final guest = _auth.currentUser;
      if (guest != null && guest.isAnonymous) {
        try {
          final linked = await guest.linkWithCredential(
              EmailAuthProvider.credential(email: email, password: password));
          debugPrint('[AuthService] registerOrLinkWithEmail: guest '
              '${guest.uid} upgraded in place.');
          return linked;
        } on FirebaseAuthException catch (e) {
          if (!_kAlreadyRegistered.contains(e.code)) rethrow;
          debugPrint('[AuthService] registerOrLinkWithEmail: address already '
              'registered (${e.code}) — creating normally.');
        }
      }
      return _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    });
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
      // Upgrades a Guest Mode session in place (same uid, no duplicate).
      final userCred = await _signInOrLink(credential).timeout(
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

  // ── Permanent account deletion ─────────────────────────────────────────────
  //
  // The previous `deleteCurrentUser()` re-authenticated through GOOGLE ONLY and
  // then signed out UNCONDITIONALLY. For an e-mail / mobile + password account
  // Firebase's `requires-recent-login` could never be satisfied, the Auth
  // account survived, and the member was logged out anyway — so their old
  // credentials still worked. These methods each do exactly one thing, report
  // the real Firebase error, and never sign out; `AccountDeletionFlow` decides
  // the order.

  /// The provider ids linked to the signed-in account.
  List<String> get currentProviderIds => [
        for (final p in _auth.currentUser?.providerData ?? const <UserInfo>[])
          p.providerId,
      ];

  /// When the signed-in user last authenticated — the ID token's `auth_time`,
  /// which is exactly what Firebase checks for `requires-recent-login`. Null
  /// when it cannot be read (then re-authentication is asked for).
  Future<DateTime?> lastSignInTime() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final token = await user.getIdTokenResult().timeout(_tokenTimeout);
      return token.authTime;
    } catch (e) {
      debugPrint('[AuthService] lastSignInTime unavailable: $e');
      return null;
    }
  }

  /// Re-authenticates the signed-in user with their PASSWORD. The e-mail is
  /// always the account's own sign-in address (for a mobile-number account the
  /// synthesized address), never something the member types.
  ///
  /// Throws [AuthException] with Firebase's code (`invalid-credential`,
  /// `too-many-requests`, `network-request-failed`, `user-mismatch`…). Never
  /// creates a user and never signs out.
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    final email = user?.email?.trim() ?? '';
    if (user == null || email.isEmpty) {
      throw const AuthException('You are not signed in with a password.',
          code: 'no-password-account');
    }
    try {
      await user
          .reauthenticateWithCredential(
              EmailAuthProvider.credential(email: email, password: password))
          .timeout(_credentialTimeout);
      debugPrint('[AuthService] reauthenticateWithPassword: ok (${user.uid}).');
    } on TimeoutException {
      throw const AuthException(
          'No internet connection. Please check your network and try again.',
          code: 'network-request-failed');
    } catch (e) {
      debugPrint('[AuthService] reauthenticateWithPassword FAILED: $e');
      throw AuthException.from(e);
    }
  }

  /// Re-authenticates the signed-in user with GOOGLE. Returns false when the
  /// member dismissed the account picker. Throws [AuthException] when Firebase
  /// refuses (e.g. `user-mismatch` — a different Google account was chosen).
  Future<bool> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.',
          code: 'no-current-user');
    }
    try {
      final wanted = (user.email ?? '').toLowerCase();
      GoogleSignInAccount? account;
      try {
        account = await _googleSignIn
            .signInSilently()
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        account = null;
      }
      if (account == null || account.email.toLowerCase() != wanted) {
        // A different (or no) cached Google account: clear it so the picker
        // really opens, then let the member choose.
        await _googleSignIn
            .signOut()
            .timeout(const Duration(seconds: 6))
            .catchError((Object _) => null);
        account = await _googleSignIn.signIn().timeout(_pickerTimeout);
      }
      if (account == null) {
        debugPrint('[AuthService] reauthenticateWithGoogle: cancelled.');
        return false;
      }
      final auth = await account.authentication.timeout(_tokenTimeout);
      await user
          .reauthenticateWithCredential(GoogleAuthProvider.credential(
            accessToken: auth.accessToken,
            idToken: auth.idToken,
          ))
          .timeout(_credentialTimeout);
      debugPrint('[AuthService] reauthenticateWithGoogle: ok (${user.uid}).');
      return true;
    } catch (e) {
      final failure = AuthException.from(e);
      if (failure.cancelled) return false;
      debugPrint('[AuthService] reauthenticateWithGoogle FAILED: $e');
      throw failure;
    }
  }

  /// PERMANENTLY deletes the signed-in Firebase Auth user.
  ///
  /// Does NOT sign out and does NOT hide the failure: the Firebase error code is
  /// logged and rethrown ([AuthException.code] keeps `requires-recent-login`,
  /// `network-request-failed`, …) so the caller can re-authenticate or retry.
  Future<void> deleteAuthUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.',
          code: 'no-current-user');
    }
    final uid = user.uid;
    try {
      await user.delete().timeout(_credentialTimeout);
      debugPrint('[AuthService] deleteAuthUser: Firebase Auth user $uid '
          'PERMANENTLY deleted.');
    } on TimeoutException {
      debugPrint('[AuthService] deleteAuthUser: timed out for $uid.');
      throw const AuthException(
          'No internet connection. Please check your network and try again.',
          code: 'network-request-failed');
    } on FirebaseAuthException catch (e, st) {
      debugPrint('[AuthService] deleteAuthUser FAILED for $uid: '
          '${e.code} — ${e.message}\n$st');
      // Keep the raw code — `AuthException.from` would fold several codes
      // together, and the caller branches on `requires-recent-login`.
      throw AuthException(e.message ?? 'Could not delete the account.',
          code: e.code);
    }
  }

  /// Ends every session once the Auth user has been deleted.
  ///
  /// `disconnect()` revokes this app's Google grant, so the next sign-in shows
  /// the account chooser rather than silently handing back the same Google
  /// account. Bounded and best-effort: there is no account left to protect.
  Future<void> endSessionAfterDeletion() async {
    var googleSession = false;
    try {
      googleSession =
          await _googleSignIn.isSignedIn().timeout(const Duration(seconds: 3));
    } catch (_) {}
    if (googleSession) {
      try {
        await _googleSignIn.disconnect().timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('[AuthService] endSessionAfterDeletion: Google disconnect '
            'skipped ($e)');
      }
      try {
        await _googleSignIn.signOut().timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
    try {
      // Normally already signed out by the delete itself; harmless if so.
      await _auth.signOut();
    } catch (e) {
      debugPrint('[AuthService] endSessionAfterDeletion: signOut failed: $e');
    }
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
