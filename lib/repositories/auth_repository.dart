import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/errors/auth_exception.dart';
import '../core/utils/login_identifier.dart';
import '../models/user_model.dart';
import '../services/firebase/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import '../services/firebase/fcm_service.dart';
import '../services/firebase/login_directory_service.dart';

/// Orchestrates authentication: delegates credential work to [AuthService] and
/// user-document work to [FirestoreService]. The UI/providers only talk to this
/// repository, never to Firebase directly.
class AuthRepository {
  final AuthService _auth;
  final FirestoreService _firestore;
  final FcmService _fcm;
  final LoginDirectoryService _directory;

  AuthRepository(this._auth, this._firestore, this._fcm, this._directory);

  Stream<User?> get authStateChanges => _auth.authStateChanges;
  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUserId;

  /// True when the live session is a GUEST (anonymous) one — browse-only, with
  /// no `users/{uid}` document and no write access anywhere.
  bool get isGuest => _auth.isGuest;

  /// Starts Guest Mode. Deliberately does NOT create a `users/{uid}` document:
  /// a guest stores nothing permanent, and the security rules enforce that
  /// server-side. The account becomes real only when the guest registers or
  /// logs in, at which point it is LINKED in place (same uid).
  Future<void> signInAsGuest() async {
    debugPrint('[AuthRepository] signInAsGuest: starting guest session...');
    final cred = await _auth.signInAnonymously();
    debugPrint('[AuthRepository] signInAsGuest: guest ${cred.user?.uid} ready '
        '(no user document written — guests persist nothing).');
  }

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

  // ── Password login: mobile number OR e-mail (§ two login methods) ─────────

  /// Resolves whatever the member typed into the single "Phone Number or Email"
  /// field to the e-mail address their Firebase password credential uses.
  ///
  ///  • an e-mail → itself, no lookup at all;
  ///  • a mobile number → the `login_index` entry when one exists (member
  ///    registered with a real e-mail), otherwise the deterministic
  ///    [LoginIdentifier.phoneAuthEmail] address that phone-only accounts use.
  ///
  /// Throws [AuthException] when the input is neither.
  Future<String> resolveAuthEmail(String identifier) async {
    final value = identifier.trim();
    switch (LoginIdentifier.kindOf(value)) {
      case LoginIdentifierKind.email:
        return value.toLowerCase();
      case LoginIdentifierKind.phone:
        final mobile = LoginIdentifier.localMobile(value)!;
        final mapped = await _directory.authEmailForPhone(mobile);
        final resolved = mapped ?? LoginIdentifier.phoneAuthEmail(mobile);
        debugPrint('[AuthRepository] resolveAuthEmail: mobile $mobile → '
            '${mapped == null ? 'synthesized' : 'indexed'} address');
        return resolved;
      case LoginIdentifierKind.unknown:
        throw const AuthException(
          'Enter a valid 10-digit mobile number or e-mail address.',
          code: 'invalid-identifier',
        );
    }
  }

