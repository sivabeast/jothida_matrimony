// Admin login management with fakes: delete / recreate, Delete Login keeping
// data, restore, and the OTP resend limits. No Firebase is started — the
// services are replaced by in-memory fakes (`implements` + noSuchMethod).

import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/errors/auth_exception.dart';
import 'package:jothida_matrimony/core/utils/account_identity.dart';
import 'package:jothida_matrimony/core/utils/otp_throttle.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/models/user_model.dart';
import 'package:jothida_matrimony/services/firebase/account_admin_backend.dart';
import 'package:jothida_matrimony/services/firebase/admin_account_service.dart';
import 'package:jothida_matrimony/services/firebase/firestore_service.dart';
import 'package:jothida_matrimony/services/firebase/login_directory_service.dart';

final _t = DateTime(2026, 9, 17);

/// In-memory stand-in for the Firestore records the service touches.
class _FakeStore implements FirestoreService {
  final users = <String, UserModel>{};
  final profiles = <String, List<ProfileModel>>{};
  final tombstones = <String, Map<String, dynamic>>{};
  final calls = <String>[];

  @override
  Future<UserModel?> getUserFromServer(String uid) async => users[uid];

  @override
  Future<List<UserModel>> usersWithPhone(String mobile) async => [
        for (final u in users.values)
          if ((u.phone ?? '').endsWith(mobile)) u,
      ];

  @override
  Future<List<ProfileModel>> profilesOfUser(String uid) async =>
      profiles[uid] ?? const [];

  @override
  Future<({LoginTombstone? tombstone, String authEmail})> readLoginTombstone(
      String uid) async {
    final data = tombstones[uid];
    return (
      tombstone: LoginTombstone.fromMap(uid, data),
      authEmail: '${data?['authEmail'] ?? ''}',
    );
  }

  @override
  Future<void> writeLoginTombstone(String uid,
      {required String mode,
      String mobile = '',
      String authEmail = '',
      String by = '',
      bool authDeleted = false}) async {
    calls.add('tombstone:$uid:$mode');
    tombstones[uid] = {'mode': mode, 'mobile': mobile, 'authEmail': authEmail};
  }

  @override
  Future<void> clearLoginTombstone(String uid) async {
    calls.add('clearTombstone:$uid');
    tombstones.remove(uid);
  }

  @override
  Future<void> setLoginAccess(String uid, LoginAccessState access,
      {String by = ''}) async {
    calls.add('access:$uid:${access.name}');
    users[uid] = users[uid]!.copyWith(loginAccess: access);
  }

  @override
  Future<List<String>> deleteUser(String userId, {String adminUid = ''}) async {
    calls.add('deleteUser:$userId');
    tombstones[userId] = {'mode': LoginTombstone.modeDeleted};
    users.remove(userId);
    profiles.remove(userId);
    return [];
  }

  @override
  Future<void> deleteProfileById(String profileId) async =>
      calls.add('deleteProfile:$profileId');

