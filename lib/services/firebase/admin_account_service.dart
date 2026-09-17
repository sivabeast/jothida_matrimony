import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_check_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/utils/account_identity.dart';
import '../../core/utils/login_identifier.dart';
import '../../core/utils/profile_save_error.dart';
import '../../firebase_options.dart';
import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import 'account_admin_backend.dart';
import 'firestore_service.dart';
import 'login_directory_service.dart';

/// The login account an admin just provisioned (or restored) for a member.
class ProvisionedAccount {
  final String uid;

  /// The address the Firebase password credential actually uses — the member's
  /// real e-mail, or the deterministic phone address when they have none.
  final String authEmail;

  /// 10-digit mobile number the member signs in with.
  final String mobile;

  /// Real e-mail address, or '' when the member has none.
  final String email;

  /// True when an EXISTING account (same UID) got its login back instead of a
  /// new account being created — its profile and data are already linked.
  final bool restored;

  const ProvisionedAccount({
    required this.uid,
    required this.authEmail,
    required this.mobile,
    required this.email,
    this.restored = false,
  });
}

/// Why a login could not simply be created — each needs a different decision
/// from the admin, and none of them is "the account already exists, give up".
enum LoginConflictKind {
  /// A live account already owns the mobile number (or several do).
  phoneInUse,

  /// Only a deleted account's registry entry holds the number.
  staleIndex,

  /// The sign-in address belongs to another live account.
  emailInUse,

  /// A Firebase Auth record with that address still exists but nothing in the
  /// app uses it. The backend can replace it; without the backend the app
  /// cannot even see whose it is.
  authRecordStillExists,
}

class LoginConflictException implements Exception {
  final LoginConflictKind kind;
  final String message;
  final LoginInspection? inspection;

  /// The account the conflict is about, when known.
  final ExistingLogin? account;

  const LoginConflictException(this.kind, this.message,
      {this.inspection, this.account});

  @override
  String toString() => message;
}

/// Everything found for a mobile number.
class LoginInspection {
  final String mobile;
  final LoginIndexEntry? index;
  final List<ExistingLogin> accounts;

  /// True when Firebase Auth itself was checked (the backend is deployed).
  final bool authChecked;

  const LoginInspection({
    required this.mobile,
    required this.index,
    required this.accounts,
    required this.authChecked,
  });

  LoginAvailability get availability => decideLoginAvailability(
      index: index, accounts: accounts, authChecked: authChecked);

  List<ExistingLogin> get liveAccounts =>
      [for (final a in accounts) if (a.isLive) a];

  ExistingLogin? get orphanAuth {
    for (final a in accounts) {
      if (a.authExists == true && !a.hasAccountRecord && a.profileCount == 0) {
        return a;
      }
    }
    return null;
  }
}

/// Result of an admin removing a login or a whole account.
class LoginRemovalResult {
  /// Firestore steps that did not complete (Delete User only).
  final List<String> failedSteps;

  /// true = the Firebase Auth record is gone; false = it was already gone;
  /// null = the backend is not deployed, so the record could not be deleted
  /// from the app — the tombstone stops it at its next sign-in instead.
  final bool? authDeleted;

  const LoginRemovalResult({this.failedSteps = const [], this.authDeleted});

  bool get backendUnavailable => authDeleted == null;
}

/// Everything an ADMIN does to a member's LOGIN: inspect, create, restore,
/// delete, reset — plus the Account Health scan.
///
/// ## Two layers
///
/// The trusted backend (`functions/accounts.js`, Blaze plan) is always tried
/// first: it sees and changes Firebase Authentication itself, and it enforces
/// admin permission server-side. When it is not deployed, the service falls
/// back to what the app can do safely on its own — never to anything that
/// would need the Admin SDK's credentials in the app:
///
///  * a new login is created on a SECONDARY Firebase app (the admin's own
///    session is never swapped out) and its account record and phone claim
///    are written from that new member's session;
///  * a deleted login cannot be removed from Firebase Auth, so it is
///    TOMBSTONED — it deletes itself the next time anyone signs in with it;
///  * Firebase Auth cannot be listed, so Account Health checks Firestore only
///    and says so.
class AdminAccountService {
  final LoginDirectoryService _directory;
  final FirestoreService _firestore;
  final AccountAdminBackend _backend;

