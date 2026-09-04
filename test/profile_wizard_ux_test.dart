// The profile-creation redesign, pinned where it can actually regress.
//
// Three behaviours that are invisible to a unit test and easy to undo by
// accident:
//
//   • the children question appears only for someone who has been married;
//   • an optional step's Skip lives at the BOTTOM, next to Continue, and a
//     mandatory step has no Skip at all;
//   • the multi-select sheet confirms with a real full-width button.
//
// (The place picker's one-tap selection is pinned in
// bookings_badges_and_places_test.dart, alongside the rest of that widget.)

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';
import 'package:jothida_matrimony/screens/profile/steps/step_basic.dart';
import 'package:jothida_matrimony/widgets/common/searchable_multi_select_field.dart';
import 'package:jothida_matrimony/widgets/common/step_actions.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

/// Pumps Basic Details with [maritalStatus] already chosen, exactly as the
/// wizard does when the step is re-entered or an existing profile is edited.
Future<AppLocalizations> _pumpBasic(
  WidgetTester tester,
  String? maritalStatus,
) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (maritalStatus != null) {
    container
        .read(profileCreationProvider.notifier)
        .updateData({'maritalStatus': maritalStatus});
  }
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: _app(StepBasic(onNext: () {})),
  ));
  await tester.pump(const Duration(milliseconds: 200));
  return AppLocalizations.delegate.load(const Locale('en'));
}

void main() {
  group('children are asked about only where the question makes sense', () {
    testWidgets('never married → the question is absent, not merely ignored',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final l10n = await _pumpBasic(tester, 'Never Married');
      expect(find.textContaining(l10n.haveChildren), findsNothing);
      expect(find.textContaining(l10n.numberOfChildren), findsNothing);
      expect(find.textContaining(l10n.childrenLivingStatus), findsNothing);
    });

    testWidgets('married → the question is on the form', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final l10n = await _pumpBasic(tester, 'Married');
      expect(find.textContaining(l10n.haveChildren), findsOneWidget);
      // The count only follows a "yes", so it is not there yet.
      expect(find.textContaining(l10n.numberOfChildren), findsNothing);
    });

    testWidgets('a legacy stored status still asks', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // 'Widow' normalises to 'Widowed' — the question must survive the
      // rename, or every profile written by an older build loses it.
      final l10n = await _pumpBasic(tester, 'Widow');
      expect(find.textContaining(l10n.haveChildren), findsOneWidget);
    });

    testWidgets('nothing chosen yet asks nothing', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final l10n = await _pumpBasic(tester, null);
      expect(find.textContaining(l10n.haveChildren), findsNothing);
    });

    testWidgets('answering yes reveals the count and the living status',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final l10n = await _pumpBasic(tester, 'Divorced');
      await tester.ensureVisible(find.text(l10n.yes));
      await tester.tap(find.text(l10n.yes));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining(l10n.numberOfChildren), findsOneWidget);
      expect(find.textContaining(l10n.childrenLivingStatus), findsOneWidget);

      // …and answering no puts them away again.
      await tester.ensureVisible(find.text(l10n.no));
      await tester.tap(find.text(l10n.no));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(l10n.numberOfChildren), findsNothing);
      expect(find.textContaining(l10n.childrenLivingStatus), findsNothing);
    });
  });

  group('optional steps carry Skip at the bottom, never in the app bar', () {
    testWidgets('a skippable step shows Continue AND Skip', (tester) async {
      var skipped = false;
      await tester.pumpWidget(_app(ProviderScope(
        child: StepActions(onContinue: () {}, onSkip: () => skipped = true),
      )));
      await tester.pump();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.continueLabel), findsOneWidget);
      expect(find.text(l10n.skip), findsOneWidget);

      await tester.tap(find.text(l10n.skip));
      await tester.pump();
      expect(skipped, isTrue);
    });

    testWidgets('a mandatory step shows Continue alone', (tester) async {
      await tester.pumpWidget(_app(ProviderScope(
        child: StepActions(onContinue: () {}),
      )));
      await tester.pump();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.continueLabel), findsOneWidget);
      expect(find.text(l10n.skip), findsNothing);
    });
  });

  group('the multi-select sheet confirms with a real button', () {
    testWidgets('Done is a full-width filled button at the bottom',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      var picked = <String>[];
      await tester.pumpWidget(_app(SearchableMultiSelectField(
        label: 'Course / Degree',
        items: const ['B.E.', 'B.Sc.', 'M.A.'],
        selected: const [],
        isRequired: true,
        onChanged: (v) => picked = v,
      )));
      await tester.pump();

      // The asterisk marks it as required, right on the field label.
      expect(find.text('Course / Degree *'), findsOneWidget);

      await tester.tap(find.byType(InputDecorator).first);
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // An ElevatedButton — not the old cramped TextButton in the header.
      final done = find.widgetWithText(ElevatedButton, l10n.done);
      expect(done, findsOneWidget);
      final size = tester.getSize(done);
      expect(size.height, greaterThanOrEqualTo(48.0));
      // Full width, not a cramped label tucked into a corner: it spans the
      // sheet apart from its side padding.
      final sheetWidth = tester.getSize(find.byType(MaterialApp)).width;
      expect(size.width, greaterThan(sheetWidth - 40));

      await tester.tap(find.text('B.Sc.'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.doneCount(1)));
      await tester.pumpAndSettle();

      expect(picked, ['B.Sc.']);
    });
  });
}
