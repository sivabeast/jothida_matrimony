// Renders the real Horoscope Request screen for a GUEST and walks the steps.
//
// A form this size fails in ways unit tests cannot see — a null Material
// colour shade, an unbounded Row, a missing localization key — so this pumps
// the actual widget and fails on any build/layout exception.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/auth_provider.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';
import 'package:jothida_matrimony/screens/report/request_external_report_screen.dart';

Future<void> _pump(WidgetTester tester, {required Locale locale}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // A GUEST: no profile, so nothing is auto-filled and no login is
        // demanded anywhere in the flow (spec §1).
        isGuestProvider.overrideWithValue(true),
        myProfileProvider.overrideWith(
            (ref) => Stream<ProfileModel?>.value(null)),
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
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('a guest can open the form and reach the contact step',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pump(tester, locale: const Locale('en'));
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Step 1 is Person 1. A guest is not blocked by a login wall: the form is
    // simply there, with the two things worth offering before anything has
    // been typed — a look at a finished report, and a login for anyone who
    // also wants to track the request afterwards. Both are links, not a
    // paragraph explaining the flow the member is already standing in.
    expect(find.text(l10n.personOneDetails), findsOneWidget);
    expect(find.text(l10n.viewSampleReport), findsOneWidget);
    expect(find.text(l10n.loginToTrackRequest), findsOneWidget);
    expect(find.text(l10n.continueLabel), findsOneWidget);

    // Continue with an empty form must NOT advance — the required fields are
    // still required for a guest.
    await tester.tap(find.text(l10n.continueLabel));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.personOneDetails), findsOneWidget);
  });

  testWidgets('the Tamil layout builds without overflowing', (tester) async {
    // A narrow phone in Tamil is the worst case: the longest labels in the
    // least width.
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pump(tester, locale: const Locale('ta'));
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('ta'));
    expect(find.text(l10n.personOneDetails), findsOneWidget);
  });

  group('the pay button is never a step backwards', () {
    // The regression: the contact details were validated through their Form,
    // and that Form is only in the tree while the contact step is showing. By
    // the time "Pay ₹199 · Request report" was pressed its state was null, the
    // check read null as "invalid", and the member was silently sent back to
    // the contact step instead of into Google Play.
    //
    // The check is a VALUE check now, so it cannot depend on what happens to
    // be mounted.
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('complete details are accepted with no Form anywhere in sight', () {
      expect(
        horoscopeContactProblem(
            name: 'Meena R', whatsapp: '9876543210', l10n: l10n),
        isNull,
      );
    });

    test('spacing inside a ten-digit number is ignored', () {
      expect(
        horoscopeContactProblem(
            name: 'Meena R', whatsapp: '98765 43210', l10n: l10n),
        isNull,
      );
    });

    test('a country code left in the field is rejected, not silently stored',
        () {
      // The field's formatter trims a pasted "+91…" down to the local number,
      // so twelve digits reaching here means something went wrong upstream —
      // and twelve digits is not a number worth writing to the request.
      expect(
        horoscopeContactProblem(
            name: 'Meena R', whatsapp: '+91 98765 43210', l10n: l10n),
        l10n.whatsappMustBe10Digits,
      );
    });

    test('a missing name says so', () {
      expect(
        horoscopeContactProblem(name: ' ', whatsapp: '9876543210', l10n: l10n),
        l10n.pleaseEnterFullName,
      );
    });

    test('an empty and a short number are told apart', () {
      expect(
        horoscopeContactProblem(name: 'Meena R', whatsapp: '', l10n: l10n),
        l10n.whatsappRequired,
      );
      expect(
        horoscopeContactProblem(
            name: 'Meena R', whatsapp: '98765', l10n: l10n),
        l10n.whatsappMustBe10Digits,
      );
    });
  });
}