  AdminAccountService({
    LoginDirectoryService? directory,
    FirestoreService? firestore,
    AccountAdminBackend? backend,
  })  : _directory = directory ?? LoginDirectoryService(),
        _firestore = firestore ?? FirestoreService(),
        _backend = backend ?? AccountAdminBackend();

  static const String _appName = 'adminMemberProvisioning';

  // ── Inspect ────────────────────────────────────────────────────────────────

  /// What already holds [mobile] (and [email], when given).
  Future<LoginInspection> inspectMobile(String mobile,
      {String email = ''}) async {
    final local = LoginIdentifier.localMobile(mobile);
    if (local == null) {
      throw const AuthException('Enter a valid 10-digit mobile number.',
          code: 'invalid-mobile');
    }
    try {
      final r = await _backend.inspectLogin(mobile: local, email: email);
      return LoginInspection(
        mobile: local,
        index: r.index,
        accounts: [for (final a in r.accounts) _fromBackend(a)],
        authChecked: true,
      );
    } on AccountBackendException catch (e) {
      if (!e.isUnavailable) throw AuthException(e.message, code: e.code);
    }
    return _inspectWithoutBackend(local);
  }

  /// Everything the app can see for [uid] (User Details → Login & Access).
  Future<LoginInspection> inspectMember(String uid, {String mobile = ''}) async {
    try {
      final r = await _backend.inspectLogin(
          uid: uid, mobile: LoginIdentifier.localMobile(mobile) ?? '');
      return LoginInspection(
        mobile: LoginIdentifier.localMobile(mobile) ?? '',
        index: r.index,
        accounts: [for (final a in r.accounts) _fromBackend(a)],
        authChecked: true,
      );
    } on AccountBackendException catch (e) {
      if (!e.isUnavailable) throw AuthException(e.message, code: e.code);
    }
    final entries = await _directory.entriesForUid(uid);
    final account = await _describe(uid);
    return LoginInspection(
      mobile: entries.isEmpty ? '' : entries.first.mobile,
      index: entries.isEmpty ? null : entries.first,
      accounts: [account],
      authChecked: false,
    );
  }

  Future<LoginInspection> _inspectWithoutBackend(String mobile) async {
    final index = await _directory.lookup(mobile);
    final uids = <String>{
      if (index != null && index.uid.isNotEmpty) index.uid,
      for (final u in await _firestore.usersWithPhone(mobile)) u.uid,
    };
    return LoginInspection(
      mobile: mobile,
      index: index,
      accounts: [for (final uid in uids) await _describe(uid)],
      authChecked: false,
    );
  }

  Future<ExistingLogin> _describe(String uid) async {
    final UserModel? user = await _firestore.getUserFromServer(uid);
    String tombstone = '';
    try {
      tombstone = (await _firestore.readLoginTombstone(uid)).tombstone?.mode ?? '';
    } catch (e) {
      debugPrint('[AdminAccount] tombstone read for $uid skipped: $e');
    }
    final List<ProfileModel> profiles = await _firestore.profilesOfUser(uid);
    final newest = profiles.isEmpty ? null : profiles.first;
    return ExistingLogin(
      uid: uid,
      displayName: user?.displayName ?? '',
      mobile: LoginIdentifier.localMobile(user?.phone ?? '') ?? '',
      email: LoginIdentifier.realEmailOrEmpty(user?.email),
      role: user?.role ?? '',
      hasAccountRecord: user != null,
      access: user?.loginAccess ?? LoginAccessState.active,
      tombstoneMode: tombstone,
      profileCount: profiles.length,
      profileId: newest?.id ?? '',
      profileName: newest?.fullName ?? '',
      profileStatus: newest?.status ?? '',
    );
  }

  static ExistingLogin _fromBackend(BackendAccount a) => ExistingLogin(
        uid: a.uid,
        displayName: a.displayName,
        mobile: LoginIdentifier.localMobile(a.phone) ?? '',
        email: LoginIdentifier.realEmailOrEmpty(a.email),
        role: a.role,
        hasAccountRecord: a.hasUserDoc,
        authExists: a.auth != null,
        authEmail: a.auth?.email ?? '',
        providers: a.auth?.providers ?? const [],
        access: a.access,
        tombstoneMode: a.tombstoneMode,
        profileCount: a.profileCount,
        profileId: a.profileId,
        profileName: a.profileName,
        profileStatus: a.profileStatus,
      );

  // ── Create / restore ──────────────────────────────────────────────────────

