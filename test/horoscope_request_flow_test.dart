// The Horoscope Report Request, verification, married and rating rules.
//
// These cover the promises that are easy to break silently later:
//
//   * a WhatsApp number is EXACTLY 10 digits — never 9, never 11, never text;
//   * a submitted request is a SNAPSHOT, so editing a profile afterwards can
//     never rewrite it;
//   * Nakshatra / Rasi / the horoscope image stay OPTIONAL;
//   * a guest's request is flagged as such and carries no assignment;
//   * verification is REVERSIBLE, and revoking touches nothing else;
//   * the update gate blocks only builds below the configured floor.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/constants/app_constants.dart';
import 'package:jothida_matrimony/models/app_update_config.dart';
import 'package:jothida_matrimony/models/astrologer_request_model.dart';
import 'package:jothida_matrimony/models/location_model.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/screens/report/horoscope_request_person_form.dart';

/// Runs the formatter the way a text field would: old value → new value.
String _typed(String existing, String incoming) {
  const f = WhatsAppNumberFormatter();
  return f
      .formatEditUpdate(
        TextEditingValue(text: existing),
        TextEditingValue(
            text: incoming,
            selection: TextSelection.collapsed(offset: incoming.length)),
      )
      .text;
}

HoroscopePersonDraft _draft({
  String name = 'Meena Karthik',
  DateTime? dob,
  int hour = 6,
  int minute = 45,
  bool pm = false,
  String? nakshatra,
  String? rasi,
  String image = '',
}) {
  final d = HoroscopePersonDraft()
    ..dob = dob ?? DateTime(1998, 4, 12)
    ..hour = hour
    ..minute = minute
    ..isPm = pm
    ..place = const PlaceSelection(
        city: 'Rosalpatti', district: 'Virudhunagar', state: 'Tamil Nadu')
    ..nakshatra = nakshatra
    ..rasi = rasi
    ..imageUrl = image;
  d.name.text = name;
  return d;
}

