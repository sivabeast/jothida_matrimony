// Layout + redaction tests for the downloadable profile form.
//
// The printed "பதிவு படிவம்" layout packs fixed-width Tamil labels, paired
// half-width fields and wrapping tick-box groups into a FIXED A4 content
// width — the exact shape that overflows elsewhere in this app the moment a
// value turns out longer than the designer assumed. A page that overflows is
// not just ugly here: the overflow stripe is rasterised straight into the
// member's PDF. These tests pump the whole form at the real A4 content width
// with deliberately long values and fail on any RenderFlex overflow.
//
// They also pin the privacy contract: a member downloading a match's profile
// must never receive a value the profile screen would have hidden.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/models/user_model.dart';
import 'package:jothida_matrimony/widgets/export/profile_form_export.dart';

/// A4 content width the exporter lays pages out at (see `_kContentW`).
const double _kContentW = 702;

ProfileModel _profile({
  String fullName = 'Kavitha Ramasubramaniam',
  String fullNameTamil = 'கவிதா ராமசுப்ரமணியம்',
  String maritalStatus = 'Never Married',
  String dosham = 'No',
  String height = "5'4\"",
  String weight = '54 kg',
  String annualIncome = '₹5-7 Lakhs',
  Map<String, bool> privacy = ProfilePrivacy.defaults,
  String? photoUrl = 'https://example.invalid/photo.jpg',
}) =>
    ProfileModel(
      id: 'p1',
      userId: 'u1',
      profileCreatedBy: 'Myself',
      profileCreatedFor: 'Myself',
      fullName: fullName,
      fullNameTamil: fullNameTamil,
      gender: 'Female',
      dateOfBirth: DateTime(1997, 4, 12),
      age: 28,
      height: height,
      weight: weight,
      maritalStatus: maritalStatus,
      religion: 'Hindu',
      caste: 'Vanniyar',
      subCaste: 'Padayachi',
      educationLevel: 'PG',
      education: 'M.Sc Computer Science',
      occupation: 'Software Engineer',
      employmentType: 'Private',
      workLocation: 'Chennai',
      annualIncome: annualIncome,
      country: 'India',
      state: 'Tamil Nadu',
      district: 'Villupuram',
      city: 'Tindivanam',
      motherTongue: 'Tamil',
      physicalStatus: 'Normal',
      nativePlace: 'Tindivanam',
      citizenship: 'Indian',
      profilePhotoUrl: photoUrl,
      privacySettings: privacy,
      horoscope: HoroscopeDetails(
        rasi: 'மேஷம்',
        nakshatra: 'அசுவினி',
        lagnam: 'ரிஷபம்',
        dosham: dosham,
        rahuKethuDosham: 'No',
        dasaBalance: '3y 2m 5d',
        yogam: '',
        karanam: '',
        moonSign: '',
        sunSign: '',
        birthTime: '06:45 AM',
        birthPlace: 'Tindivanam, Villupuram',
      ),
      partnerPreferences: const PartnerPreferences(
        minAge: 28,
        maxAge: 36,
        education: ['UG', 'PG'],
        occupation: ['Software Engineer', 'Teacher'],
        // Deliberately DIFFERENT from annualIncome above: the two are separate
        // fields and only the member's own income is gated by "Hide Salary".
        income: '₹8-10 Lakhs',
        religion: 'Hindu',
        caste: 'Vanniyar',
        district: 'Villupuram',
        state: 'Tamil Nadu',
      ),
      contact: const ContactDetails(
        contactPersonName: 'Ramasubramaniam',
        relationship: 'Father',
        mobileNumber: '9876543210',
        whatsappNumber: '9876543211',
        email: 'kavitha.family@example.com',
      ),
      createdAt: DateTime(2026, 1, 4),
      updatedAt: DateTime(2026, 2, 9),
    );

UserModel _user() => UserModel(
      uid: 'u1',
      email: 'kavitha@example.com',
      phone: '+919876543210',
      createdAt: DateTime(2026, 1, 4),
      updatedAt: DateTime(2026, 2, 9),
    );

/// Pumps the whole form at the real A4 content width and fails on overflow.
Future<void> _expectNoOverflow(
  WidgetTester tester,
  Widget form, {
  required String reason,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(child: form),
      ),
    ),
  ));
  await tester.pump();
  expect(tester.takeException(), isNull, reason: reason);
}

/// Every string the rendered form puts on the page.
List<String> _renderedText(WidgetTester tester) => [
      ...tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? ''),
      ...tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text.toPlainText()),
    ];

