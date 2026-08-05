// Overflow regression tests for the redesigned premium surfaces.
//
// Both of these put long, translated labels inside FIXED halves of a row (the
// equal Reject / Accept Interest buttons) or inside a constrained dialog card,
// which is exactly the shape that overflowed elsewhere in this app. They are
// pumped at small-phone widths in BOTH languages and fail on any RenderFlex
// overflow.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/widgets/interest/pending_interest_card.dart';

/// The narrowest devices we support (logical px).
const _widths = <double>[320, 360, 411];

Widget _host(Widget child, Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );

Future<void> _expectNoOverflow(
  WidgetTester tester,
  Widget Function() build,
) async {
  for (final locale in const [Locale('en'), Locale('ta')]) {
    for (final width in _widths) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(build(), locale));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Layout overflow at ${width}px in "${locale.languageCode}"',
      );
    }
  }
}

void main() {
  testWidgets('Pending interest card never overflows', (tester) async {
    await _expectNoOverflow(
      tester,
      () => PendingInterestCard(
        name: 'Priyadharshini Balasubramanian',
        onAccept: () async {},
        onReject: () async {},
      ),
    );
  });

  testWidgets('Pending interest card never overflows (compact)',
      (tester) async {
    await _expectNoOverflow(
      tester,
      () => PendingInterestCard(
        name: 'Priyadharshini Balasubramanian',
        compact: true,
        onAccept: () async {},
        onReject: () async {},
      ),
    );
  });

  testWidgets('Reject and Accept Interest are equal-width', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      PendingInterestCard(
        name: 'Anitha',
        onAccept: () async {},
        onReject: () async {},
      ),
      const Locale('en'),
    ));
    await tester.pump();

    final reject = tester.getRect(find.widgetWithText(OutlinedButton, 'Reject'));
    final accept =
        tester.getRect(find.widgetWithText(FilledButton, 'Accept Interest'));
    expect(accept.width, closeTo(reject.width, 0.5));
    expect(accept.height, closeTo(reject.height, 0.5));
  });

}
