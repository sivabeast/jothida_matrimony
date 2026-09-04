// The Reports page leads with WHO each report is about.
//
// The card used to open with a generic sparkle icon and a name pulled straight
// off the request, which is how a placeholder second-person name ended up
// being the most prominent thing on the page. It now shows the other person's
// live profile photo and current name, falling back to the stored name and a
// gender-appropriate avatar — never a broken image — when there is no profile
// to read.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/models/astrologer_request_model.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/match_analysis_provider.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';
import 'package:jothida_matrimony/screens/home/tabs/reports_tab.dart';
import 'package:jothida_matrimony/widgets/common/network_photo.dart';

ProfileModel _profile({
  required String id,
  required String name,
  String photo = '',
}) =>
    ProfileModel.fromMap({
      'id': id,
      'userId': 'uid-$id',
      // fromMap reads the WIZARD shape: `name`, and the photo off `photos`.
      'name': name,
      'photos': photo.isEmpty ? const <String>[] : <String>[photo],
      'city': 'Madurai',
      'state': 'Tamil Nadu',
    });

/// An internal compatibility report between two registered members.
AstrologerRequestModel _internalReport({
  required AstrologerRequestStatus status,
}) =>
    AstrologerRequestModel(
      id: 'REQ-1',
      astrologerId: '',
      astrologerName: 'Office',
      // Already assigned, so the tab's "stuck request" self-heal leaves it
      // alone instead of reaching for the live service.
      astrologerEmail: 'office@example.test',
      userId: 'uid-mine',
      userName: 'Arun K',
      type: AstrologerRequestType.matching,
      status: status,
      message: '',
      amount: 199,
      paid: true,
      profileAId: 'mine',
      profileAName: 'Arun K',
      profileBId: 'theirs',
      profileBName: 'Stale Name',
      createdAt: DateTime(2026, 9, 4),
      completedAt: status == AstrologerRequestStatus.completed
          ? DateTime(2026, 9, 6)
          : null,
    );

/// An EXTERNAL request: the second person is not on the app at all, so there is
/// no profile behind them.
AstrologerRequestModel _externalReport() => AstrologerRequestModel(
      id: 'REQ-2',
      astrologerId: '',
      astrologerName: 'Office',
      astrologerEmail: 'office@example.test',
      userId: 'uid-mine',
      userName: 'Arun K',
      type: AstrologerRequestType.matching,
      status: AstrologerRequestStatus.pending,
      message: '',
      amount: 199,
      paid: true,
      profileAName: 'Arun K',
      profileBName: 'Kavitha S',
      externalRequest: {
        'requester': {'name': 'Arun K', 'gender': 'Male'},
        'other': {'name': 'Kavitha S', 'gender': 'Female'},
      },
      createdAt: DateTime(2026, 9, 4),
    );

Future<AppLocalizations> _pump(
  WidgetTester tester,
  List<AstrologerRequestModel> reports, {
  ProfileModel? partner,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      myMatchAnalysisRequestsProvider.overrideWith((ref) =>
          Stream<List<AstrologerRequestModel>>.value(reports)),
      myProfileProvider.overrideWith((ref) => Stream<ProfileModel?>.value(
          _profile(id: 'mine', name: 'Arun K'))),
      profileByIdProvider.overrideWith(
          (ref, id) => Stream<ProfileModel?>.value(partner)),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ReportsTab()),
    ),
  ));
  // Two frames: the first builds the list, the second lets each card's
  // partner-profile stream deliver.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return AppLocalizations.delegate.load(const Locale('en'));
}

void main() {
  testWidgets('the card shows the partner\'s LIVE name and photo',
      (tester) async {
    final l10n = await _pump(
      tester,
      [_internalReport(status: AstrologerRequestStatus.pending)],
      partner: _profile(
          id: 'theirs',
          name: 'Priya',
          photo: 'https://example.test/priya.jpg'),
    );
    expect(tester.takeException(), isNull);

    // The current profile name wins over the one frozen on the request.
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Stale Name'), findsNothing);
    // …and the viewer's OWN name is never what the card is titled with.
    expect(find.text('Arun K'), findsNothing);

    // A real photo, at a size you can actually recognise someone in.
    final photo = tester.widget<NetworkPhoto>(find.byType(NetworkPhoto).first);
    expect(photo.url, 'https://example.test/priya.jpg');
    expect(photo.width, greaterThanOrEqualTo(64.0));

    // Under analysis → the status and the details action, not "View Report".
    expect(find.text(l10n.statusUnderAnalysis), findsOneWidget);
    expect(find.text(l10n.viewDetails), findsOneWidget);
    expect(find.text(l10n.viewReport), findsNothing);
  });

  testWidgets('a partner with no profile keeps the entered name and an avatar',
      (tester) async {
    await _pump(tester, [_externalReport()]);
    expect(tester.takeException(), isNull);

    expect(find.text('Kavitha S'), findsOneWidget);
    // No profile → no URL → NetworkPhoto renders its branded fallback rather
    // than a broken image, and the icon follows the person's gender.
    final photo = tester.widget<NetworkPhoto>(find.byType(NetworkPhoto).first);
    expect(photo.url, isEmpty);
    expect(photo.fallbackIcon, Icons.woman_outlined);
  });

  testWidgets('a completed report leads with View Report', (tester) async {
    final l10n = await _pump(
      tester,
      [_internalReport(status: AstrologerRequestStatus.completed)],
      partner: _profile(id: 'theirs', name: 'Priya'),
    );
    expect(tester.takeException(), isNull);

    // The completed tab is the second one.
    await tester.tap(find.text(l10n.completedTab(1)));
    await tester.pumpAndSettle();

    expect(find.text('Priya'), findsOneWidget);
    expect(find.text(l10n.statusCompleted), findsOneWidget);
    expect(find.text(l10n.viewReport), findsOneWidget);
    expect(find.text(l10n.downloadReport), findsOneWidget);
  });

  testWidgets('an empty tab offers the one action that fills it',
      (tester) async {
    final l10n = await _pump(tester, const []);
    expect(tester.takeException(), isNull);

    expect(find.text(l10n.noReportsYetHint), findsWidgets);
    // The request CTA appears above the tabs AND inside the empty state.
    expect(find.text(l10n.requestNewHoroscopeReport), findsNWidgets(2));
  });
}