  /// Kept for callers that only need the duplicate guard.
  Future<void> assertMobileAvailable(String mobile) async {
    final LoginInspection inspection;
    try {
      inspection = await inspectMobile(mobile);
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('[AdminAccount] mobile availability check failed: $e');
      throw const AuthException(
        'Could not check whether this mobile number is already registered. '
        'Check your connection and try again.',
        code: 'mobile-check-failed',
      );
    }
    assertAvailable(inspection, releaseStaleIndex: false, replaceOrphanUid: '');
  }

  /// Throws the [LoginConflictException] that [inspection] amounts to, or
  /// returns when a new login may be created (after the admin's confirmations
  /// [releaseStaleIndex] / [replaceOrphanUid]).
  void assertAvailable(LoginInspection inspection,
      {bool releaseStaleIndex = false, String replaceOrphanUid = ''}) {
    switch (inspection.availability) {
      case LoginAvailability.available:
        return;
      case LoginAvailability.inUse:
        final holder = inspection.liveAccounts.first;
        throw LoginConflictException(
          LoginConflictKind.phoneInUse,
          'This mobile number already belongs to '
          '${holder.name.isEmpty ? 'another account' : holder.name}.',
          inspection: inspection,
          account: holder,
        );
      case LoginAvailability.multiple:
        throw LoginConflictException(
          LoginConflictKind.phoneInUse,
          'More than one account uses this mobile number. Resolve it in '
          'Account Health before creating another login.',
          inspection: inspection,
        );
      case LoginAvailability.staleIndex:
        if (releaseStaleIndex) return;
        throw LoginConflictException(
          LoginConflictKind.staleIndex,
          'This number is still registered to a login that was deleted.',
          inspection: inspection,
        );
      case LoginAvailability.orphanAuth:
        final orphan = inspection.orphanAuth;
        if (orphan != null && orphan.uid == replaceOrphanUid) return;
        throw LoginConflictException(
          LoginConflictKind.authRecordStillExists,
          'An old Firebase login with this number still exists, and nothing '
          'in the app uses it.',
          inspection: inspection,
          account: orphan,
        );
    }
  }

  /// Creates the member's login — or, with [targetUid], restores the login of
  /// an EXISTING member under the same UID so their profile and data stay
  /// linked.
  ///
  /// Throws [LoginConflictException] instead of creating a duplicate when
  /// anything already holds the number. The admin resolves it and calls again
  /// with [releaseStaleIndex] / [replaceOrphanUid] after confirming.
  ///
  /// [profileCreated]: the admin is creating the full profile in the same flow,
  /// so the member is never asked to create one at first sign-in.
  Future<ProvisionedAccount> provisionMemberAccount({
    required String name,
    required String mobile,
    required String email,
    required String password,
    String gender = '',
    bool profileCreated = true,
    String targetUid = '',
    bool releaseStaleIndex = false,
    String replaceOrphanUid = '',
  }) async {
    final localMobile = LoginIdentifier.localMobile(mobile);
    if (localMobile == null) {
      throw const AuthException('Enter a valid 10-digit mobile number.',
          code: 'invalid-mobile');
    }
    final realEmail = email.trim().toLowerCase();

    // 1. The trusted backend: sees Firebase Auth, re-keys or restores logins.
    try {
      final r = await _backend.provisionLogin(
        mobile: localMobile,
        email: realEmail,
        password: password,
        displayName: name,
        gender: gender,
        targetUid: targetUid,
        replaceOrphanUid: replaceOrphanUid,
        profileCreated: profileCreated,
      );
      return ProvisionedAccount(
        uid: '${r['uid']}',
        authEmail: '${r['authEmail']}',
        mobile: localMobile,
        email: realEmail,
        restored: r['restored'] == true,
      );
    } on AccountBackendException catch (e) {
      if (!e.isUnavailable) throw _conflictFromBackend(e, localMobile);
      debugPrint('[AdminAccount] backend unavailable — provisioning on the '
          'client.');
    }

    // 2. Without the backend.
    if (targetUid.isNotEmpty) {
      throw const AuthException(
        'Restoring a login under the same account needs the account backend '
        '(Cloud Functions, Blaze plan). Use "Restore Login" for a login that '
        'was disabled, or deploy the backend.',
        code: 'backend-required',
      );
    }
    final LoginInspection inspection;
    try {
      inspection = await inspectMobile(localMobile, email: realEmail);
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('[AdminAccount] mobile availability check failed: $e');
      throw const AuthException(
        'Could not check whether this mobile number is already registered. '
        'Check your connection and try again.',
        code: 'mobile-check-failed',
      );
    }
    assertAvailable(inspection,
        releaseStaleIndex: releaseStaleIndex, replaceOrphanUid: '');
    if (inspection.availability == LoginAvailability.staleIndex) {
      await _directory.release(localMobile);
    }

    return _createOnSecondaryApp(
      name: name,
      mobile: localMobile,
      realEmail: realEmail,
      password: password,
      gender: gender,
      profileCreated: profileCreated,
    );
  }

