// Account identity: one mobile number → one login, one login → one profile,
// deleted logins that must not come back, and the Account Health scan.
//
// The bug these pin: Admin → Delete User removed `profiles` + `users/{uid}`
// only. `login_index/{mobile}` survived — so "This mobile number already has
// an account" appeared when the admin re-created the login — and the Firebase
// Auth record survived, so the old password still signed in and quietly
// recreated an empty account.

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/errors/auth_exception.dart';
import 'package:jothida_matrimony/core/utils/account_identity.dart';
import 'package:jothida_matrimony/models/password_reset_request.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/models/user_model.dart';
import 'package:jothida_matrimony/router/auth_redirect.dart';
import 'package:jothida_matrimony/services/firebase/account_admin_backend.dart';

final _t = DateTime(2026, 9, 17);

UserModel _user(
  String uid, {
  String role = 'user',
  String? phone,
  LoginAccessState access = LoginAccessState.active,
  bool mustChangePassword = false,
}) =>
    UserModel(
      uid: uid,
      phone: phone,
      role: role,
      createdAt: _t,
      updatedAt: _t,
      loginAccess: access,
      mustChangePassword: mustChangePassword,
    );

ProfileModel _profile(String id, String userId,
        {bool complete = false, bool dummy = false}) =>
    ProfileModel.fromMap({
      'id': id,
      'userId': userId,
      'name': 'Member $userId',
      if (complete) ...{
        'photos': ['https://res.cloudinary.com/x/image/upload/v1/a.jpg'],
        'education': 'B.E.',
        'horoscopeDetails': {'rasi': 'Mesham'},
      },
    }).copyWith(isDummy: dummy);