  /// Signs in with **mobile number + password** or **e-mail + password** —
  /// the only two password login methods (usernames were removed).
  Future<UserModel> signInWithIdentifier(
      String identifier, String password) async {
    final email = await resolveAuthEmail(identifier);
    debugPrint('[AuthRepository] signInWithIdentifier: starting...');
    final cred = await _auth.signInWithEmail(email, password);
    final model =
        await _onAuthenticated(cred.user!, loginProvider: 'password');
    // Self-healing: an account that has a mobile number but no directory entry
    // (registered before this index existed, or a failed write) gets one now,
    // so the NEXT phone login resolves directly.
    final mobile = LoginIdentifier.localMobile(model.phone ?? '');
    if (mobile != null) {
      unawaited(_directory.registerQuietly(
          mobile: mobile, authEmail: email, uid: model.uid));
    }
    return model;
  }

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
      // Bound the login write: `createOrUpdateUserOnLogin` runs a Firestore
      // transaction + read, both of which require a server round-trip and can
      // hang on a poor/offline connection. A timeout turns an indefinite hang
      // into a real error that resets the UI loading state (instead of an
      // eternal spinner) and shows a retry-able message.
      model = await _firestore
          .createOrUpdateUserOnLogin(user,
              phone: phone, loginProvider: loginProvider)
          .timeout(const Duration(seconds: 25));
    } on TimeoutException catch (e, st) {
      debugPrint('[AuthRepository] _onAuthenticated: Firestore write TIMED OUT '
          '(25s): $e\n$st');
      throw const AuthException(
        'Signed in, but the database did not respond in time. Please check '
        'your internet connection and try again.',
        code: 'firestore-timeout',
      );
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
    // FCM token registration is best-effort and must NEVER block or delay the
    // sign-in. `getToken()` can hang (not throw) on emulators, restricted
    // networks, or devices without Play Services — which previously froze the
    // login spinner here. Fire it off detached and return immediately so the
    // user reaches their screen the moment their account doc is ready.
    unawaited(_registerFcmToken(user.uid));
    return model;
  }

  /// Best-effort push-token registration, intentionally detached from the
  /// sign-in critical path: any slowness or failure here never affects login.
  Future<void> _registerFcmToken(String uid) async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _firestore.updateFcmToken(uid, token);
        debugPrint('[AuthRepository] FCM token registered for $uid.');
      } else {
        debugPrint('[AuthRepository] FCM token unavailable (skipped).');
      }
    } catch (e, st) {
      debugPrint('[AuthRepository] FCM token registration failed '
          '(non-fatal): $e\n$st');
    }
  }

  /// Used by the email/OTP flows to ensure a user document exists.
  Future<UserModel> createUserDocumentAfterAuth(User user,
          {String? phone, String? loginProvider}) =>
      _onAuthenticated(user, phone: phone, loginProvider: loginProvider);

  /// **Account creation** (not profile creation) for matrimony users: creates
  /// the Firebase Auth credential, the `users/{uid}` document, the mobile →
  /// sign-in-address index entry, and stores the registration details.
  ///
  /// [email] is optional. When it is empty the Firebase credential uses the
  /// deterministic phone address ([LoginIdentifier.phoneAuthEmail]), so the
  /// member can still sign in with **mobile number + password**.
  ///
  /// The new account intentionally stays `isProfileComplete: false`: the
  /// matrimony profile is created later, only when the member chooses to.
  Future<UserModel> registerUserWithDetails({
    required String password,
    required String name,
    required String phone,
    required String gender,
    required DateTime dateOfBirth,
    String email = '',
    String location = '',
  }) async {
    final realEmail = email.trim().toLowerCase();
    final mobile = LoginIdentifier.localMobile(phone) ?? phone.trim();
    final authEmail = realEmail.isNotEmpty
        ? realEmail
        : LoginIdentifier.phoneAuthEmail(mobile);
    debugPrint('[AuthRepository] registerUserWithDetails: creating Firebase '
        'account (realEmail=${realEmail.isNotEmpty})...');
    final cred = await _auth.registerWithEmail(authEmail, password);
    final user = cred.user!;
    debugPrint('[AuthRepository] registerUserWithDetails: Firebase user '
        '${user.uid} created. Updating display name...');
    await user.updateDisplayName(name);
    await _onAuthenticated(user, phone: mobile, loginProvider: 'password');
    debugPrint('[AuthRepository] registerUserWithDetails: saving registration '
        'details to Firestore...');
    await _firestore.saveUserRegistrationDetails(
      user.uid,
      name: name,
      phone: mobile,
      gender: gender,
      dateOfBirth: dateOfBirth,
      location: location,
      email: realEmail,
    );
    // Mobile login resolution — best-effort so a blocked/slow index write can
    // never fail an otherwise-successful registration.
    await _directory.registerQuietly(
        mobile: mobile, authEmail: authEmail, uid: user.uid);
    final model = (await _firestore.getUser(user.uid))!;
    debugPrint('[AuthRepository] registerUserWithDetails: done. '
        'isProfileComplete=${model.isProfileComplete}');
    return model;
  }

  Future<UserModel?> getUserModel(String uid) => _firestore.getUser(uid);

  /// Signs out. The device's FCM token is deleted and cleared from
  /// `users/{uid}` FIRST (while the session still satisfies the owner-only
  /// rules) so a shared device stops receiving the previous account's pushes
  /// the moment they log out — best-effort with a hard bound, because a push
  /// hiccup must never block or delay signing out.
  Future<void> signOut() async {
    final uid = _auth.currentUserId;
    if (uid != null) {
      try {
        await _fcm.deleteToken(uid).timeout(const Duration(seconds: 5));
        debugPrint('[AuthRepository] signOut: FCM token cleared for $uid.');
      } catch (e) {
        debugPrint(
            '[AuthRepository] signOut: FCM token cleanup skipped (non-fatal): $e');
      }
    }
    await _auth.signOut();
  }

  // ── Permanent account deletion ─────────────────────────────────────────────
  //
  // The ORDER is owned by `AccountDeletionFlow` (core/utils/
  // account_deletion_flow.dart). These are its individual steps. None of them
  // signs out except [endSessionAfterDeletion], which the flow calls only once
  // the Firebase Auth user is gone.

  /// The providers linked to the signed-in account ('password', 'google.com').
  List<String> get currentProviderIds => _auth.currentProviderIds;

  /// When the signed-in user last authenticated (the ID token's `auth_time`).
  Future<DateTime?> lastSignInTime() => _auth.lastSignInTime();

  /// Re-authenticates the signed-in account with its password. Throws
  /// [AuthException] (e.g. `invalid-credential`, `too-many-requests`).
  Future<void> reauthenticateWithPassword(String password) =>
      _auth.reauthenticateWithPassword(password);

  /// Re-authenticates the signed-in account with Google. False when the member
  /// cancelled the picker; throws [AuthException] (e.g. `user-mismatch`).
  Future<bool> reauthenticateWithGoogle() => _auth.reauthenticateWithGoogle();

  /// Deletes the member's Firestore data while they are still authenticated,
  /// then verifies. Returns the steps that failed and whether a profile or
  /// account document can still be read.
  Future<({List<String> failedSteps, bool residual})> deleteAccountData(
      String uid,
      {required bool isAstrologer}) async {
    debugPrint('[AuthRepository] deleteAccountData($uid, '
        'isAstrologer=$isAstrologer)');
    // Push token first, so a deleted account stops receiving notifications on
    // this device even if a later step fails.
    try {
      await _fcm.deleteToken(uid);
    } catch (e) {
      debugPrint('[AuthRepository] deleteAccountData: FCM token delete '
          'skipped: $e');
    }
    final failedSteps = isAstrologer
        ? await _firestore.deleteAstrologerAccountData(uid)
        : await _firestore.deleteUserAccountData(uid);
    // VERIFY rather than assume — still signed in, so the owner rules that
    // permitted the deletes permit this read too.
    final residual = await _firestore.hasResidualAccountData(uid);
    debugPrint('[AuthRepository] deleteAccountData: residual=$residual, '
        'failed=${failedSteps.isEmpty ? 'none' : failedSteps.join(',')}');
    return (failedSteps: failedSteps, residual: residual);
  }

  /// Permanently deletes the signed-in Firebase Auth user. Does NOT sign out
  /// and does NOT swallow the failure — see [AuthService.deleteAuthUser].
  Future<void> deleteAuthUser() => _auth.deleteAuthUser();

  /// Ends every session after the Auth user has been deleted.
  Future<void> endSessionAfterDeletion() => _auth.endSessionAfterDeletion();
}