  Object _conflictFromBackend(AccountBackendException e, String mobile) {
    final account = e.account == null ? null : _fromBackend(e.account!);
    switch (e.reason) {
      case 'phone-number-already-exists':
        return LoginConflictException(LoginConflictKind.phoneInUse, e.message,
            account: account);
      case 'email-already-in-use':
        return LoginConflictException(LoginConflictKind.emailInUse, e.message,
            account: account);
      case 'orphan-auth-account':
        return LoginConflictException(
            LoginConflictKind.authRecordStillExists, e.message,
            account: account);
    }
    return AuthException(e.message, code: e.reason.isEmpty ? e.code : e.reason);
  }

  Future<T> _withSecondaryApp<T>(
      Future<T> Function(FirebaseAuth auth, FirebaseFirestore db) run) async {
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
    // A secondary FirebaseApp carries NO App Check token of its own; with
    // enforcement ON, Identity Toolkit rejects the first call without this —
    // on BOTH the fresh and the reused path. Idempotent and bounded.
    await AppCheckConfig.activateFor(app);
    final auth = FirebaseAuth.instanceFor(app: app);
    final db = FirebaseFirestore.instanceFor(app: app);
    try {
      return await run(auth, db);
    } finally {
      await auth.signOut().catchError((Object e) {
        debugPrint('[AdminAccount] secondary sign-out skipped: $e');
      });
      // Firestore has to be TERMINATED first: deleting a FirebaseApp whose
      // Firestore client is still running throws, which is how a stale
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

  /// A write that must reach the SERVER before the admin is told it worked.
  ///
  /// `commitWrite` treats a slow acknowledgement as "queued offline", which is
  /// right for a member's own edits but wrong here: the temporary Firestore
  /// client is terminated right after, and a queued write would be lost with
  /// it while the admin sees "profile created".
  static Future<void> _serverWrite(Future<void> write) =>
      write.timeout(const Duration(seconds: 25), onTimeout: () {
        throw const AuthException(
          'The server did not confirm the new login in time. Nothing was '
          'saved — check the connection and try again.',
          code: 'member-provisioning-timeout',
        );
      });

  Future<ProvisionedAccount> _createOnSecondaryApp({
    required String name,
    required String mobile,
    required String realEmail,
    required String password,
    required String gender,
    required bool profileCreated,
  }) {
    final authEmail =
        realEmail.isNotEmpty ? realEmail : LoginIdentifier.phoneAuthEmail(mobile);
    return _withSecondaryApp((auth, db) async {
      User? created;
      try {
        debugPrint('[AdminAccount] creating login for $mobile '
            '(realEmail=${realEmail.isNotEmpty})...');
        final UserCredential cred;
        try {
          cred = await auth.createUserWithEmailAndPassword(
              email: authEmail, password: password);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            // The app cannot look inside Firebase Auth. Say exactly that
            // instead of "an account already exists".
            throw LoginConflictException(
              LoginConflictKind.authRecordStillExists,
              realEmail.isNotEmpty
                  ? 'A Firebase login with $realEmail already exists, but no '
                      'account in the app uses this mobile number.'
                  : 'An old Firebase login for this mobile number still exists '
                      '(its account was deleted in the app).',
            );
          }
          throw AuthException.from(e);
        }
        final user = cred.user!;
        created = user;
        await user.updateDisplayName(name).catchError((Object e) {
          debugPrint('[AdminAccount] display-name update skipped: $e');
        });

        // The phone number FIRST, atomically: if another account took it in
        // the meantime, nothing else is written and the login is rolled back.
        final owner = await LoginDirectoryService(db: db)
            .claim(mobile: mobile, authEmail: authEmail, uid: user.uid);
        if (owner.uid != user.uid) {
          throw const LoginConflictException(
            LoginConflictKind.phoneInUse,
            'This mobile number was registered by another account a moment '
            'ago.',
          );
        }

        final now = DateTime.now();
        final model = UserModel(
          uid: user.uid,
          // Never store the synthesized sign-in address as a contact e-mail.
          email: realEmail.isEmpty ? null : realEmail,
          phone: mobile,
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
        await _serverWrite(db
            .collection(AppConstants.usersCollection)
            .doc(user.uid)
            .set(model.toFirestore()));
        debugPrint('[AdminAccount] account ready (uid=${user.uid}).');
        return ProvisionedAccount(
          uid: user.uid,
          authEmail: authEmail,
          mobile: mobile,
          email: realEmail,
        );
      } catch (e) {
        // ROLL BACK a half-created login. We are still signed in AS that user
        // on this secondary instance, so deleting it needs no privileges —
        // and it frees the mobile number / address for the admin's retry.
        if (created != null) {
          try {
            await db
                .collection(LoginDirectoryService.collection)
                .doc(mobile)
                .get()
                .then((s) async {
              if (s.data()?['uid'] == created!.uid) await s.reference.delete();
            });
          } catch (_) {}
          try {
            await created.delete();
            debugPrint('[AdminAccount] rolled back the new auth account.');
          } catch (rollbackError) {
            debugPrint('[AdminAccount] could not roll back the auth account '
                '(${created.uid}): $rollbackError');
          }
        }
        if (e is AuthException || e is LoginConflictException) rethrow;
        final failure = classifyProfileSaveError(e);
        debugPrint('[AdminAccount] member provisioning FAILED '
            '(${failure.name}): $e');
        throw AuthException(
          failure == ProfileSaveFailure.permissionDenied
              ? "The new member's login was created but the database refused "
                  'to save its account record (permission denied), so it was '
                  'rolled back. Check that the latest Firestore rules are '
                  'deployed.'
              : failure == ProfileSaveFailure.network
                  ? 'Could not reach the server while saving the new member '
                      'account. Nothing was kept — check the connection and '
                      'try again.'
                  : 'Could not save the new member account. Nothing was kept '
                      '— please try again.',
          code: 'member-provisioning-failed',
        );
      }
    });
  }

  /// SPARK-PLAN ownership check for [LoginConflictKind.authRecordStillExists]:
  /// the admin proves they control the leftover login by signing in to it
  /// with its CURRENT password.
  ///
  ///  * If nothing in the app belongs to it (its account was deleted), the old
  ///    login is deleted and a fresh one created with [newPassword].
  ///  * If it is a live member without a mobile claim, its password becomes
  ///    [newPassword] and the number is claimed for it — the SAME account is
  ///    returned (`restored`), so no duplicate is ever created.
  Future<ProvisionedAccount> reclaimWithCurrentPassword({
    required String name,
    required String mobile,
    required String email,
    required String currentPassword,
    required String newPassword,
    String gender = '',
    bool profileCreated = true,
  }) async {
    final local = LoginIdentifier.localMobile(mobile);
    if (local == null) {
      throw const AuthException('Enter a valid 10-digit mobile number.',
          code: 'invalid-mobile');
    }
    final realEmail = email.trim().toLowerCase();
    final authEmail =
        realEmail.isNotEmpty ? realEmail : LoginIdentifier.phoneAuthEmail(local);

    final reusable = await _withSecondaryApp<ProvisionedAccount?>((auth, db) async {
      final UserCredential cred;
      try {
        cred = await auth.signInWithEmailAndPassword(
            email: authEmail, password: currentPassword);
      } catch (e) {
        final mapped = AuthException.from(e);
        throw AuthException(
          mapped.code == 'invalid-credential'
              ? 'That is not the current password of the old login.'
              : mapped.message,
          code: mapped.code,
        );
      }
      final user = cred.user!;
      final account =
          await db.collection(AppConstants.usersCollection).doc(user.uid).get();
      // The removed-login record. Unreadable while its rules are not deployed
      // — that must not abort the admin's verified reclaim with a raw
      // permission-denied; the account record alone then decides.
      String tombMode = '';
      try {
        final tomb = await db
            .collection(AppConstants.loginTombstonesCollection)
            .doc(user.uid)
            .get();
        tombMode = '${tomb.data()?['mode'] ?? ''}';
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        debugPrint('[AdminAccount] login_tombstones unreadable (rules not '
            'deployed) — deciding by the account record only.');
      }
      final deleted =
          !account.exists || tombMode == LoginTombstone.modeDeleted;
      if (deleted) {
        await user.delete();
        debugPrint('[AdminAccount] leftover login ${user.uid} deleted after '
            'password verification.');
        return null;
      }
      // A live member: keep the SAME uid.
      final owner = await LoginDirectoryService(db: db)
          .claim(mobile: local, authEmail: authEmail, uid: user.uid);
      if (owner.uid != user.uid) {
        throw const LoginConflictException(LoginConflictKind.phoneInUse,
            'This mobile number belongs to a different account.');
      }
      await user.updatePassword(newPassword);
      await _serverWrite(db
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set({
        'phone': local,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
      return ProvisionedAccount(
        uid: user.uid,
        authEmail: authEmail,
        mobile: local,
        email: realEmail,
        restored: true,
      );
    });
    if (reusable != null) return reusable;
    return _createOnSecondaryApp(
      name: name,
      mobile: local,
      realEmail: realEmail,
      password: newPassword,
      gender: gender,
      profileCreated: profileCreated,
    );
  }

  // ── Remove / restore ──────────────────────────────────────────────────────

  /// Admin → Delete User: the account, its profile and member-private
  /// records, AND its login. See [FirestoreService.deleteUser].
  Future<LoginRemovalResult> deleteMember(String uid,
      {required String adminUid}) async {
    // The LOGIN goes first (when the backend exists): a member whose data
    // deletion then fails half-way can no longer sign in to what is left, and
    // the backend's own guard refuses to remove an administrator.
    bool? authDeleted;
    try {
      authDeleted = (await _backend.deleteLogin(uid, keepData: false)).authDeleted;
    } on AccountBackendException catch (e) {
      if (!e.isUnavailable) throw AuthException(e.message, code: e.code);
    }
    final failed = await _firestore.deleteUser(uid, adminUid: adminUid);
    return LoginRemovalResult(failedSteps: failed, authDeleted: authDeleted);
  }

  /// Admin → Delete Login: the member can no longer sign in, and the mobile
  /// number is released — but the profile, chats, horoscope documents and
  /// every other record are KEPT, and the login can be restored.
  Future<LoginRemovalResult> deleteLogin(String uid,
      {required String adminUid}) async {
    try {
      final r = await _backend.deleteLogin(uid, keepData: true);
      return LoginRemovalResult(authDeleted: r.authDeleted);
    } on AccountBackendException catch (e) {
      if (!e.isUnavailable) throw AuthException(e.message, code: e.code);
    }
    final entries = await _directory.entriesForUid(uid);
    final user = await _firestore.getUserFromServer(uid);
    if (user != null && (user.isAdmin || user.role == 'admin')) {
      throw const AuthException('Administrator logins cannot be deleted here.',
          code: 'admin-login');
    }
    await _firestore.writeLoginTombstone(
      uid,
      mode: LoginTombstone.modeDisabled,
      mobile: entries.isNotEmpty
          ? entries.first.mobile
          : (LoginIdentifier.localMobile(user?.phone ?? '') ?? ''),
      authEmail: entries.isNotEmpty ? entries.first.authEmail : '',
      by: adminUid,
    );
    if (user != null) {
      await _firestore.setLoginAccess(uid, LoginAccessState.disabled,
          by: adminUid);
    }
    for (final e in entries) {
      await _directory.release(e.mobile);
    }
    return const LoginRemovalResult();
  }

  /// Gives a DISABLED login back without the backend: the tombstone is lifted,
  /// the mobile number re-claimed and the member's existing password works
  /// again. (With the backend, restore through [provisionMemberAccount] with
  /// `targetUid`, which also sets a new password.)
  Future<void> restoreDisabledLogin(String uid,
      {required String adminUid}) async {
    final user = await _firestore.getUserFromServer(uid);
    if (user?.loginAccess == LoginAccessState.deleted) {
      // The backend deleted the Firebase Auth record itself — there is no old
      // password left to re-enable. Only a new login under the same UID works.
      throw const AuthException(
        "This member's Firebase login was deleted. Enter a new password to "
        'restore it under the same account.',
        code: 'password-required',
      );
    }
    final record = await _firestore.readLoginTombstone(uid);
    final tombstone = record.tombstone;
    if (tombstone == null) {
      await _firestore.setLoginAccess(uid, LoginAccessState.active);
      return;
    }
    if (tombstone.deletesAuthRecord) {
      throw const AuthException(
        'This login was deleted, not disabled — create a new login instead.',
        code: 'login-deleted',
      );
    }
    final mobile = tombstone.mobile;
    final authEmail = record.authEmail.isNotEmpty
        ? record.authEmail
        : (mobile.isEmpty ? '' : LoginIdentifier.phoneAuthEmail(mobile));
    if (mobile.isNotEmpty && authEmail.isNotEmpty) {
      final holder = await _directory.lookup(mobile);
      if (holder != null && holder.uid != uid) {
        throw LoginConflictException(
          LoginConflictKind.phoneInUse,
          'The mobile number $mobile now belongs to another account.',
        );
      }
      if (holder == null) {
        await _directory.assign(mobile: mobile, authEmail: authEmail, uid: uid);
      }
    }
    await _firestore.setLoginAccess(uid, LoginAccessState.active);
    await _firestore.clearLoginTombstone(uid);
    await _firestore.logAdminAction(
      adminUid: adminUid,
      action: 'login_restored',
      targetUid: uid,
      details: 'Disabled login restored${mobile.isEmpty ? '' : ' ($mobile)'}',
    );
  }

  /// Admin-assisted recovery: a one-time temporary password (backend only).
  /// The member must choose their own at next sign-in.
  Future<String> setTemporaryPassword(String uid, {String requestId = ''}) async {
    try {
      return await _backend.setTemporaryPassword(uid, requestId: requestId);
    } on AccountBackendException catch (e) {
      if (e.isUnavailable) {
        throw const AuthException(
          'Setting a temporary password needs the account backend (Cloud '
          'Functions on the Blaze plan). Send a reset e-mail instead when the '
          'member has a real e-mail address.',
          code: 'backend-required',
        );
      }
      throw AuthException(e.message, code: e.reason.isEmpty ? e.code : e.reason);
    }
  }

  // ── Account Health ────────────────────────────────────────────────────────

  Future<AccountScanReport> scanAccounts() async {
    final results = await Future.wait<Object>([
      _firestore.getAllUsersForScan(),
      _firestore.getAllProfilesForScan(),
      _directory.allEntries(),
      _firestore.allProfileOwners().catchError((Object e) {
        debugPrint('[AdminAccount] profile_owners unreadable: $e');
        return <String, String>{};
      }),
      _firestore.allLoginTombstones().catchError((Object e) {
        debugPrint('[AdminAccount] login_tombstones unreadable: $e');
        return <String, LoginTombstone>{};
      }),
    ]);
    List<AuthAccountInfo>? auth;
    try {
      auth = await _backend.listAuthAccounts();
    } on AccountBackendException catch (e) {
      if (!e.isUnavailable) rethrow;
    }
    return scanAccountIntegrity(
      users: results[0] as List<UserModel>,
      profiles: results[1] as List<ProfileModel>,
      loginIndex: results[2] as List<LoginIndexEntry>,
      ownershipClaims: results[3] as Map<String, String>,
      tombstones: results[4] as Map<String, LoginTombstone>,
      authAccounts: auth,
    );
  }

  /// Records [profileId] as [uid]'s one profile.
  Future<void> repairProfileOwner(String uid, String profileId) =>
      _firestore.setProfileOwner(uid, profileId);

  /// Multiple profiles for one account: keeps [keepProfileId], permanently
  /// deletes the other ids the admin selected, and records the ownership.
  Future<void> keepOneProfile(String uid,
      {required String keepProfileId,
      required List<String> deleteProfileIds,
      required String adminUid}) async {
    for (final id in deleteProfileIds) {
      if (id == keepProfileId) continue;
      await _firestore.deleteProfileById(id);
    }
    await _firestore.setProfileOwner(uid, keepProfileId);
    await _firestore.logAdminAction(
      adminUid: adminUid,
      action: 'duplicate_profiles_resolved',
      targetUid: uid,
      targetProfileId: keepProfileId,
      details: 'Deleted ${deleteProfileIds.join(', ')}',
    );
  }

  Future<void> releaseStaleNumber(String mobile, {required String adminUid}) async {
    await _directory.release(mobile);
    await _firestore.logAdminAction(
      adminUid: adminUid,
      action: 'login_index_released',
      details: 'Released stale mobile registration $mobile',
    );
  }
}
