// Permanent account deletion — the ORDER, tested without Firebase.
//
// The bug: data was deleted first, the Auth delete then hit
// `requires-recent-login`, re-authentication only knew Google (so a password
// account could never pass it), and the member was signed out regardless — so
// the old e-mail + password kept working. These tests pin the fixed order.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/utils/account_deletion_flow.dart';
import 'package:jothida_matrimony/repositories/auth_repository.dart';

final _now = DateTime(2026, 9, 16, 12);

class _Harness {
  final calls = <String>[];
  String? uid = 'u1';
  bool anonymous = false;
  List<String> providers = ['password'];
  DateTime? signedInAt = _now.subtract(const Duration(hours: 3));
  List<String> failedSteps = const [];
  bool residual = false;

  /// Errors the Auth delete throws, one per attempt; exhausted → success.
  final authErrors = <DeletionAuthError>[];

  /// What each re-authentication returns, in order.
  final reauthAnswers = <bool>[];

  AccountDeletionFlow get flow => AccountDeletionFlow(
        AccountDeletionPorts(
          currentUid: () => uid,
          isAnonymous: () => anonymous,
          providerIds: () => providers,
          lastSignInTime: () async => signedInAt,
          deleteUserFiles: (_) async => calls.add('files'),
          clearChats: (_) async => calls.add('chats'),
          deleteUserData: (_) async {
            calls.add('data');
            return failedSteps;
          },
          hasResidualData: (_) async {
            calls.add('verify');
            return residual;
          },
          deleteAuthUser: () async {
            calls.add('authDelete');
            if (authErrors.isNotEmpty) throw authErrors.removeAt(0);
          },
          endSession: () async => calls.add('signOut'),
          wait: (_) async => calls.add('wait'),
        ),
        now: () => _now,
      );

  Future<AccountDeletionResult> run() => flow.run((method) async {
        calls.add('reauth:${method.name}');
        return reauthAnswers.isEmpty ? true : reauthAnswers.removeAt(0);
      });
}

