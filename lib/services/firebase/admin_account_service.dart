import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_check_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/utils/login_identifier.dart';
import '../../firebase_options.dart';
import '../../models/user_model.dart';
import 'login_directory_service.dart';

/// The login account an admin just provisioned for a member.
class ProvisionedAccount {
  final String uid;

  /// The address the Firebase password credential actually uses — the member's
  /// real e-mail, or the deterministic phone address when they have none.
  final String authEmail;

  /// 10-digit mobile number the member signs in with.
  final String mobile;

  /// Real e-mail address, or '' when the member has none.
  final String email;

  const ProvisionedAccount({
    required this.uid,
    required this.authEmail,
    required this.mobile,
    required this.email,
  });
}

/// Creates a member's LOGIN ACCOUNT on behalf of an admin.
///
/// ## Why a second Firebase app
///
/// `createUserWithEmailAndPassword` signs the *calling* client into the account
/// it just created. Running it on the default app would silently swap the admin
/// out of their own session mid-flow. So the account is provisioned through a
/// SECONDARY [FirebaseApp]: it has its own auth state, the admin's session is
/// never touched, and the temporary instance is torn down afterwards.
///
/// The two documents that only the new member may write — `users/{uid}` and
/// their `login_index` entry — are written through that same secondary
/// instance while it is authenticated AS the new member, so no security rule
/// has to be loosened for the admin. Everything else (profile, contact) is
/// written by the admin under the existing admin rules.
class AdminAccountService {
  final LoginDirectoryService _directory;

  AdminAccountService({LoginDirectoryService? directory})
      : _directory = directory ?? LoginDirectoryService();

  static const String _appName = 'adminMemberProvisioning';

  /// Fails fast when the mobile number already has a login, so the admin sees a
  /// proper error BEFORE anything is created. E-mail duplicates are caught by
  /// Firebase itself (`email-already-in-use`).
  Future<void> assertMobileAvailable(String mobile) async {
    final taken = await _directory.isPhoneRegistered(mobile);
    if (taken) {
      throw const AuthException(
        'This mobile number already has an account.',
        code: 'mobile-already-in-use',
      );
    }
  }

  /// Creates the Firebase Auth credential plus the member's `users/{uid}`
  /// document and mobile → sign-in-address index entry.
  ///
  /// The account is created with `isProfileComplete: true` when [profileCreated]
  /// is set (the admin is creating the full matrimony profile in the same flow),
  /// so the member is NEVER asked to create a profile that already exists.
  Future<ProvisionedAccount> provisionMemberAccount({
    required String name,
    required String mobile,
    required String email,
    required String password,
    String gender = '',
    bool profileCreated = true,
  }) async {
    final localMobile = LoginIdentifier.localMobile(mobile);
    if (localMobile == null) {
      throw const AuthException(
        'Enter a valid 10-digit mobile number.',
        code: 'invalid-mobile',
      );
    }
    final realEmail = email.trim().toLowerCase();
    final authEmail = realEmail.isNotEmpty
        ? realEmail
        : LoginIdentifier.phoneAuthEmail(localMobile);

    await assertMobileAvailable(localMobile);

    // A previous run that crashed before `delete()` would leave the named app
    // behind; reuse it rather than failing with "already exists".
    FirebaseApp app;
    try {
      app = Firebase.app(_appName);
    } catch (_) {
      app = await Firebase.initializeApp(
        name: _appName,
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await AppCheckConfig.activateFor(app);
    }

    try {
      final auth = FirebaseAuth.instanceFor(app: app);
      debugPrint('[AdminAccount] creating login for $localMobile '
          '(realEmail=${realEmail.isNotEmpty})...');
      final UserCredential cred;
      try {
        cred = await auth.createUserWithEmailAndPassword(
            email: authEmail, password: password);
      } catch (e) {
        throw AuthException.from(e);
      }
      final user = cred.user!;
      await user.updateDisplayName(name).catchError((Object e) {
        debugPrint('[AdminAccount] display-name update skipped: $e');
      });

      final db = FirebaseFirestore.instanceFor(app: app);
      final now = DateTime.now();
      final model = UserModel(
        uid: user.uid,
        // Never store the synthesized sign-in address as a contact e-mail.
        email: realEmail.isEmpty ? null : realEmail,
        phone: localMobile,
        displayName: name,
        loginProvider: 'password',
        gender: gender,
        role: 'user',
        // Admin-created members already HAVE a profile — they must never be
        // asked to create one when they first sign in.
        isProfileComplete: profileCreated,
        createdAt: now,
        updatedAt: now,
        lastLoginAt: now,
      );
      await db
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(model.toFirestore());

      // Written from the new member's own session, which is exactly what the
      // login_index rule requires (uid == request.auth.uid).
      await db.collection(LoginDirectoryService.collection).doc(localMobile).set(
        {
          'authEmail': authEmail,
          'uid': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await auth.signOut().catchError((Object e) {
        debugPrint('[AdminAccount] secondary sign-out skipped: $e');
      });
      debugPrint('[AdminAccount] account ready (uid=${user.uid}).');
      return ProvisionedAccount(
        uid: user.uid,
        authEmail: authEmail,
        mobile: localMobile,
        email: realEmail,
      );
    } finally {
      // Always dispose the temporary instance — leaving it alive would keep a
      // second auth listener and Firestore channel open for the whole session.
      try {
        await app.delete();
      } catch (e) {
        debugPrint('[AdminAccount] temporary app cleanup skipped: $e');
      }
    }
  }
}
