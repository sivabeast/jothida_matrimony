// Profile creation: the failure a member sees, the account the save may be
// written to, and the required details — without Firebase.
//
// The report: saving a profile showed the raw
// "[cloud_firestore/permission-denied] The caller does not have permission to
// execute the specified operation." — no step named, nothing to act on.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/utils/profile_save_error.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/services/cloudinary/cloudinary_exception.dart';

FirebaseException _fs(String code) => FirebaseException(
    plugin: 'cloud_firestore',
    code: code,
    message: 'The caller does not have permission to execute the specified '
        'operation.');

void main() {
  group('classification', () {
    test('a refused Firestore write is a permission problem', () {
      expect(classifyProfileSaveError(_fs('permission-denied')),
          ProfileSaveFailure.permissionDenied);
    });

    test('network failures are told apart from permission failures', () {
      for (final e in <Object>[
        _fs('unavailable'),
        _fs('deadline-exceeded'),
        TimeoutException('slow'),
        FirebaseAuthException(code: 'network-request-failed'),
      ]) {
        expect(classifyProfileSaveError(e), ProfileSaveFailure.network,
            reason: '$e');
      }
    });

    test('an expired or revoked session asks the member to sign in again', () {
      expect(classifyProfileSaveError(_fs('unauthenticated')),
          ProfileSaveFailure.sessionExpired);
      expect(
          classifyProfileSaveError(
              FirebaseAuthException(code: 'user-token-expired')),
          ProfileSaveFailure.sessionExpired);
    });

    test('the operation travels with the failure', () {
      const e = ProfileSaveException(
          ProfileSaveFailure.permissionDenied, 'profiles/p1 create');
      expect(classifyProfileSaveError(e), ProfileSaveFailure.permissionDenied);
      expect('$e', contains('profiles/p1 create'));
    });

    test('photo upload failures keep their own category', () {
      expect(classifyProfileSaveError(CloudinaryUploadException('boom')),
          ProfileSaveFailure.upload);
    });
  });

  group('what the member reads', () {
    test('never the raw Firebase text, in English and Tamil', () {
      for (final lang in ['en', 'ta']) {
        final l10n = lookupAppLocalizations(Locale(lang));
        for (final f in ProfileSaveFailure.values) {
          final message = profileSaveMessage(l10n, f);
          expect(message, isNotEmpty);
          expect(message, isNot(contains('cloud_firestore')));
          expect(message, isNot(contains('The caller does not have permission')));
        }
      }
    });

    test('permission and network failures say different things', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
          profileSaveMessage(l10n, ProfileSaveFailure.permissionDenied),
          isNot(profileSaveMessage(l10n, ProfileSaveFailure.network)));
    });

    test('admin actions are explained, not dumped', () {
      final message = describeAdminActionError(_fs('permission-denied'));
      expect(message, contains('permission denied'));
      expect(message, isNot(contains('cloud_firestore')));
      expect(describeAdminActionError(TimeoutException('x')),
          contains('Could not reach the server'));
    });
  });

  group('whose profile may be saved', () {
    test('a member saves their OWN profile', () {
      expect(
          checkProfileSaveSession(
              targetUid: 'u1',
              signedInUid: 'u1',
              signedInIsGuest: false,
              onBehalfOfMember: false),
          isNull);
    });

    test('a member can never write another account\'s profile', () {
      expect(
          checkProfileSaveSession(
              targetUid: 'someone-else',
              signedInUid: 'u1',
              signedInIsGuest: false,
              onBehalfOfMember: false),
          ProfileSaveFailure.sessionExpired);
    });

    test('signed out or guest: nothing is written', () {
      expect(
          checkProfileSaveSession(
              targetUid: 'u1',
              signedInUid: null,
              signedInIsGuest: false,
              onBehalfOfMember: false),
          ProfileSaveFailure.notSignedIn);
      expect(
          checkProfileSaveSession(
              targetUid: 'guest',
              signedInUid: 'guest',
              signedInIsGuest: true,
              onBehalfOfMember: false),
          ProfileSaveFailure.notSignedIn);
    });

    test('an admin saves on a member\'s behalf (the rules check the role)', () {
      expect(
          checkProfileSaveSession(
              targetUid: 'member',
              signedInUid: 'admin',
              signedInIsGuest: false,
              onBehalfOfMember: true),
          isNull);
    });
  });

  group('required details', () {
    test('name, gender and date of birth are required', () {
      expect(missingRequiredProfileFields(const {}),
          ['name', 'gender', 'dateOfBirth']);
      expect(
          missingRequiredProfileFields(const {
            'name': 'Ravi',
            'gender': 'Male',
            'dateOfBirth': '1995-01-01T00:00:00.000',
          }),
          isEmpty);
      expect(
          missingRequiredProfileFields(
              const {'name': '  ', 'gender': 'Male', 'dateOfBirth': 'x'}),
          ['name']);
    });
  });
}