  @override
  Future<void> logAdminAction(
          {required String adminUid,
          required String action,
          String targetUid = '',
          String targetProfileId = '',
          String details = ''}) async =>
      calls.add('log:$action');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeDirectory implements LoginDirectoryService {
  final entries = <String, LoginIndexEntry>{};
  final calls = <String>[];

  @override
  Future<LoginIndexEntry?> lookup(String mobile) async => entries[mobile];

  @override
  Future<List<LoginIndexEntry>> entriesForUid(String uid) async =>
      [for (final e in entries.values) if (e.uid == uid) e];

  @override
  Future<void> release(String mobile) async {
    calls.add('release:$mobile');
    entries.remove(mobile);
  }

  @override
  Future<void> assign(
      {required String mobile,
      required String authEmail,
      required String uid}) async {
    calls.add('assign:$mobile:$uid');
    entries[mobile] =
        LoginIndexEntry(mobile: mobile, uid: uid, authEmail: authEmail);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The Spark-plan situation: no Cloud Functions deployed.
class _NoBackend implements AccountAdminBackend {
  final calls = <String>[];
  static const _gone = AccountBackendException(
      'not-deployed', 'The account backend is not deployed.');

  @override
  Future<({LoginIndexEntry? index, List<BackendAccount> accounts})> inspectLogin(
      {String mobile = '', String email = '', String uid = ''}) async {
    calls.add('inspect');
    throw _gone;
  }

  @override
  Future<({bool authDeleted, int indexRemoved})> deleteLogin(String uid,
      {required bool keepData}) async {
    calls.add('deleteLogin:$uid:$keepData');
    throw _gone;
  }

  @override
  Future<Map<String, dynamic>> provisionLogin(
      {required String mobile,
      required String email,
      required String password,
      String displayName = '',
      String gender = '',
      String targetUid = '',
      String replaceOrphanUid = '',
      bool profileCreated = false,
      bool mustChangePassword = false}) async {
    calls.add('provision');
    throw _gone;
  }

  @override
  Future<String> setTemporaryPassword(String uid, {String requestId = ''}) =>
      throw _gone;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A deployed backend that deletes Auth records.
class _Backend extends _NoBackend {
  bool refuse = false;
  @override
  Future<({bool authDeleted, int indexRemoved})> deleteLogin(String uid,
      {required bool keepData}) async {
    calls.add('deleteLogin:$uid:$keepData');
    if (refuse) {
      throw const AccountBackendException('failed-precondition',
          'Administrator logins cannot be deleted here.');
    }
    return (authDeleted: true, indexRemoved: 1);
  }
}

UserModel _member(String uid, String phone) => UserModel(
    uid: uid, phone: phone, role: 'user', createdAt: _t, updatedAt: _t);

ProfileModel _profile(String id, String uid) =>
    ProfileModel.fromMap({'id': id, 'userId': uid, 'name': 'M'});

void main() {
  late _FakeStore store;
  late _FakeDirectory directory;
  late _NoBackend backend;
  AdminAccountService service() => AdminAccountService(
      directory: directory, firestore: store, backend: backend);

  setUp(() {
    store = _FakeStore();
    directory = _FakeDirectory();
    backend = _NoBackend();
  });

  group('delete a login, then create it again (the reported bug)', () {
    test('after Delete User the number is a STALE registration, not '
        '"already has an account"', () async {
      store.users['old'] = _member('old', '9876543210');
      store.profiles['old'] = [_profile('p1', 'old')];
      directory.entries['9876543210'] = const LoginIndexEntry(
          mobile: '9876543210', uid: 'old', authEmail: 'p9876543210@x');

      // The OLD behaviour left exactly this behind: the registry entry. Now
      // Delete User tombstones the login too.
      final removal = await service().deleteMember('old', adminUid: 'adm');
      expect(removal.backendUnavailable, isTrue);
      expect(store.calls, contains('deleteUser:old'));

      final inspection = await service().inspectMobile('9876543210');
      expect(inspection.availability, LoginAvailability.staleIndex);

      // Creating the login again asks the admin to release the number…
      await expectLater(
        service().provisionMemberAccount(
            name: 'New', mobile: '9876543210', email: '', password: 'secret1'),
        throwsA(isA<LoginConflictException>()
            .having((e) => e.kind, 'kind', LoginConflictKind.staleIndex)),
      );
      expect(directory.entries, contains('9876543210'),
          reason: 'nothing is released without the admin confirming');
    });

    test('a LIVE member is never duplicated — the admin is shown the account',
        () async {
      store.users['m1'] = _member('m1', '9876543210');
      directory.entries['9876543210'] = const LoginIndexEntry(
          mobile: '9876543210', uid: 'm1', authEmail: 'p9876543210@x');

      await expectLater(
        service().provisionMemberAccount(
            name: 'Dup', mobile: '9876543210', email: '', password: 'secret1'),
        throwsA(isA<LoginConflictException>()
            .having((e) => e.kind, 'kind', LoginConflictKind.phoneInUse)
            .having((e) => e.account?.uid, 'account', 'm1')),
      );
    });

    test('with the backend, Delete User removes the Firebase login FIRST',
        () async {
      backend = _Backend();
      store.users['old'] = _member('old', '9876543210');
      final removal = await service().deleteMember('old', adminUid: 'adm');
      expect(removal.authDeleted, isTrue);
      expect(backend.calls.first, 'deleteLogin:old:false');
      expect(store.calls, contains('deleteUser:old'));
    });

    test('the backend refusing (an administrator) stops before any data is '
        'deleted', () async {
      backend = _Backend()..refuse = true;
      store.users['adm2'] = _member('adm2', '9876543210');
      await expectLater(service().deleteMember('adm2', adminUid: 'adm'),
          throwsA(isA<AuthException>()));
      expect(store.calls, isNot(contains('deleteUser:adm2')));
    });
  });

  group('Delete Login keeps the member\'s data', () {
    test('without the backend: login disabled, number released, nothing '
        'deleted', () async {
      store.users['m1'] = _member('m1', '9876543210');
      store.profiles['m1'] = [_profile('p1', 'm1')];
      directory.entries['9876543210'] = const LoginIndexEntry(
          mobile: '9876543210', uid: 'm1', authEmail: 'p9876543210@x');

      final result = await service().deleteLogin('m1', adminUid: 'adm');

      expect(result.backendUnavailable, isTrue);
      expect(store.calls, contains('tombstone:m1:disabled'));
      expect(store.calls, contains('access:m1:disabled'));
      expect(directory.calls, contains('release:9876543210'));
      expect(store.calls.where((c) => c.startsWith('delete')), isEmpty,
          reason: 'profile, chats and documents are kept');
      expect(store.profiles['m1'], isNotEmpty);
    });

    test('restore gives the SAME account its number and access back',
        () async {
      store.users['m1'] = _member('m1', '9876543210');
      directory.entries['9876543210'] = const LoginIndexEntry(
          mobile: '9876543210', uid: 'm1', authEmail: 'p9876543210@x');
      await service().deleteLogin('m1', adminUid: 'adm');

      await service().restoreDisabledLogin('m1', adminUid: 'adm');

      expect(directory.entries['9876543210']!.uid, 'm1');
      expect(store.users['m1']!.loginAccess, LoginAccessState.active);
      expect(store.tombstones, isNot(contains('m1')));
    });

    test('restore refuses when the number now belongs to someone else',
        () async {
      store.users['m1'] = _member('m1', '9876543210');
      directory.entries['9876543210'] = const LoginIndexEntry(
          mobile: '9876543210', uid: 'm1', authEmail: 'p9876543210@x');
      await service().deleteLogin('m1', adminUid: 'adm');
      directory.entries['9876543210'] = const LoginIndexEntry(
          mobile: '9876543210', uid: 'other', authEmail: 'z@x');

      await expectLater(service().restoreDisabledLogin('m1', adminUid: 'adm'),
          throwsA(isA<LoginConflictException>()));
      expect(store.users['m1']!.loginAccess, LoginAccessState.disabled);
    });

    test('a login whose Firebase record the backend deleted is not reported '
        'as restored without a new password', () async {
      store.users['m2'] = _member('m2', '9876543210')
          .copyWith(loginAccess: LoginAccessState.deleted);
      store.tombstones['m2'] = {'mode': LoginTombstone.modeDisabled};
      await expectLater(service().restoreDisabledLogin('m2', adminUid: 'adm'),
          throwsA(isA<AuthException>()
              .having((e) => e.code, 'code', 'password-required')));
      expect(store.users['m2']!.loginAccess, LoginAccessState.deleted);
    });

    test('a DELETED account cannot be "restored" — it needs a new login',
        () async {
      store.tombstones['gone'] = {'mode': LoginTombstone.modeDeleted};
      await expectLater(service().restoreDisabledLogin('gone', adminUid: 'adm'),
          throwsA(isA<AuthException>()
              .having((e) => e.code, 'code', 'login-deleted')));
    });

    test('an administrator login cannot be removed from the app', () async {
      store.users['boss'] = UserModel(
          uid: 'boss', role: 'admin', createdAt: _t, updatedAt: _t);
      await expectLater(service().deleteLogin('boss', adminUid: 'adm'),
          throwsA(isA<AuthException>()));
      expect(store.calls, isEmpty);
    });
  });

  group('backend-only actions say so on the Spark plan', () {
    test('temporary password', () async {
      await expectLater(service().setTemporaryPassword('m1'),
          throwsA(isA<AuthException>()
              .having((e) => e.code, 'code', 'backend-required')));
    });

    test('restoring a login under the same UID with a new password', () async {
      await expectLater(
        service().provisionMemberAccount(
            name: 'M',
            mobile: '9876543210',
            email: '',
            password: 'secret1',
            targetUid: 'm1'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', 'backend-required')),
      );
    });
  });

  group('OTP resend limits', () {
    final now = DateTime(2026, 9, 17, 12);

    test('first send is immediate', () {
      expect(OtpThrottle.waitBeforeSend(const [], now), Duration.zero);
    });

    test('a resend waits for the cooldown', () {
      final wait = OtpThrottle.waitBeforeSend(
          [now.subtract(const Duration(seconds: 20))], now);
      expect(wait, const Duration(seconds: 40));
      expect(OtpThrottle.isLockout(wait), isFalse);
    });

    test('the fourth send in 30 minutes is locked out', () {
      final sends = [
        now.subtract(const Duration(minutes: 20)),
        now.subtract(const Duration(minutes: 10)),
        now.subtract(const Duration(minutes: 5)),
      ];
      final wait = OtpThrottle.waitBeforeSend(sends, now);
      expect(wait, const Duration(minutes: 10));
      expect(OtpThrottle.isLockout(wait), isTrue);
    });

    test('old sends fall out of the window', () {
      expect(
          OtpThrottle.waitBeforeSend([
            now.subtract(const Duration(minutes: 50)),
            now.subtract(const Duration(minutes: 45)),
            now.subtract(const Duration(minutes: 40)),
          ], now),
          Duration.zero);
    });
  });
}
