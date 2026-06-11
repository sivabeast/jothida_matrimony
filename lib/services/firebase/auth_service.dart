import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/errors/auth_exception.dart';

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
        _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email']);

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
    await _auth.verifyPhoneNumber(
      phoneNumber: '+91$phoneNumber',
      verificationCompleted: onAutoVerified,
      verificationFailed: (e) => onError(AuthException.from(e).message),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 60),
    );
  }

  Future<UserCredential> signInWithOTP(String verificationId, String otp) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    return _guard(() => _auth.signInWithCredential(credential));
  }

  // ── Email / Password ──────────────────────────────────────────────────────
  Future<UserCredential> registerWithEmail(String email, String password) =>
      _guard(() =>
          _auth.createUserWithEmailAndPassword(email: email, password: password));

  Future<UserCredential> signInWithEmail(String email, String password) =>
      _guard(() =>
          _auth.signInWithEmailAndPassword(email: email, password: password));

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  // ── Google ────────────────────────────────────────────────────────────────
  /// Runs the full Google → Firebase credential exchange.
  ///
  /// Returns `null` only when the user dismisses the account picker. Any real
  /// failure is thrown as an [AuthException] with a friendly message.
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // 1. Trigger the native Google account chooser.
      debugPrint('[AuthService] Opening Google account picker...');
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint('[AuthService] User cancelled the Google picker.');
        return null; // user cancelled
      }
      debugPrint('[AuthService] Google account selected: ${googleUser.email}');

      // 2. Obtain the OAuth tokens for the chosen account.
      final googleAuth = await googleUser.authentication;
      debugPrint('[AuthService] Got Google tokens '
          '(idToken=${googleAuth.idToken != null}, '
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
      debugPrint('[AuthService] Exchanging Google credential with Firebase...');
      final userCred = await _auth.signInWithCredential(credential);
      debugPrint('[AuthService] Firebase sign-in succeeded. '
          'uid=${userCred.user?.uid}, '
          'isNewUser=${userCred.additionalUserInfo?.isNewUser}');
      return userCred;
    } catch (e, st) {
      debugPrint('[AuthService] signInWithGoogle failed: $e\n$st');
      // Make sure a half-finished Google session doesn't get stuck.
      await _googleSignIn.signOut().catchError((_) {});
      throw AuthException.from(e);
    }
  }

  // ── Sign out ───────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _googleSignIn.signOut().catchError((_) {});
    await _auth.signOut();
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