/// A minimal profile, built only as far as the verification rules need.
ProfileModel _profile({required String status}) => ProfileModel(
      id: 'p1',
      userId: 'u1',
      profileCreatedBy: 'Myself',
      profileCreatedFor: 'Myself',
      fullName: 'Meena Karthik',
      gender: 'Female',
      dateOfBirth: DateTime(1998, 4, 12),
      age: 27,
      height: "5'4\"",
      weight: '54 kg',
      maritalStatus: 'Never Married',
      religion: 'Hindu',
      caste: 'Vanniyar',
      educationLevel: 'UG',
      education: 'B.Sc',
      occupation: 'Teacher',
      annualIncome: '₹5-7 Lakhs',
      country: 'India',
      state: 'Tamil Nadu',
      district: 'Virudhunagar',
      city: 'Rosalpatti',
      motherTongue: 'Tamil',
      horoscope: const HoroscopeDetails(
        rasi: 'மேஷம்',
        nakshatra: 'அசுவினி',
        lagnam: 'ரிஷபம்',
        dasaBalance: '',
        yogam: '',
        karanam: '',
        moonSign: '',
        sunSign: '',
        birthTime: '06:45 AM',
        birthPlace: 'Rosalpatti, Virudhunagar',
      ),
      partnerPreferences: const PartnerPreferences(),
      contact: const ContactDetails(
          contactPersonName: 'Karthik',
          relationship: 'Father',
          mobileNumber: '9876543210'),
      status: status,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('WhatsApp number — exactly 10 digits (§8/§34)', () {
    test('letters and symbols cannot be entered at all', () {
      expect(_typed('', 'abc98765!43210xyz'), '9876543210');
      expect(_typed('', '98765 43210'), '9876543210');
      expect(_typed('', '98765-43210'), '9876543210');
    });

    test('an 11th digit is refused rather than accepted and trimmed later', () {
      expect(_typed('9876543210', '98765432101').length, 10);
      expect(_typed('9876543210', '98765432101'), '9876543210');
    });

    test('a pasted +91 number resolves to the local 10 digits', () {
      expect(_typed('', '+91 98765 43210'), '9876543210');
      expect(_typed('', '919876543210'), '9876543210');
    });

    test('9 digits are left as typed — the FORM rejects them, not the field',
        () {
      // The formatter must not "helpfully" pad or block a partial number, or
      // the member could never type one digit at a time.
      expect(_typed('', '987654321'), '987654321');
      expect(_typed('', '987654321').length, lessThan(10));
    });

    test('the model only dials a genuine 10-digit number', () {
      AstrologerRequestModel req(String number) => AstrologerRequestModel(
            id: 'r1',
            astrologerId: '',
            userId: 'u1',
            userName: 'Guest',
            type: AstrologerRequestType.matching,
            createdAt: DateTime(2026, 8, 27),
            contactWhatsapp: number,
          );
      expect(req('9876543210').whatsappDialNumber, '919876543210');
      expect(req('919876543210').whatsappDialNumber, '919876543210');
      expect(req('987654321').whatsappDialNumber, '');
      expect(req('').whatsappDialNumber, '');
    });
  });

  group('person snapshot (§3/§7)', () {
    test('the AM/PM half is stored, not just the clock face', () {
      expect(_draft(hour: 6, minute: 45, pm: false).toMap()['tob'], '06:45 AM');
      expect(_draft(hour: 6, minute: 45, pm: true).toMap()['tob'], '06:45 PM');
      expect(_draft(pm: true).toMap()['tobPeriod'], 'PM');
    });

    test('District and City are stored separately from the display place', () {
      final m = _draft().toMap();
      expect(m['placeDistrict'], 'Virudhunagar');
      expect(m['placeCity'], 'Rosalpatti');
      expect(m['place'], 'Rosalpatti, Virudhunagar, Tamil Nadu');
    });

    test('Nakshatra, Rasi and the horoscope image are optional', () {
      final m = _draft().toMap();
      expect(m['nakshatra'], '');
      expect(m['rasi'], '');
      expect(m['horoscopeImageUrl'], '');
      // …and the required parts are still there, so a blank optional field
      // never leaves the request unusable.
      expect(m['name'], 'Meena Karthik');
      expect(m['dob'], isNotEmpty);
      expect(m['tob'], isNotEmpty);
    });

    test('a later profile edit cannot rewrite an already-stored snapshot', () {
      final draft = _draft(name: 'Person B', dob: DateTime(1990, 1, 2));
      final stored = draft.toMap();

      // The member goes back and changes everything — as if they had edited
      // their profile after submitting.
      draft.name.text = 'Someone Else';
      draft.dob = DateTime(2001, 12, 31);
      draft.nakshatra = 'அசுவினி';

      expect(stored['name'], 'Person B');
      expect(stored['dob'], '02 Jan 1990');
      expect(stored['nakshatra'], '');
    });

    test('clear() empties every field so a new person can be entered', () {
      final d = _draft(nakshatra: 'அசுவினி', rasi: 'மேஷம்', image: 'u');
      expect(d.isBlank, isFalse);
      d.clear();
      expect(d.isBlank, isTrue);
      expect(d.toMap()['name'], '');
      expect(d.toMap()['place'], '');
    });

    test('age is derived from the DOB, not typed', () {
      final dob = DateTime(DateTime.now().year - 30, 1, 1);
      expect(_draft(dob: dob).age, anyOf(29, 30));
    });
  });

  group('the request document (§10/§35)', () {
    AstrologerRequestModel build({required bool guest}) =>
        AstrologerRequestModel(
          id: 'doc123456789',
          astrologerId: '',
          userId: 'uid-1',
          userName: guest ? 'Guest' : 'Meena',
          type: AstrologerRequestType.matching,
          createdAt: DateTime(2026, 8, 27),
          requestCode: 'JH-260827-4821',
          contactName: 'Karthik',
          contactWhatsapp: '9876543210',
          guestRequest: guest,
          externalRequest: {
            'requester': _draft(name: 'Person 1').toMap(),
            'other': _draft(name: 'Person 2').toMap(),
            'contact': {'name': 'Karthik', 'whatsapp': '9876543210'},
          },
        );

    test('a guest request is flagged and carries no assignment', () {
      final r = build(guest: true);
      expect(r.guestRequest, isTrue);
      expect(r.isAssigned, isFalse);
      expect(r.astrologerEmail, isEmpty);
      expect(r.amount, 0);
      expect(r.paid, isFalse);
    });

    test('both persons and the contact survive a Firestore round trip', () {
      final map = build(guest: true).toFirestore();
      expect(map['guestRequest'], isTrue);
      expect(map['contactWhatsapp'], '9876543210');
      expect(map['contactName'], 'Karthik');
      expect(map['requestCode'], 'JH-260827-4821');
      final ext = map['externalRequest'] as Map<String, dynamic>;
      expect((ext['requester'] as Map)['name'], 'Person 1');
      expect((ext['other'] as Map)['name'], 'Person 2');
    });

    test('the readable code is what is shown, with a fallback for old docs',
        () {
      expect(build(guest: false).displayRequestId, 'JH-260827-4821');
      final legacy = AstrologerRequestModel(
        id: 'abcdefghijklmnop',
        astrologerId: '',
        userId: 'u',
        userName: 'u',
        type: AstrologerRequestType.matching,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(legacy.displayRequestId, isNotEmpty);
      expect(legacy.displayRequestId, 'ABCDEFGHIJ');
    });

    test('copyWith never rewrites the snapshot or the contact person', () {
      final r = build(guest: true);
      final assigned = r.copyWith(
          astrologerEmail: 'staff@example.com',
          status: AstrologerRequestStatus.accepted);
      expect(assigned.contactWhatsapp, '9876543210');
      expect(assigned.requestCode, 'JH-260827-4821');
      expect(assigned.guestRequest, isTrue);
      expect(assigned.externalRequester['name'], 'Person 1');
    });

    test('a legacy request with no contact falls back to the account name', () {
      final legacy = AstrologerRequestModel(
        id: 'r',
        astrologerId: '',
        userId: 'u',
        userName: 'Meena Karthik',
        type: AstrologerRequestType.matching,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(legacy.displayContactName, 'Meena Karthik');
    });
  });

  group('mandatory update gate (§25/§27/§28)', () {
    test('a build below the floor is FORCED', () {
      const c = AppUpdateConfig(
          latestVersionCode: 20, minimumSupportedVersionCode: 20);
      expect(c.requirementFor(19), AppUpdateRequirement.forced);
    });

    test('a build at or above the floor is never forced', () {
      const c = AppUpdateConfig(
          latestVersionCode: 21, minimumSupportedVersionCode: 20);
      // Behind the latest, but above the floor → OPTIONAL, so an ordinary
      // Play release does not lock anyone out (§28).
      expect(c.requirementFor(20), AppUpdateRequirement.optional);
      expect(c.requirementFor(21), AppUpdateRequirement.none);
      expect(c.requirementFor(22), AppUpdateRequirement.none);
    });

    test('an unconfigured or unreadable version never blocks anyone', () {
      expect(const AppUpdateConfig().requirementFor(19),
          AppUpdateRequirement.none);
      const c = AppUpdateConfig(
          latestVersionCode: 20, minimumSupportedVersionCode: 20);
      expect(c.requirementFor(0), AppUpdateRequirement.none);
    });

    test('Update Now always resolves to a real Play listing', () {
      expect(const AppUpdateConfig().effectivePlayStoreUrl,
          AppUpdateConfig.defaultPlayStoreUrl);
      expect(
          const AppUpdateConfig(playStoreUrl: 'https://evil.example.com/apk')
              .effectivePlayStoreUrl,
          AppUpdateConfig.defaultPlayStoreUrl);
    });
  });

  group('admin verification is reversible (§13/§14)', () {
    test('an explicit revoke removes the badge from an approved profile', () {
      final approved = _profile(status: AppConstants.profileApproved);
      expect(approved.isProfileVerified, isTrue);

      final revoked = approved.copyWith(profileVerified: false);
      expect(revoked.isProfileVerified, isFalse);
      // Nothing else moved: the account is untouched and the profile is still
      // approved and active.
      expect(revoked.status, AppConstants.profileApproved);
      expect(revoked.isActive, approved.isActive);
      expect(revoked.id, approved.id);
    });

    test('verify → revoke → verify again is a normal cycle', () {
      var p = _profile(status: AppConstants.profileApproved);
      p = p.copyWith(profileVerified: false);
      expect(p.isProfileVerified, isFalse);
      p = p.copyWith(profileVerified: true);
      expect(p.isProfileVerified, isTrue);
      p = p.copyWith(profileVerified: false);
      expect(p.isProfileVerified, isFalse);
    });

    test('profiles from before the feature keep their badge', () {
      // No explicit decision recorded → the approval status still decides, so
      // shipping this cannot silently un-verify everyone.
      final legacy = _profile(status: AppConstants.profileApproved);
      expect(legacy.profileVerified, isNull);
      expect(legacy.isProfileVerified, isTrue);

      final pending = _profile(status: AppConstants.profilePending);
      expect(pending.isProfileVerified, isFalse);
    });

    test('an explicit verify overrides a non-approved status', () {
      final p = _profile(status: AppConstants.profilePending)
          .copyWith(profileVerified: true);
      expect(p.isProfileVerified, isTrue);
    });
  });
}
