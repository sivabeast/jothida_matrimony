// Overflow regression tests for the Horoscope UI.
//
// The Profile Creation → Horoscope page reported "RIGHT OVERFLOWED BY 4.5
// PIXELS": the Calculated Horoscope card's header was a Row holding a Spacer
// between two UNBOUNDED Texts, so the translated (longer) labels no longer fit
// on a small phone. These tests pump the affected widgets at small-phone widths
// in BOTH languages and fail if Flutter reports any RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/screens/profile/steps/step3_horoscope.dart';
import 'package:jothida_matrimony/widgets/common/dual_range_slider_field.dart';
import 'package:jothida_matrimony/widgets/common/horoscope_documents_view.dart';

/// The narrowest devices we support (logical px). 320 covers small Androids
/// such as the Galaxy Fold cover screen; 360 is the common budget-phone width.
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
        // Same padding the wizard steps use, so the available width matches
        // what the real page gives these widgets.
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );

/// Pumps [child] at every small width in every supported locale and asserts
/// Flutter recorded no layout overflow.
Future<void> _expectNoOverflow(
  WidgetTester tester,
  Widget Function() build,
) async {
  for (final locale in const [Locale('en'), Locale('ta')]) {
    for (final width in _widths) {
      tester.view.physicalSize = Size(width, 800);
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
  testWidgets('Calculated Horoscope card never overflows', (tester) async {
    await _expectNoOverflow(
      tester,
      () => const CalculatedHoroscopeCard(
        rasi: 'மேஷம்',
        nakshatra: 'அஸ்வினி',
        lagnam: 'கடகம்',
      ),
    );
  });

  testWidgets('Horoscope documents view never overflows', (tester) async {
    await _expectNoOverflow(
      tester,
      () => const HoroscopeDocumentsView(
        imageUrls: [
          'https://example.com/a.jpg',
          'https://example.com/b.jpg',
          'https://example.com/c.jpg',
        ],
        pdfUrls: [
          'https://example.com/a.pdf',
          'https://example.com/b.pdf',
        ],
      ),
    );
  });

  testWidgets('Horoscope documents empty state never overflows',
      (tester) async {
    await _expectNoOverflow(
      tester,
      () => const HoroscopeDocumentsView(imageUrls: [], pdfUrls: []),
    );
  });

  testWidgets('Dual range slider never overflows', (tester) async {
    await _expectNoOverflow(
      tester,
      () => DualRangeSliderField(
        label: 'Height Range / உயர வரம்பு',
        min: 0,
        max: 23,
        startValue: 4,
        endValue: 20,
        startCaption: 'Minimum Height / குறைந்தபட்ச உயரம்',
        endCaption: 'Maximum Height / அதிகபட்ச உயரம்',
        formatRange: (a, b) => "4'10\" – 6'2\" வயது",
        onChanged: (_, __) {},
      ),
    );
  });
}