void main() {
  group('member account status (Admin → Users)', () {
    test('signed up, no profile → Profile Not Created', () {
      expect(classifyMemberAccount(user: _user('u1'), profile: null),
          MemberAccountStatus.profileNotCreated);
    });

    test('a thin profile is Incomplete, a filled one Completed', () {
      expect(
          classifyMemberAccount(user: _user('u1'), profile: _profile('p', 'u1')),
          MemberAccountStatus.profileIncomplete);
      expect(
          classifyMemberAccount(
              user: _user('u1'), profile: _profile('p', 'u1', complete: true)),
          MemberAccountStatus.profileCompleted);
    });

    test('a removed login is shown as such, whatever the profile', () {
      for (final access in [LoginAccessState.disabled, LoginAccessState.deleted]) {
        expect(
            classifyMemberAccount(
                user: _user('u1', access: access),
                profile: _profile('p', 'u1', complete: true)),
            MemberAccountStatus.authDeleted);
      }
    });

    test('two profiles, a shared phone, or a profile without an account → '
        'Needs Review', () {
      expect(
          classifyMemberAccount(
              user: _user('u1'), profile: _profile('p', 'u1'), profileCount: 2),
          MemberAccountStatus.needsReview);
      expect(
          classifyMemberAccount(
              user: _user('u1'), profile: null, phoneConflict: true),
          MemberAccountStatus.needsReview);
      expect(classifyMemberAccount(user: null, profile: _profile('p', 'u1')),
          MemberAccountStatus.needsReview);
    });

    test('authStatus and mustChangePassword are parsed from the document', () {
      expect(LoginAccessState.parse('disabled'), LoginAccessState.disabled);
      expect(LoginAccessState.parse('DELETED'), LoginAccessState.deleted);
      expect(LoginAccessState.parse(null), LoginAccessState.active);
      expect(LoginAccessState.parse('anything'), LoginAccessState.active);
      expect(LoginTombstone.fromMap('u', {'mode': 'deleted'})!.deletesAuthRecord,
          isTrue);
      expect(LoginTombstone.fromMap('u', {'mode': 'disabled'})!.deletesAuthRecord,
          isFalse);
      expect(LoginTombstone.fromMap('u', {'mode': 'bogus'}), isNull);
    });
  });

  group('one profile per account', () {
    test('the recorded profile wins when it exists', () {
      expect(
          chooseOwnProfileDocId(
              existingNewestFirst: ['newer', 'claimed'],
              claimedId: 'claimed',
              freshId: 'fresh'),
          'claimed');
    });

    test('legacy data without a record is REPLACED, never duplicated', () {
      expect(
          chooseOwnProfileDocId(
              existingNewestFirst: ['legacy'], claimedId: '', freshId: 'fresh'),
          'legacy');
    });

    test('a retry after an interrupted save lands on the recorded id', () {
      expect(
          chooseOwnProfileDocId(
              existingNewestFirst: const [],
              claimedId: 'reserved',
              freshId: 'fresh'),
          'reserved');
    });

    test('only a brand-new account gets a fresh document', () {
      expect(
          chooseOwnProfileDocId(
              existingNewestFirst: const [], claimedId: '', freshId: 'fresh'),
          'fresh');
    });
  });

  group('creating a login for a mobile number', () {
    ExistingLogin login(String uid,
            {bool record = true,
            bool? auth,
            String tomb = '',
            LoginAccessState access = LoginAccessState.active,
            int profiles = 0}) =>
        ExistingLogin(
          uid: uid,
          hasAccountRecord: record,
          authExists: auth,
          tombstoneMode: tomb,
          access: access,
          profileCount: profiles,
        );
    const index = LoginIndexEntry(
        mobile: '9876543210', uid: 'old', authEmail: 'p9876543210@x');

    test('the REPORTED BUG: a deleted login no longer blocks its number', () {
      // Delete User removed the account record and tombstoned the login; only
      // the registry entry is left.
      expect(
          decideLoginAvailability(
              index: index,
              accounts: [login('old', record: false, tomb: 'deleted')],
              authChecked: false),
          LoginAvailability.staleIndex);
      // With the backend, the Firebase Auth record is known to be gone too.
      expect(
          decideLoginAvailability(
              index: index,
              accounts: [login('old', record: false, auth: false)],
              authChecked: true),
          LoginAvailability.staleIndex);
    });

    test('a free number is available', () {
      expect(
          decideLoginAvailability(
              index: null, accounts: const [], authChecked: false),
          LoginAvailability.available);
    });

    test('a live member keeps their number — link, never duplicate', () {
      expect(
          decideLoginAvailability(
              index: index, accounts: [login('old')], authChecked: false),
          LoginAvailability.inUse);
    });

    test('a login disabled with its data kept still owns the number', () {
      expect(
          decideLoginAvailability(
              index: null,
              accounts: [login('m', access: LoginAccessState.disabled)],
              authChecked: false),
          LoginAvailability.inUse);
    });

    test('an Auth record deleted by the backend with data kept still owns it',
        () {
      expect(
          decideLoginAvailability(
              index: null,
              accounts: [
                login('m', auth: false, access: LoginAccessState.deleted)
              ],
              authChecked: true),
          LoginAvailability.inUse);
    });

    test('an Auth record whose app account is gone is stale, not live', () {
      expect(
          decideLoginAvailability(
              index: index, accounts: [login('old', auth: false)], authChecked: true),
          LoginAvailability.staleIndex);
    });

    test('two live accounts on one number must be reviewed first', () {
      expect(
          decideLoginAvailability(
              index: index,
              accounts: [login('a'), login('b')],
              authChecked: false),
          LoginAvailability.multiple);
    });

    test('an unused Firebase login is reported (backend only)', () {
      expect(
          decideLoginAvailability(
              index: null,
              accounts: [login('orphan', record: false, auth: true)],
              authChecked: true),
          LoginAvailability.orphanAuth);
      // …but never one that still has a profile.
      expect(
          decideLoginAvailability(
              index: null,
              accounts: [login('o', record: false, auth: true, profiles: 1)],
              authChecked: true),
          LoginAvailability.available);
    });
  });

  group('Account Health scan', () {
    test('finds every inconsistency without the backend', () {
      final report = scanAccountIntegrity(
        users: [
          _user('a', phone: '9876543210'),
          _user('b', phone: '+91 98765 43210'), // same number, other uid
          _user('c', phone: '9000000001'),
          _user('d'), // member without a profile
          _user('staff', role: 'astrologer'), // never counted as missing
        ],
        profiles: [
          _profile('pa', 'a'),
          _profile('pc1', 'c'),
          _profile('pc2', 'c'), // second profile on one account
          _profile('pz', 'zombie'), // profile whose account is gone
          _profile('dummy', 'seed', dummy: true), // ignored
        ],
        loginIndex: const [
          LoginIndexEntry(mobile: '9876543210', uid: 'a', authEmail: 'x'),
          LoginIndexEntry(mobile: '9111111111', uid: 'gone', authEmail: 'y'),
        ],
        ownershipClaims: const {},
      );

      final types = {for (final i in report.issues) i.type};
      expect(report.authChecked, isFalse);
      expect(types, contains(AccountIssueType.duplicatePhone));
      expect(types, contains(AccountIssueType.multipleProfiles));
      expect(types, contains(AccountIssueType.profileWithoutAccount));
      expect(types, contains(AccountIssueType.staleLoginIndex));
      expect(types, contains(AccountIssueType.missingOwnershipRecord));
      // Auth-only categories are not guessed without the backend.
      expect(types, isNot(contains(AccountIssueType.authWithoutAccount)));
      expect(types, isNot(contains(AccountIssueType.accountWithoutAuth)));

      final dup = report.of(AccountIssueType.duplicatePhone).single;
      expect(dup.mobile, '9876543210');
      expect(dup.uids, ['a', 'b']);
      expect(report.of(AccountIssueType.staleLoginIndex).single.mobile,
          '9111111111');
      expect(report.of(AccountIssueType.multipleProfiles).single.profileIds,
          unorderedEquals(['pc1', 'pc2']));
      expect(report.membersWithoutProfileUids, ['b', 'd']);
    });

    test('a correct ownership record is not reported', () {
      final report = scanAccountIntegrity(
        users: [_user('a')],
        profiles: [_profile('pa', 'a')],
        loginIndex: const [],
        ownershipClaims: const {'a': 'pa'},
      );
      expect(report.issues, isEmpty);
    });

    test('a tombstoned (deleted) account does not hold its number', () {
      final report = scanAccountIntegrity(
        users: [_user('new', phone: '9876543210')],
        profiles: const [],
        loginIndex: const [
          LoginIndexEntry(mobile: '9876543210', uid: 'old', authEmail: 'x'),
        ],
        ownershipClaims: const {},
        tombstones: const {
          'old': LoginTombstone(uid: 'old', mode: LoginTombstone.modeDeleted),
        },
      );
      expect(report.of(AccountIssueType.duplicatePhone), isEmpty);
      expect(report.of(AccountIssueType.staleLoginIndex).single.uids, ['old']);
    });

    test('with the backend: unlinked logins, missing logins, mismatches', () {
      final report = scanAccountIntegrity(
        users: [
          _user('a', phone: '9876543210'),
          _user('noauth'),
          _user('kept', access: LoginAccessState.deleted),
        ],
        profiles: [_profile('pa', 'a')],
        loginIndex: const [
          LoginIndexEntry(
              mobile: '9876543210', uid: 'a', authEmail: 'old@mail.com'),
        ],
        ownershipClaims: const {'a': 'pa'},
        authAccounts: const [
          AuthAccountInfo(
              uid: 'a',
              email: 'p9876543210@phone.jothidamatrimony.app',
              providers: ['password']),
          AuthAccountInfo(
              uid: 'stray',
              email: 'p9123456789@phone.jothidamatrimony.app',
              providers: ['password']),
          AuthAccountInfo(uid: 'guest'), // anonymous — ignored
        ],
      );
      expect(report.authChecked, isTrue);
      expect(report.of(AccountIssueType.authWithoutAccount).single.uids,
          ['stray']);
      expect(report.of(AccountIssueType.authWithoutAccount).single.mobile,
          '9123456789');
      // 'kept' was deleted by the backend with its data kept — recorded, so
      // not an inconsistency.
      expect(report.of(AccountIssueType.accountWithoutAuth).single.uids,
          ['noauth']);
      expect(report.of(AccountIssueType.loginIndexMismatch), hasLength(1));
    });
  });

  group('recovery privacy + request limits', () {
    test('masking never reveals the synthesized address or the whole number',
        () {
      expect(maskEmail('p9876543210@phone.jothidamatrimony.app'), '');
      expect(maskEmail('ravi.kumar@gmail.com'), 'ra•••@g•••.com');
      expect(maskMobile('+91 98765 43210'), '98•••••210');
    });

    test('one reset request per number per UTC day', () {
      final day = PasswordResetRequest.dayKeyFor(DateTime.utc(2026, 9, 17, 23));
      expect(PasswordResetRequest.dayKeyFor(DateTime.utc(2026, 9, 17, 1)), day);
      expect(PasswordResetRequest.dayKeyFor(DateTime.utc(2026, 9, 18, 1)),
          day + 1);
      expect(PasswordResetRequest.idFor('9876543210', day), '9876543210_$day');
      expect(PasswordResetStatus.parse('under_review'),
          PasswordResetStatus.underReview);
      expect(PasswordResetStatus.parse('junk'), PasswordResetStatus.pending);
      expect(PasswordResetStatus.resolved.isOpen, isFalse);
    });
  });

  group('backend errors', () {
    test('an undeployed function is "unavailable", not a failure', () {
      final e = AccountAdminBackend.mapFunctionsError('not-found', 'NOT_FOUND', null);
      expect(e.isUnavailable, isTrue);
      expect(AccountAdminBackend.mapFunctionsError('unavailable', 'x', null)
          .isUnavailable, isTrue);
    });

    test('the reason travels to the app', () {
      final e = AccountAdminBackend.mapFunctionsError('already-exists', 'taken', {
        'reason': 'phone-number-already-exists',
        'account': {
          'uid': 'u9',
          'hasUserDoc': true,
          'profileCount': 1,
          'auth': {'uid': 'u9', 'email': 'a@b.com', 'providers': ['password']},
        },
      });
      expect(e.isUnavailable, isFalse);
      expect(e.reason, 'phone-number-already-exists');
      expect(e.account!.uid, 'u9');
      expect(e.account!.auth!.providers, ['password']);
    });
  });

  group('Firebase errors are named precisely', () {
    test('credential / phone already in use are not "account exists"', () {
      expect(AuthException.from(_fae('credential-already-in-use')).code,
          'credential-already-in-use');
      expect(AuthException.from(_fae('phone-number-already-exists')).code,
          'phone-number-already-exists');
    });

    test('OTP failures', () {
      expect(AuthException.from(_fae('invalid-verification-code')).code,
          'invalid-verification-code');
      expect(AuthException.from(_fae('session-expired')).code,
          'session-expired');
      expect(AuthException.from(_fae('billing-not-enabled')).code,
          'otp-unavailable');
      expect(
          AuthException.from(_fae('internal-error',
                  message: 'An internal error has occurred. [ BILLING_NOT_ENABLED ]'))
              .code,
          'otp-unavailable');
    });
  });

  group('router gates', () {
    String? at(String loc, UserModel user) => resolveAuthRedirect(
        location: loc,
        isAuthenticated: true,
        userDocLoading: false,
        user: user);

    test('a removed login is held on the explanation screen', () {
      final removed = _user('u1', access: LoginAccessState.disabled);
      expect(at('/home', removed), '/account-unavailable');
      expect(at('/account-unavailable', removed), isNull);
      expect(at('/help', removed), isNull);
    });

    test('a temporary password must be replaced first', () {
      final temp = _user('u1', mustChangePassword: true);
      expect(at('/home', temp), '/change-password');
      expect(at('/login', temp), '/change-password');
      expect(at('/change-password', temp), isNull);
    });

    test('a normal member is unaffected', () {
      expect(at('/home', _user('u1')), isNull);
    });
  });
}

FirebaseAuthException _fae(String code, {String? message}) =>
    FirebaseAuthException(code: code, message: message);
