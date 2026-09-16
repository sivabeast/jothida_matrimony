import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_check_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/utils/firestore_write.dart';
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
    final bool taken;
    try {
      taken = await _directory.isPhoneRegistered(mobile);
    } catch (e) {
      // The check is a DUPLICATE guard, so a failed lookup must not be treated
      // as "the number is free" — that is how two accounts end up on one
      // number. Stop, and say which step could not be completed instead of
      // letting a raw FirebaseException reach the admin as "a Firebase error".
      debugPrint('[AdminAccount] mobile availability check failed: $e');
      throw const AuthException(
        'Could not check whether this mobile number is already registered. '
        'Check your connection and try again.',
        code: 'mobile-check-failed',
      );
    }
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
      debugPrint('[AdminAccount] reusing the existing "$_appName" instance.');
    } catch (_) {
      app = await Firebase.initializeApp(
        name: _appName,
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    // ROOT CAUSE of "a Firebase error appears when the admin submits":
    // App Check was only activated on the freshly-initialised branch above. A
    // secondary FirebaseApp carries NO App Check token of its own, and with
    // enforcement ON, Identity Toolkit rejects the very first
    // `createUserWithEmailAndPassword` with an opaque internal error. Any run
    // that REUSED a left-over instance therefore had no provider installed and
    // failed — which is also why it looked intermittent rather than broken.
    //
    // Activation is idempotent, best-effort and bounded, so calling it on both
    // paths costs nothing and closes the hole.
    await AppCheckConfig.activateFor(app);

    final auth = FirebaseAuth.instanceFor(app: app);
    final db = FirebaseFirestore.instanceFor(app: app);
    User? created;
    try {
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
      created = user;
      await user.updateDisplayName(name).catchError((Object e) {
        debugPrint('[AdminAccount] display-name update skipped: $e');
      });

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
      // BOUNDED writes. With offline persistence the Future stays pending
      // until the SERVER acknowledges, so on a flaky connection Submit used to
      // spin indefinitely with nothing on screen to explain it. `commitWrite`
      // treats a locally-committed-but-unacknowledged write as success
      // (Firestore syncs it) and still rethrows a genuine permission-denied.
      await commitWrite(db
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(model.toFirestore()));

      // Written from the new member's own session, which is exactly what the
      // login_index rule requires (uid == request.auth.uid).
      await commitWrite(db
          .collection(LoginDirectoryService.collection)
          .doc(localMobile)
          .set(
        {
          'authEmail': authEmail,
          'uid': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ));

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
    } catch (e) {
      // ROLL BACK a half-created account (spec §21). If the credential was
      // created but its `users/{uid}` document was not, the member would own a
      // Firebase Auth login the app cannot resolve, nobody can clean up from a
      // client, and the admin cannot even retry — the mobile / e-mail is now
      // "already in use". We are still signed in AS that user on this secondary
      // instance, so deleting it is permitted and needs no privileged
      // credentials (spec §32).
      if (created != null) {
        try {
          await created.delete();
          debugPrint('[AdminAccount] rolled back the orphaned auth account.');
        } catch (rollbackError) {
          debugPrint('[AdminAccount] could not roll back the auth account '
              '(${created.uid}): $rollbackError');
        }
      }
      // Name the step that actually failed rather than surfacing a bare
      // FirebaseException — "a Firebase error" tells the admin nothing about
      // what to do next.
      if (e is AuthException) rethrow;
      debugPrint('[AdminAccount] member provisioning FAILED: $e');
      throw AuthException(
        'Could not save the new member account: $e',
        code: 'member-provisioning-failed',
      );
    } finally {
      // Always dispose the temporary instance — leaving it alive would keep a
      // second auth listener and Firestore channel open for the whole session,
      // AND send the next run down the reuse path above.
      //
      // Firestore has to be TERMINATED first: deleting a FirebaseApp whose
      // Firestore client is still running throws, which is exactly how a stale
      // instance survived to break the following run.
      try {
        await db.terminate();
      } catch (e) {
        debugPrint('[AdminAccount] secondary Firestore terminate skipped: $e');
      }
      try {
        await app.delete();
      } catch (e) {
        debugPrint('[AdminAccount] temporary app cleanup skipped: $e');
      }
    }
  }
}
