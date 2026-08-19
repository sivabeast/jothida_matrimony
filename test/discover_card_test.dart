// Diagnostic widget test for the Matches "profile book" card (DiscoverTab).
//
// Pumps the REAL DiscoverTab with one fully-populated profile and verifies the
// card content (name / education / profession) actually renders. If the card is
// blank because of a hidden build/layout exception, this test fails and prints
// the exact exception + stack.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/data/sample_profiles.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/models/interest_model.dart';
import 'package:jothida_matrimony/providers/interest_provider.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';
import 'package:jothida_matrimony/screens/home/tabs/discover_tab.dart';

class _FakeDiscoverNotifier extends DiscoverNotifier {
  _FakeDiscoverNotifier(this._state);
  final DiscoverState _state;
  @override
  DiscoverState build() => _state;
  @override
  Future<void> load() async {}
  @override
  Future<void> loadMore() async {}
  @override
  Future<void> applyFilters(MatchFilters filters) async {}
}

void main() {
  testWidgets('Matches card renders the profile content', (tester) async {
    final all = sampleProfiles();
    final me = all.firstWhere((p) => p.gender == 'Male');
    final her = all.firstWhere((p) => p.gender == 'Female');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discoverProvider.overrideWith(
            () => _FakeDiscoverNotifier(
              DiscoverState(profiles: [her], isLoading: false, hasMore: false),
            ),
          ),
          myProfileProvider.overrideWith((ref) => Stream.value(me)),
          sentInterestsProvider
              .overrideWith((ref) => Stream.value(const <InterestModel>[])),
          receivedInterestsProvider
              .overrideWith((ref) => Stream.value(const <InterestModel>[])),
        ],
        // The DiscoverTab is fully localized now, so the test app must provide
        // the l10n delegates (context.l10n asserts otherwise).
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DiscoverTab()),
        ),
      ),
    );

    // Let the initState microtask (_load) and providers settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Surface any swallowed build/layout exception explicitly.
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'DiscoverTab threw while rendering: $ex');

    // The minimal Matches feed has NO title/count/filter header row — it begins
    // straight at the first summary card. The card content must be visible.
    expect(find.textContaining('Priya'), findsWidgets,
        reason: 'Name missing from the summary card');
    expect(find.textContaining('M.Sc'), findsWidgets,
        reason: 'Education detail missing from the summary card');
    expect(find.textContaining('Software Engineer'), findsWidgets,
        reason: 'Profession detail missing from the summary card');

    // The two summary actions must be present.
    expect(find.text('Express Interest'), findsOneWidget,
        reason: 'Express Interest action missing from the summary card');
    expect(find.text('View Profile'), findsOneWidget,
        reason: 'View Profile action missing from the summary card');
  });

  // The "Matches your Nakshatra" chip now sits on the SAME row as the name.
  // A Row of two unbounded children is exactly the shape that overflows on a
  // narrow phone, so pin it at the smallest widths we support, in both
  // languages (the Tamil label is much longer than the English one).
  testWidgets('Matches card name row never overflows', (tester) async {
    final all = sampleProfiles();
    final me = all.firstWhere((p) => p.gender == 'Male');
    final her = all.firstWhere((p) => p.gender == 'Female');

    for (final locale in const [Locale('en'), Locale('ta')]) {
      for (final width in const <double>[320, 360, 411]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoverProvider.overrideWith(
                () => _FakeDiscoverNotifier(
                  DiscoverState(
                      profiles: [her], isLoading: false, hasMore: false),
                ),
              ),
              myProfileProvider.overrideWith((ref) => Stream.value(me)),
              sentInterestsProvider
                  .overrideWith((ref) => Stream.value(const <InterestModel>[])),
              receivedInterestsProvider
                  .overrideWith((ref) => Stream.value(const <InterestModel>[])),
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
              home: const Scaffold(body: DiscoverTab()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull,
            reason: 'Matches card overflowed at ${width}px in '
                '"${locale.languageCode}"');
      }
    }
  });
}
