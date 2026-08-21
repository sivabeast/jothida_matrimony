// Tests for the ONE Horoscope Compatibility Report page.
//
// The separate "Horoscope Match Result" page was merged into this screen, so
// ONE page must carry: the free porutham counts and both lists, "What the
// report includes" ONCE, "Service Details" ONCE, and the paid CTA below them.
// It must never show a rating-style label ("Average Match", "Good Match", …)
// or any percentage.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/data/sample_profiles.dart';
import 'package:jothida_matrimony/core/services/porutham_match.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/models/astrologer_request_model.dart';
import 'package:jothida_matrimony/models/astrology_service_config.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/astrology_config_provider.dart';
import 'package:jothida_matrimony/providers/match_analysis_provider.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';
import 'package:jothida_matrimony/screens/astrology/horoscope_report_service_screen.dart';

/// A bride/groom pairing whose poruthams actually resolve, so the page renders
/// real counts rather than the "not enough data" notice.
({ProfileModel me, ProfileModel other, PoruthamMatchResult result}) _pair() {
  final profiles = sampleProfiles();
  for (final me in profiles) {
    for (final other in profiles) {
      if (me.id == other.id) continue;
      final r = computePorutham(me, other);
      if (r != null) return (me: me, other: other, result: r);
    }
  }
  fail('no sample pairing produced a porutham result');
}

Widget _host(ProfileModel me, ProfileModel other) => ProviderScope(
      overrides: [
        myProfileProvider.overrideWith((ref) => Stream.value(me)),
        profileByUserIdProvider(other.userId).overrideWith((ref) async => other),
        // No paid request exists for this pair → the CTA is offered.
        myMatchAnalysisRequestsProvider.overrideWith(
            (ref) => Stream.value(const <AstrologerRequestModel>[])),
        astrologyServiceConfigProvider.overrideWith(
            (ref) => Stream.value(AstrologyServiceConfig.defaults)),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: HoroscopeReportServiceScreen(otherUserId: other.userId),
      ),
    );

void main() {
  // The page is a ListView, so give the test a tall viewport — otherwise the
  // lower sections simply are not built and the assertions test nothing.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views.first;
    view.physicalSize = const Size(420, 4000);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('shows the free porutham counts, both lists and the paid CTA',
      (tester) async {
    final p = _pair();
    await tester.pumpWidget(_host(p.me, p.other));
    await tester.pumpAndSettle();

    // The total and both counts come from the real calculation.
    expect(find.text('${p.result.totalCount} Poruthams'), findsOneWidget);
    expect(find.text('${p.result.matchedCount}'), findsWidgets);
    expect(find.text('Matched'), findsOneWidget);
    expect(find.text('Not Matched'), findsOneWidget);

    // Every porutham is listed by name under one heading or the other, and the
    // headings carry the same counts as the tiles above.
    for (final item in p.result.poruthams) {
      expect(find.text(item.name), findsOneWidget,
          reason: '${item.name} missing from the breakdown');
    }
    if (p.result.matching.isNotEmpty) {
      expect(find.text('Matching Poruthams (${p.result.matching.length})'),
          findsOneWidget);
    }
    if (p.result.nonMatching.isNotEmpty) {
      expect(
          find.text(
              'Not Matching / Needs Attention (${p.result.nonMatching.length})'),
          findsOneWidget);
    }

    // The paid CTA names the ₹200 charge explicitly and sits below the free
    // result (spec §8).
    expect(find.textContaining('Request Report'), findsOneWidget);
    expect(find.textContaining('₹200'), findsWidgets);
  });

  testWidgets('service information appears exactly once — no duplicate pages',
      (tester) async {
    final p = _pair();
    await tester.pumpWidget(_host(p.me, p.other));
    await tester.pumpAndSettle();

    // Spec §5: the same information must never be repeated. One page, one
    // "What the report includes", one "Service Details".
    expect(find.text('What the report includes'), findsOneWidget);
    expect(find.text('Service Details'), findsOneWidget);
    expect(find.text('Service Charge'), findsOneWidget);
    for (final item in AstrologyServiceConfig.defaults.reportIncludes) {
      expect(find.text(item), findsOneWidget,
          reason: '"$item" must be listed once, not on two screens');
    }
  });

  testWidgets('never shows a rating label or a percentage', (tester) async {
    final p = _pair();
    await tester.pumpWidget(_host(p.me, p.other));
    await tester.pumpAndSettle();

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' | ');

    for (final banned in const [
      'Excellent Match',
      'Good Match',
      'Average Match',
      'Poor Match',
      'Low Match',
      '%',
    ]) {
      expect(texts.contains(banned), isFalse,
          reason: 'the result page must not show "$banned"');
    }
  });
}
