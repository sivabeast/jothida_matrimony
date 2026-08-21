// Astrology bookings, admin notification badges and the shared place picker.
//
// Covers the rules that are easy to regress silently:
//   • a booking card's chip reads "Upcoming" only while the visit is ahead;
//   • an admin badge counts NEW action-required records only, never the total,
//     and opening the section clears the badge WITHOUT deleting records;
//   • a place is always identified by City/Village + District + State, so two
//     villages that share a name stay distinguishable.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jothida_matrimony/core/utils/appointment_status.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/models/astrologer_account_model.dart';
import 'package:jothida_matrimony/models/astrologer_request_model.dart';
import 'package:jothida_matrimony/models/location_model.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/models/report_model.dart';
import 'package:jothida_matrimony/providers/admin_badge_provider.dart';
import 'package:jothida_matrimony/providers/admin_provider.dart';
import 'package:jothida_matrimony/providers/appointment_provider.dart';
import 'package:jothida_matrimony/providers/auth_provider.dart';
import 'package:jothida_matrimony/providers/location_provider.dart';
import 'package:jothida_matrimony/providers/report_provider.dart';
import 'package:jothida_matrimony/widgets/common/place_picker_field.dart';

AstrologerRequestModel _appt({
  required String id,
  required AstrologerRequestStatus status,
  DateTime? visitDate,
  DateTime? createdAt,
}) =>
    AstrologerRequestModel(
      id: id,
      astrologerId: '',
      userId: 'u1',
      userName: 'Member',
      type: AstrologerRequestType.consultation,
      status: status,
      visitDate: visitDate,
      session: 'morning',
      createdAt: createdAt ?? DateTime.now(),
    );