void main() {
  group('a normal deletion (Test A)', () {
    test('re-authenticates first, deletes data, deletes Auth, THEN signs out',
        () async {
      final h = _Harness();
      final result = await h.run();
      expect(h.calls, [
        'reauth:password',
        'files',
        'chats',
        'data',
        'verify',
        'authDelete',
        'signOut',
      ]);
      expect(result.outcome, AccountDeletionOutcome.deleted);
      expect(result.authDeleted, isTrue);
    });

    test('a recent sign-in needs no password prompt', () async {
      final h = _Harness()
        ..signedInAt = _now.subtract(const Duration(minutes: 2));
      final result = await h.run();
      expect(h.calls.any((c) => c.startsWith('reauth')), isFalse);
      expect(result.outcome, AccountDeletionOutcome.deleted);
    });

    test('a Google account re-authenticates with Google', () async {
      final h = _Harness()..providers = ['google.com'];
      await h.run();
      expect(h.calls.first, 'reauth:google');
    });
  });

  group('never signs out before the Auth account is gone', () {
    test('cancelled re-authentication deletes nothing and stays signed in',
        () async {
      final h = _Harness()..reauthAnswers.add(false);
      final result = await h.run();
      expect(h.calls, ['reauth:password']);
      expect(result.outcome, AccountDeletionOutcome.cancelled);
      expect(result.authDeleted, isFalse);
    });

    test('a failed Auth delete is reported, and does NOT sign out', () async {
      final h = _Harness()
        ..authErrors.addAll(const [
          DeletionAuthError('internal-error'),
        ]);
      final result = await h.run();
      expect(h.calls, isNot(contains('signOut')));
      expect(result.outcome, AccountDeletionOutcome.loginNotDeleted);
      expect(result.authDeleted, isFalse);
    });

    test('requires-recent-login mid-way re-authenticates and retries',
        () async {
      final h = _Harness()
        ..signedInAt = _now.subtract(const Duration(minutes: 1))
        ..authErrors.add(const DeletionAuthError('requires-recent-login'));
      final result = await h.run();
      expect(h.calls, [
        'files',
        'chats',
        'data',
        'verify',
        'authDelete',
        'reauth:password',
        'authDelete',
        'signOut',
      ]);
      expect(result.outcome, AccountDeletionOutcome.deleted);
    });

    test('refusing the mid-way prompt leaves the login and the session', () async {
      final h = _Harness()
        ..signedInAt = _now
        ..reauthAnswers.add(false)
        ..authErrors.add(const DeletionAuthError('requires-recent-login'));
      final result = await h.run();
      expect(h.calls, isNot(contains('signOut')));
      expect(result.outcome, AccountDeletionOutcome.loginNotDeleted);
    });

    test('a network error is retried', () async {
      final h = _Harness()
        ..authErrors.add(const DeletionAuthError('network-request-failed'));
      final result = await h.run();
      expect(h.calls.where((c) => c == 'authDelete'), hasLength(2));
      expect(h.calls, contains('wait'));
      expect(result.outcome, AccountDeletionOutcome.deleted);
    });
  });

  group('data consistency', () {
    test('identity data that could not be deleted stops before the Auth delete',
        () async {
      final h = _Harness()..failedSteps = ['profiles'];
      final result = await h.run();
      expect(h.calls, isNot(contains('authDelete')));
      expect(h.calls, isNot(contains('signOut')));
      expect(result.outcome, AccountDeletionOutcome.dataNotDeleted);
      expect(result.failedSteps, ['profiles']);
    });

    test('a profile still readable after deletion also stops', () async {
      final h = _Harness()..residual = true;
      final result = await h.run();
      expect(h.calls, isNot(contains('authDelete')));
      expect(result.outcome, AccountDeletionOutcome.dataNotDeleted);
    });

    test('non-identifying cleanup failures are logged but do not block',
        () async {
      final h = _Harness()..failedSteps = ['notifications'];
      final result = await h.run();
      expect(result.outcome, AccountDeletionOutcome.deleted);
      expect(result.failedSteps, ['notifications']);
    });

    test('no signed-in account (or a guest) attempts nothing', () async {
      for (final h in [_Harness()..uid = null, _Harness()..anonymous = true]) {
        final result = await h.run();
        expect(h.calls, isEmpty);
        expect(result.outcome, AccountDeletionOutcome.notSignedIn);
      }
    });

    test('an account with no re-authentication method deletes nothing',
        () async {
      final h = _Harness()..providers = ['phone'];
      final result = await h.run();
      expect(h.calls, isEmpty);
      expect(result.outcome, AccountDeletionOutcome.reauthUnsupported);
    });
  });

  group('building blocks', () {
    test('recent-login window', () {
      expect(isRecentLogin(null, _now), isFalse);
      expect(isRecentLogin(_now.subtract(const Duration(minutes: 3)), _now),
          isTrue);
      expect(isRecentLogin(_now.subtract(const Duration(minutes: 6)), _now),
          isFalse);
    });

    test('password is preferred when both are linked', () {
      expect(reauthMethodForProviders(['google.com', 'password']),
          ReauthMethod.password);
      expect(reauthMethodForProviders(['google.com']), ReauthMethod.google);
      expect(reauthMethodForProviders(const []), ReauthMethod.unsupported);
    });
  });

  group('source guards', () {
    test('no Auth helper signs out as part of deleting', () {
      final src =
          File('lib/services/firebase/auth_service.dart').readAsStringSync();
      expect(src.contains('Future<bool> deleteCurrentUser('), isFalse,
          reason: 'the old helper signed out whatever the outcome');
      final start = src.indexOf('Future<void> deleteAuthUser()');
      final body = src.substring(start, src.indexOf('Future<void> endSessionAfterDeletion()'));
      expect(body.contains('signOut'), isFalse);
    });

    test('the success message is shown only for a real deletion', () {
      final src =
          File('lib/core/utils/account_deletion.dart').readAsStringSync();
      final successAt = src.indexOf('l10n.accountDeletedSuccess');
      final caseAt =
          src.lastIndexOf('case AccountDeletionOutcome.', successAt);
      expect(src.substring(caseAt, successAt),
          contains('AccountDeletionOutcome.deleted'));
      expect(RegExp('accountDeletedSuccess').allMatches(src), hasLength(1));
    });

    test("deleting a staff account keeps members' report requests", () {
      final src = File('lib/services/firebase/firestore_service.dart')
          .readAsStringSync();
      final start = src.indexOf('Future<List<String>> deleteAstrologerAccountData');
      final body = src.substring(start, src.indexOf('Future<bool> _deleteSubcollection'));
      expect(body.contains("'astrologerId', uid"), isFalse);
    });
  });
}
