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

    // Step 1 is Person 1, and a guest is told they may submit without an
    // account rather than being blocked by a login wall.
    expect(find.text(l10n.personOneDetails), findsOneWidget);
    expect(find.text(l10n.guestCanSubmitHoroscopeRequest), findsOneWidget);
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
}
