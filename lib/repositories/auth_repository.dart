import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/firebase/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import '../services/firebase/fcm_service.dart';

/// Orchestrates authentication: delegates credential work to [AuthService] and
/// user-document work to [FirestoreService]. The UI/providers only talk to this
/// repository, never to Firebase directly.
class AuthRepository {
  final AuthService _auth;
  final FirestoreService _firestore;
  final FcmService _fcm;

  AuthRepository(this._auth, this._firestore, this._fcm);

  Stream<User?> get authStateChanges => _auth.authStateChanges;
  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUserId;

  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String) onCodeSent,
    required Function(String) onError,
    required Function(PhoneAuthCredential) onAutoVerified,
  }) =>
      _auth.verifyPhone(
        phoneNumber: phoneNumber,
        onCodeSent: onCodeSent,
        onError: onError,
        onAutoVerified: onAutoVerified,
      );

  Future<UserCredential> signInWithOTP(String verificationId, String otp) =>
      _auth.signInWithOTP(verificationId, otp);

  Future<UserCredential> registerWithEmail(String email, String password) =>
      _auth.registerWithEmail(email, password);

  Future<UserCredential> signInWithEmail(String email, String password) =>
      _auth.signInWithEmail(email, password);

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordReset(email);

  /// Full Google sign-in. Returns the resolved [UserModel], or `null` if the
  /// user dismissed the account picker. Throws [AuthException] on real errors.
  ///
  /// [FirestoreService.createOrUpdateUserOnLogin] creates the `users/{uid}`
  /// document on first sign-in only (with `isProfileComplete: false`) and
  /// otherwise just refreshes `lastLoginAt`/`loginProvider`. The UI uses
  /// [UserModel.isProfileComplete] to decide whether to send the user to
  /// onboarding (new / incomplete profile) or straight to their normal
  /// screen (returning user).
  Future<UserModel?> signInWithGoogle() async {
    debugPrint('[AuthRepository] signInWithGoogle: starting...');
    final cred = await _auth.signInWithGoogle();
    if (cred?.user == null) {
      debugPrint('[AuthRepository] signInWithGoogle: cancelled by user.');
      return null;
    }
    debugPrint('[AuthRepository] signInWithGoogle: Firebase user '
        '${cred!.user!.uid}, syncing Firestore...');
    final model = await _onAuthenticated(cred.user!, loginProvider: 'google.com');
    debugPrint('[AuthRepository] signInWithGoogle: done. '
        'isProfileComplete=${model.isProfileComplete}, '
        'isAdmin=${model.isAdmin}, isAstrologer=${model.isAstrologer}');
    return model;
  }

  /// Shared post-auth step for every sign-in path: create-or-update the user
  /// document, register the FCM token, and return the [UserModel].
  Future<UserModel> _onAuthenticated(User user,
      {String? phone, String? loginProvider}) async {
    debugPrint('[AuthRepository] _onAuthenticated: '
        'createOrUpdateUserOnLogin(${user.uid}, loginProvider=$loginProvider)');
    final model = await _firestore.createOrUpdateUserOnLogin(user,
        phone: phone, loginProvider: loginProvider);
    debugPrint('[AuthRepository] _onAuthenticated: Firestore doc ready.');
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _firestore.updateFcmToken(user.uid, token);
        debugPrint('[AuthRepository] _onAuthenticated: FCM token updated.');
      }
    } catch (e, st) {
      // FCM is best-effort — never let a push-notification hiccup block sign-in.
      debugPrint('[AuthRepository] _onAuthenticated: FCM token update '
          'failed (non-fatal): $e\n$st');
    }
    return model;
  }

  /// Used by the email/OTP flows to ensure a user document exists.
  Future<UserModel> createUserDocumentAfterAuth(User user,
          {String? phone, String? loginProvider}) =>
      _onAuthenticated(user, phone: phone, loginProvider: loginProvider);

  /// Email/password signup for matrimony **users**: creates the auth account,
  /// the `users/{uid}` document, and saves the essential registration details
  /// (name, mobile, gender, DOB, location) in one go.
  Future<UserModel> registerUserWithDetails({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String gender,
    required DateTime dateOfBirth,
    required String location,
  }) async {
    final cred = await _auth.registerWithEmail(email, password);
    final user = cred.user!;
    await user.updateDisplayName(name);
    await _onAuthenticated(user, phone: phone, loginProvider: 'password');
    await _firestore.saveUserRegistrationDetails(
      user.uid,
      name: name,
      phone: phone,
      gender: gender,
      dateOfBirth: dateOfBirth,
      location: location,
    );
    return (await _firestore.getUser(user.uid))!;
  }

  Future<UserModel?> getUserModel(String uid) => _firestore.getUser(uid);

  Future<void> signOut() => _auth.signOut();
}