/// How an account deletion ended — what the member is told.
enum AccountDeletionOutcome {
  /// The Firebase Auth user was deleted along with the member's data.
  deleted,

  /// No signed-in (non-guest) account — nothing was attempted.
  notSignedIn,

  /// Re-authentication was cancelled or failed — nothing was deleted.
  cancelled,

  /// Re-authentication was required but the account has no method this app
  /// can re-authenticate with — nothing was deleted.
  reauthUnsupported,

  /// Identity data could not be deleted — the Auth user was kept so the member
  /// can retry. Still signed in.
  dataNotDeleted,

  /// The data was deleted but the Firebase Auth user was not. Still signed in;
  /// retrying finishes the deletion.
  loginNotDeleted,
}

/// What actually happened during an account deletion.
///
/// Deliberately not a bare `bool`. "Did it work?" has two independent answers
/// here — the Firebase Auth record and the Firestore data are removed by
/// different mechanisms with different failure modes — and collapsing them into
/// one flag is what let a HALF-deleted account report success (spec §3/§4).
class AccountDeletionResult {
  /// Whether the Firebase Auth user itself was deleted.
  final bool authDeleted;

  /// Names of the Firestore deletion steps that did not complete.
  final List<String> failedSteps;

  /// Whether a post-deletion re-read still finds account data (a profile or the
  /// `users/{uid}` document).
  final bool residualData;

  /// How the deletion ended. Only [AccountDeletionOutcome.deleted] may be
  /// reported to the member as a deleted account.
  final AccountDeletionOutcome? _outcome;

  const AccountDeletionResult({
    required this.authDeleted,
    this.failedSteps = const [],
    this.residualData = false,
    AccountDeletionOutcome? outcome,
  }) : _outcome = outcome;

  /// A deletion that stopped before removing anything.
  const AccountDeletionResult.stopped(AccountDeletionOutcome outcome)
      : authDeleted = false,
        failedSteps = const [],
        residualData = false,
        _outcome = outcome;

  AccountDeletionOutcome get outcome =>
      _outcome ??
      (authDeleted
          ? AccountDeletionOutcome.deleted
          : AccountDeletionOutcome.loginNotDeleted);

  /// True when the account is genuinely, completely gone.
  bool get isComplete => authDeleted && failedSteps.isEmpty && !residualData;

  /// True for the ONE combination that can resurrect a deleted profile: the
  /// auth record survived, so the same uid signs in again, AND data survived
  /// for that uid to find. Either alone is recoverable; together they are the
  /// bug this class exists to make visible.
  bool get mayResurrect => !authDeleted && (residualData || failedSteps.isNotEmpty);
}
