import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/errors/auth_exception.dart';
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
  }) {
    debugPrint('[AuthRepository] verifyPhone($phoneNumber): starting...');
    return _auth.verifyPhone(
      phoneNumber: phoneNumber,
      onCodeSent: (id) {
        debugPrint('[AuthRepository] verifyPhone: codeSent.');
        onCodeSent(id);
      },
      onError: (e) {
        debugPrint('[AuthRepository] verifyPhone: error: $e');
        onError(e);
      },
      onAutoVerified: onAutoVerified,
    );
  }

  Future<UserCredential> signInWithOTP(String verificationId, String otp) async {
    debugPrint('[AuthRepository] signInWithOTP: starting...');
    final cred = await _auth.signInWithOTP(verificationId, otp);
    debugPrint('[AuthRepository] signInWithOTP: success. uid=${cred.user?.uid}');
    return cred;
  }

  Future<UserCredential> registerWithEmail(String email, String password) async {
    debugPrint('[AuthRepository] registerWithEmail($email): starting...');
    final cred = await _auth.registerWithEmail(email, password);
    debugPrint('[AuthRepository] registerWithEmail: success. uid=${cred.user?.uid}');
    return cred;
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    debugPrint('[AuthRepository] signInWithEmail($email): starting...');
    final cred = await _auth.signInWithEmail(email, password);
    debugPrint('[AuthRepository] signInWithEmail: success. uid=${cred.user?.uid}');
    return cred;
  }

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
    final UserModel model;
    try {
      model = await _firestore.createOrUpdateUserOnLogin(user,
          phone: phone, loginProvider: loginProvider);
    } on FirebaseException catch (e, st) {
      debugPrint('[AuthRepository] _onAuthenticated: Firestore write FAILED: '
          '${e.plugin}/${e.code} — ${e.message}\n$st');
      if (e.code == 'permission-denied') {
        throw AuthException(
          'Signed in, but saving your account to the database was blocked '
          '(permission-denied). The Firestore security rules likely have not '
          'been deployed yet for this Firebase project. Please deploy '
          'firestore.rules and try again.',
          code: 'firestore-permission-denied',
        );
      }
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        throw const AuthException(
          'Signed in, but could not reach the database. Please check your '
          'internet connection and try again.',
          code: 'firestore-unavailable',
        );
      }
      throw AuthException(
        'Signed in, but saving your account failed (${e.code}). '
        'Please verify Cloud Firestore is enabled for this Firebase project.',
        code: 'firestore-${e.code}',
      );
    } catch (e, st) {
      debugPrint('[AuthRepository] _onAuthenticated: unexpected error: $e\n$st');
      throw AuthException('Signed in, but something went wrong while '
          'setting up your account: $e');
    }
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
    debugPrint('[AuthRepository] registerUserWithDetails($email): '
        'creating Firebase account...');
    final cred = await _auth.registerWithEmail(email, password);
    final user = cred.user!;
    debugPrint('[AuthRepository] registerUserWithDetails: Firebase user '
        '${user.uid} created. Updating display name...');
    await user.updateDisplayName(name);
    await _onAuthenticated(user, phone: phone, loginProvider: 'password');
    debugPrint('[AuthRepository] registerUserWithDetails: saving registration '
        'details to Firestore...');
    await _firestore.saveUserRegistrationDetails(
      user.uid,
      name: name,
      phone: phone,
      gender: gender,
      dateOfBirth: dateOfBirth,
      location: location,
    );
    final model = (await _firestore.getUser(user.uid))!;
    debugPrint('[AuthRepository] registerUserWithDetails: done. '
        'isProfileComplete=${model.isProfileComplete}');
    return model;
  }

  Future<UserModel?> getUserModel(String uid) => _firestore.getUser(uid);

  Future<void> signOut() => _auth.signOut();
}
