// Diagnostic widget test for the Matches "profile book" card (DiscoverTab).
//
// Pumps the REAL DiscoverTab with one fully-populated profile and verifies the
// card content (name / education / profession) actually renders. If the card is
// blank because of a hidden build/layout exception, this test fails and prints
// the exact exception + stack.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/core/data/sample_profiles.dart';
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
        child: const MaterialApp(home: Scaffold(body: DiscoverTab())),
      ),
    );

    // Let the initState microtask (_load) and providers settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Surface any swallowed build/layout exception explicitly.
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'DiscoverTab threw while rendering: $ex');

    // Count badge proves the list rendered with one match.
    expect(find.textContaining('1 Match'), findsOneWidget);

    // The card content must be visible.
    expect(find.textContaining('Priya'), findsWidgets,
        reason: 'Name overlay missing from the card');
    expect(find.textContaining('M.Sc'), findsWidgets,
        reason: 'Education detail missing from the card');
    expect(find.textContaining('Software Engineer'), findsWidgets,
        reason: 'Profession badge missing from the card');
  });
}
