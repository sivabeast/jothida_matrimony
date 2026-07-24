// A test-only fake implements the sealed `DocumentSnapshot`; that is
// intentional and scoped to this file.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:jothida_matrimony/models/user_model.dart';

/// Minimal stand-in for a Firestore document so `UserModel.fromFirestore` can be
/// exercised without a live backend.
class _FakeDoc extends Fake implements DocumentSnapshot {
  _FakeDoc(this._id, this._data);
  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  Map<String, dynamic>? data() => _data;
}

void main() {
  group('UserModel.fromFirestore is resilient to loosely-typed documents', () {
    // This is the regression guard for the production crash "type 'String' is
    // not a subtype of type 'bool' in type cast", which struck right after a
    // successful Google sign-in and read as "Signed in, but something went
    // wrong while setting up your account".
    test('boolean flags stored as strings / numbers do not crash', () {
      final doc = _FakeDoc('u1', {
        'isProfileComplete': 'true',
        'isEmailVerified': 'false',
        'isPhoneVerified': 1,
        'isBlocked': 0,
        'freePortuthamsUsed': '3',
        'privacySettings': {
          'hidePhone': 'true',
          'hideSalary': false,
        },
      });

      final user = UserModel.fromFirestore(doc);

      expect(user.isProfileComplete, isTrue);
      expect(user.isEmailVerified, isFalse);
      expect(user.isPhoneVerified, isTrue);
      expect(user.isBlocked, isFalse);
      expect(user.freePortuthamsUsed, 3);
      // Coerced string value…
      expect(user.privacySettings['hidePhone'], isTrue);
      // …existing bool kept…
      expect(user.privacySettings['hideSalary'], isFalse);
      // …and a missing default is backfilled.
      expect(user.privacySettings['hideAddress'], isFalse);
    });

    test('a document with none of the optional fields falls back cleanly', () {
      final user = UserModel.fromFirestore(_FakeDoc('u2', <String, dynamic>{}));

      expect(user.role, 'user');
      expect(user.isProfileComplete, isFalse);
      expect(user.isBlocked, isFalse);
      expect(user.freePortuthamsUsed, 0);
      expect(user.privacySettings.length, 6);
      expect(user.privacySettings.values.every((v) => v == false), isTrue);
    });

    test('genuine bool/int values still parse normally', () {
      final doc = _FakeDoc('u3', {
        'isProfileComplete': true,
        'isBlocked': true,
        'freePortuthamsUsed': 5,
        'role': 'admin',
      });

      final user = UserModel.fromFirestore(doc);

      expect(user.isProfileComplete, isTrue);
      expect(user.isBlocked, isTrue);
      expect(user.freePortuthamsUsed, 5);
      expect(user.role, 'admin');
      expect(user.isAdmin, isTrue);
    });
  });
}