/// English localizations, resolved once for the label helpers.
Future<AppLocalizations> _l10n() => AppLocalizations.delegate.load(
      const Locale('en'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('booking status chip', () {
    test('an open booking whose visit is ahead reads "Upcoming"', () async {
      final l10n = await _l10n();
      final appt = _appt(
        id: 'B1',
        status: AstrologerRequestStatus.accepted,
        visitDate: DateTime.now().add(const Duration(days: 3)),
      );
      expect(appointmentTimelineLabel(l10n, appt), l10n.apptStatusUpcoming);
    });

    test('a past booking falls back to its own status', () async {
      final l10n = await _l10n();
      final appt = _appt(
        id: 'B2',
        status: AstrologerRequestStatus.completed,
        visitDate: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(appointmentTimelineLabel(l10n, appt), l10n.apptStatusCompleted);
    });

    test('a cancelled booking never reads "Upcoming"', () async {
      final l10n = await _l10n();
      final appt = _appt(
        id: 'B3',
        status: AstrologerRequestStatus.rejected,
        visitDate: DateTime.now().add(const Duration(days: 3)),
      );
      expect(appointmentTimelineLabel(l10n, appt), l10n.apptStatusCancelled);
      expect(isOpenAppointment(appt.status), isFalse);
    });
  });

  group('admin notification badges', () {
    /// A scope wired to fixed data, so a badge count is a pure function of the
    /// records and the "last seen" marks.
    ProviderContainer container({
      List<AstrologerRequestModel> appointments = const [],
      List<ProfileModel> pendingProfiles = const [],
      List<ReportModel> reports = const [],
    }) =>
        ProviderContainer(overrides: [
          firebaseAuthStreamProvider
              .overrideWith((ref) => const Stream<User?>.empty()),
          pendingProfilesProvider
              .overrideWith((ref) => Stream.value(pendingProfiles)),
          allAppointmentsProvider
              .overrideWith((ref) => Stream.value(appointments)),
          allAstrologerRequestsProvider
              .overrideWith((ref) => Stream.value(const [])),
          allReportsProvider.overrideWith((ref) => Stream.value(reports)),
          allAstrologersProvider
              .overrideWith((ref) => Stream.value(const <AstrologerAccount>[])),
        ]);

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('an empty queue shows NO badge', () async {
      final c = container();
      addTearDown(c.dispose);
      c.listen(adminBadgeCountsProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      final counts = c.read(adminBadgeCountsProvider);
      expect(counts[AdminBadgeSection.appointments], 0);
      expect(counts[AdminBadgeSection.pendingVerification], 0);
    });

    test('counts only PENDING bookings — never the total in the collection',
        () async {
      final c = container(appointments: [
        _appt(id: 'A', status: AstrologerRequestStatus.pending),
        _appt(id: 'B', status: AstrologerRequestStatus.pending),
        // Already handled — must NOT be counted.
        _appt(id: 'C', status: AstrologerRequestStatus.accepted),
        _appt(id: 'D', status: AstrologerRequestStatus.completed),
        _appt(id: 'E', status: AstrologerRequestStatus.rejected),
      ]);
      addTearDown(c.dispose);
      c.listen(adminBadgeCountsProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(adminBadgeCountsProvider)[AdminBadgeSection.appointments],
          2);
    });

    test('opening the section clears the badge but keeps every record',
        () async {
      final appointments = [
        _appt(id: 'A', status: AstrologerRequestStatus.pending),
        _appt(id: 'B', status: AstrologerRequestStatus.pending),
      ];
      final c = container(appointments: appointments);
      addTearDown(c.dispose);
      c.listen(adminBadgeCountsProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(adminBadgeCountsProvider)[AdminBadgeSection.appointments],
          2);

      await c
          .read(adminSeenProvider.notifier)
          .markSeen(AdminBadgeSection.appointments);
      await Future<void>.delayed(Duration.zero);

      // Notification cleared — the two pending bookings are still there.
      expect(c.read(adminBadgeCountsProvider)[AdminBadgeSection.appointments],
          0);
      expect(
          c.read(allAppointmentsProvider).valueOrNull?.length, appointments.length);
    });
  });

  group('place identity', () {
    test('a place always displays City, District, State', () {
      const p = PlaceSelection(
        city: 'Athikkolam',
        cityEn: 'Athikkolam',
        district: 'Ramanathapuram',
        districtEn: 'Ramanathapuram',
        state: 'Tamil Nadu',
      );
      expect(p.display, 'Athikkolam, Ramanathapuram, Tamil Nadu');
    });

    test('a free-typed place carries only its name', () {
      const p = PlaceSelection.custom('Chinna Ooru');
      expect(p.display, 'Chinna Ooru');
      expect(p.custom, isTrue);
      expect(p.districtId, isNull);
    });
  });

  testWidgets('the picker tells two same-named villages apart',
      (tester) async {
    // The search sheet is a tall bottom sheet — give it room, or the rows are
    // clipped and the taps land on nothing.
    final view = tester.view;
    view.physicalSize = const Size(420, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    // The same village name in two different districts — exactly the case a
    // bare city list could not resolve (spec §27/§28).
    const ramnad = TnDistrict(
        id: 1, nameEn: 'Ramanathapuram', nameTa: 'ராமநாதபுரம்');
    const sivaganga =
        TnDistrict(id: 2, nameEn: 'Sivaganga', nameTa: 'சிவகங்கை');
    final options = [
      PlaceOption(
        city: const TnCity(
            id: 10,
            districtId: 1,
            nameEn: 'Athikkolam',
            nameTa: 'அத்திக்கோலம்'),
        district: ramnad,
      ),
      PlaceOption(
        city: const TnCity(
            id: 11,
            districtId: 2,
            nameEn: 'Athikkolam',
            nameTa: 'அத்திக்கோலம்'),
        district: sivaganga,
      ),
    ];

    PlaceSelection? picked;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allPlaceOptionsProvider.overrideWith((ref) async => options),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlacePickerField(
            label: 'Place of Birth',
            value: picked?.display,
            onChanged: (p) => picked = p,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InputDecorator).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Athik');
    await tester.pumpAndSettle();

    // Both villages are offered, each disambiguated by its own district.
    expect(find.text('Athikkolam'), findsNWidgets(2));
    expect(find.text('Ramanathapuram, Tamil Nadu'), findsOneWidget);
    expect(find.text('Sivaganga, Tamil Nadu'), findsOneWidget);

    // Row order is [Ramanathapuram, Sivaganga, "use what I typed"], so index 1
    // is the Sivaganga village — NOT `.last`, which is the free-text fallback.
    await tester.tap(find.byIcon(Icons.add_circle_outline).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.display, 'Athikkolam, Sivaganga, Tamil Nadu');
    expect(picked!.districtId, 2);
  });
}
