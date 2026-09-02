// Renders the real Horoscope Request screen for a signed-in MEMBER and pins
// the behaviour the redesign is judged on (spec §1, §2, §3, §5A):
//
//   • Person 1 opens ALREADY FILLED from the profile, with no "Use my profile
//     details" button anywhere;
//   • the gender is stated, not asked, and captioned with where it came from;
//   • a single Clear empties Person 1 so somebody else can be entered;
//   • Person 2 offers neither action, and its gender is Person 1's opposite;
//   • the final CTA asks for ₹199 and the sample is reachable before paying;
//   • all of the above builds in Tamil on a narrow phone without overflowing.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/auth_provider.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';
import 'package:jothida_matrimony/screens/report/request_external_report_screen.dart';
import 'package:jothida_matrimony/screens/report/sample_compatibility_report_screen.dart';
import 'package:jothida_matrimony/widgets/report/horoscope_fee_card.dart';

ProfileModel _member({String gender = 'Male'}) => ProfileModel.fromMap({
      'id': 'me',
      'userId': 'me-uid',
      'name': 'Karthik Raja',
      'fullName': 'Karthik Raja',
      'gender': gender,
      'age': 29,
      'dateOfBirth': DateTime(1996, 3, 2).toIso8601String(),
      'city': 'Erode',
      'district': 'Erode',
      'state': 'Tamil Nadu',
      // NOTE: ProfileModel.fromMap reads 'horoscopeDetails' / 'contactDetails'
      // (the shapes the app actually stores) — not 'horoscope' / 'contact'.
      'horoscopeDetails': {
        'birthTime': '09:20 PM',
        'birthPlace': 'Erode, Erode, Tamil Nadu',
        'nakshatra': 'உத்திரம்',
        'rasi': 'கன்னி',
      },
      'contactDetails': {
        'contactPersonName': 'Karthik Raja',
        'mobileNumber': '9876543210',
      },
    });

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  required Locale locale,
  ProfileModel? profile,
  Size size = const Size(1080, 2400),
  double dpr = 3.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isGuestProvider.overrideWithValue(false),
        myProfileProvider
            .overrideWith((ref) => Stream<ProfileModel?>.value(profile)),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RequestExternalReportScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return AppLocalizations.delegate.load(locale);
}

void main() {
  testWidgets('Person 1 is pre-filled and there is no "use my profile" button',
      (tester) async {
    final l10n =
        await _pump(tester, locale: const Locale('en'), profile: _member());
    expect(tester.takeException(), isNull);

    // Already filled in — no button to press to make it happen (spec §1A).
    expect(find.text('Karthik Raja'), findsWidgets);
    expect(find.text(l10n.useMyProfileDetails), findsNothing);

    // One Clear action, and it is the simple one.
    expect(find.text(l10n.clearDetails), findsOneWidget);
    expect(find.text(l10n.clearAndEnterNew), findsNothing);
  });

  testWidgets('Person 1 gender is taken from the profile, not asked',
      (tester) async {
    final l10n =
        await _pump(tester, locale: const Locale('en'), profile: _member());

    expect(find.text(l10n.genderBasedOnProfile), findsOneWidget);
    expect(find.text('Male'), findsOneWidget);
    // …and the Bride/Groom mapping is already visible (spec §1E).
    expect(find.text(l10n.groomRole), findsOneWidget);
    // A read-only statement, not a picker.
    expect(find.text(l10n.genderPickForThisPerson), findsNothing);
  });

  testWidgets('a female member is mapped to the Bride', (tester) async {
    final l10n = await _pump(tester,
        locale: const Locale('en'), profile: _member(gender: 'Female'));
    expect(find.text('Female'), findsOneWidget);
    expect(find.text(l10n.brideRole), findsOneWidget);
  });

  testWidgets('Clear empties Person 1 and re-opens the gender question',
      (tester) async {
    final l10n =
        await _pump(tester, locale: const Locale('en'), profile: _member());

    await tester.tap(find.text(l10n.clearDetails));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.clearAll));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The profile's details are gone and it does not silently re-seed.
    expect(find.text('Karthik Raja'), findsNothing);
    // Gender is now the one thing that has to be asked (spec §1A).
    expect(find.text(l10n.genderPickForThisPerson), findsOneWidget);
    expect(find.text(l10n.genderBasedOnProfile), findsNothing);
    // Nothing left to clear.
    expect(find.text(l10n.clearDetails), findsNothing);
  });

  testWidgets('Person 2 has no profile action and an automatic gender',
      (tester) async {
    final l10n =
        await _pump(tester, locale: const Locale('en'), profile: _member());

    await tester.tap(find.text(l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text(l10n.personTwoDetails), findsOneWidget);
    // Neither action belongs on Person 2 — it is somebody else (spec §1C).
    expect(find.text(l10n.useMyProfileDetails), findsNothing);
    expect(find.text(l10n.clearDetails), findsNothing);
    // Opposite of Person 1 (Male), so Female → Bride (spec §1D/§1E).
    expect(find.text(l10n.genderAutoFromPersonOne), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text(l10n.brideRole), findsOneWidget);
  });

  testWidgets('the sample report is reachable before any payment',
      (tester) async {
    final l10n =
        await _pump(tester, locale: const Locale('en'), profile: _member());

    expect(find.text(l10n.viewSampleReport), findsOneWidget);
    await tester.tap(find.text(l10n.viewSampleReport));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.byType(SampleCompatibilityReportScreen), findsOneWidget);
    // Unmistakably a demo (spec §3A).
    expect(find.text(l10n.sampleReportBadge), findsWidgets);
    expect(find.text(l10n.sampleReportNotice), findsOneWidget);
  });

  testWidgets('the sample renders every section without overflowing in Tamil',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ta'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SampleCompatibilityReportScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('ta'));
    // Scroll the whole certificate: an overflow anywhere down the page throws.
    for (var i = 0; i < 14; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'scroll step $i');
    }
    expect(find.text(l10n.sampleReportFooterNotice), findsOneWidget);
  });

  testWidgets('the fee block states ₹199 in Tamil without overflowing',
      (tester) async {
    // The narrowest realistic phone in the longest language. Driving the whole
    // four-step form would mean scripting three native pickers; the risk this
    // guards is the PRICE BLOCK's layout, so it is rendered directly.
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ta'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const HoroscopeFeeCard(priceText: '₹199'),
              const SizedBox(height: 14),
              HoroscopeSamplePreviewCard(onView: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('ta'));
    expect(find.text(l10n.amountPayable), findsOneWidget);
    expect(find.text('₹199'), findsOneWidget);
    // The one-fee-for-two-people promise sits where the money is asked for.
    expect(find.text(l10n.oneRequestOneFeeNote), findsOneWidget);
    expect(find.text(l10n.viewSampleReport), findsOneWidget);
  });

  test('the pay CTA names the price in both languages', () async {
    for (final code in const ['en', 'ta']) {
      final l10n = await AppLocalizations.delegate.load(Locale(code));
      expect(l10n.payAndRequestReport('₹199'), contains('₹199'),
          reason: code);
    }
  });
}