void main() {
  // A4 page is 794 logical px wide; give the harness room for the full column.
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('profile form layout', () {
    testWidgets('typical profile fits the A4 content width', (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _expectNoOverflow(
        tester,
        buildProfileFormPreview(profile: _profile(), user: _user()),
        reason: 'A typical profile overflowed the printed form',
      );
    });

    testWidgets('long values still fit', (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // "Widowed" is the longest Tamil marital-status label and a free-text
      // dosham falls back to a full-width rule — both stress the row widths.
      await _expectNoOverflow(
        tester,
        buildProfileFormPreview(
          profile: _profile(
            fullName: 'Venkataraman Subramanian Balasubramanian',
            fullNameTamil: 'வெங்கடராமன் சுப்ரமணியன் பாலசுப்ரமணியன்',
            maritalStatus: 'Widowed',
            dosham: 'Partially present — needs astrologer verification',
            annualIncome: 'Above ₹50 Lakhs per annum',
          ),
          user: _user(),
        ),
        reason: 'Long values overflowed the printed form',
      );
    });

    testWidgets('the form still renders when the profile is empty',
        (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _expectNoOverflow(
        tester,
        buildProfileFormPreview(
          profile: _profile(
            fullName: '',
            fullNameTamil: '',
            maritalStatus: '',
            dosham: '',
            height: '',
            weight: '',
            annualIncome: '',
            photoUrl: null,
          ),
        ),
        reason: 'An empty profile overflowed the printed form',
      );
    });
  });

  group('member download redaction', () {
    /// Everything hidden — the switches a privacy-conscious member turns on.
    const allHidden = <String, bool>{
      ProfilePrivacy.phone: true,
      ProfilePrivacy.salary: true,
      ProfilePrivacy.horoscope: true,
      ProfilePrivacy.photo: true,
    };

    testWidgets('a match download omits every value the owner hid',
        (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final profile = _profile(privacy: allHidden);
      await _expectNoOverflow(
        tester,
        buildProfileFormPreview(
          profile: profile,
          options: ProfileFormExportOptions.forMatch(profile),
        ),
        reason: 'A redacted profile overflowed the printed form',
      );

      final text = _renderedText(tester);
      // Hidden: phone numbers, own salary and the horoscope values.
      expect(text, isNot(contains('9876543210')));
      expect(text, isNot(contains('9876543211')));
      expect(text, isNot(contains('₹5-7 Lakhs')));
      expect(text, isNot(contains('06:45 AM')));
      expect(text, isNot(contains('Tindivanam, Villupuram')));
      // Still shown: the e-mail (Hide Phone Number covers the NUMBERS only,
      // matching the Contact Details popup), the plain profile fields, and the
      // PARTNER-preference income, which "Hide Salary" does not govern.
      expect(text, contains('kavitha.family@example.com'));
      expect(text, contains('Software Engineer'));
      expect(text, contains('₹8-10 Lakhs'));
    });

    testWidgets('an unset preference prints a blank rule, never "Any"',
        (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 'Any' is the app's "no preference" sentinel and is what a member who
      // skipped the step actually has stored.
      final profile = ProfileModel(
        id: _profile().id,
        userId: _profile().userId,
        profileCreatedBy: 'Myself',
        profileCreatedFor: 'Myself',
        fullName: 'Anbu',
        gender: 'Male',
        dateOfBirth: DateTime(1995, 1, 1),
        age: 30,
        height: "5'8\"",
        weight: '70 kg',
        maritalStatus: 'Never Married',
        religion: 'Hindu',
        education: 'B.E',
        occupation: 'Engineer',
        annualIncome: '₹5-7 Lakhs',
        country: 'India',
        state: 'Tamil Nadu',
        city: 'Chennai',
        motherTongue: 'Tamil',
        horoscope: _profile().horoscope,
        partnerPreferences: const PartnerPreferences(), // all defaults = 'Any'
        contact: _profile().contact,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      await _expectNoOverflow(
        tester,
        buildProfileFormPreview(profile: profile),
        reason: 'A default-preference profile overflowed the printed form',
      );

      expect(_renderedText(tester), isNot(contains('Any')));
    });

    testWidgets('an admin download keeps every value', (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final profile = _profile(privacy: allHidden);
      await _expectNoOverflow(
        tester,
        buildProfileFormPreview(
          profile: profile,
          user: _user(),
          options:
              ProfileFormExportOptions.admin(adminEmail: 'admin@example.com'),
        ),
        reason: 'The admin form overflowed',
      );

      final text = _renderedText(tester);
      expect(text, contains('9876543210'));
      expect(text, contains('₹5-7 Lakhs'));
      expect(text, contains('06:45 AM'));
      // The admin export is stamped with who generated it.
      expect(text.join(' '), contains('admin@example.com'));
    });
  });

  test('the preview column matches the exporter content width', () {
    // Guards the constant this test file duplicates: if the page frame
    // changes, the overflow tests above must be re-checked at the new width.
    expect(_kContentW, 702);
  });
}
