// Drives the WHOLE New Horoscope Report request end to end, with real taps —
// Person 1 → Person 2 → Contact → Review → the ₹199 CTA — and pins the two
// things that were wrong with it:
//
//   • the pay CTA must open the payment flow, NEVER walk the member back to
//     the contact step (spec §1, §3, §13);
//   • a payment that does not complete must leave every field exactly where it
//     was, and say what happened (spec §16).
//
// Plus the pieces the redesign added: the three-section person card, birth
// place selected in ONE tap with no Save button, and Religion / Community that
// accept a typed value instead of an "Others" mode.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/models/location_model.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/auth_provider.dart';
import 'package:jothida_matrimony/providers/location_provider.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';
import 'package:jothida_matrimony/screens/report/horoscope_request_person_form.dart';
import 'package:jothida_matrimony/screens/report/request_external_report_screen.dart';
import 'package:jothida_matrimony/widgets/common/place_picker_field.dart';
import 'package:jothida_matrimony/widgets/common/searchable_with_add_field.dart';

/// A member whose profile fills Person 1 completely, so the walk-through only
/// has to type the SECOND chart — which is also what a real member does.
ProfileModel _member() => ProfileModel.fromMap({
      'id': 'me',
      'userId': 'me-uid',
      'name': 'Karthik Raja',
      'fullName': 'Karthik Raja',
      'gender': 'Male',
      'age': 29,
      'dateOfBirth': DateTime(1996, 3, 2).toIso8601String(),
      'city': 'Erode',
      'district': 'Erode',
      'state': 'Tamil Nadu',
      'religion': 'Hindu',
      // ProfileModel.fromMap reads 'horoscopeDetails' / 'contactDetails' — the
      // shapes the app actually stores.
      'horoscopeDetails': {
        'birthTime': '09:20 PM',
        'birthPlace': 'Erode, Erode, Tamil Nadu',
        'nakshatra': 'உத்திரம்',
        'rasi': 'கன்னி',
      },
      'contactDetails': {
        'contactPersonName': 'Karthik Raja',
        'mobileNumber': '9876543210',
      },
    });

/// Two real places, enough for the picker to have something to find and to
/// prove the row carries District + State under the city name.
final _places = <PlaceOption>[
  const PlaceOption(
    city: TnCity(
        id: 1, districtId: 30, nameEn: 'Virudhunagar', nameTa: 'விருதுநகர்'),
    district:
        TnDistrict(id: 30, nameEn: 'Virudhunagar', nameTa: 'விருதுநகர்'),
  ),
  const PlaceOption(
    city: TnCity(id: 2, districtId: 9, nameEn: 'Erode', nameTa: 'ஈரோடு'),
    district: TnDistrict(id: 9, nameEn: 'Erode', nameTa: 'ஈரோடு'),
  ),
];

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  ProfileModel? profile,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isGuestProvider.overrideWithValue(false),
        myProfileProvider
            .overrideWith((ref) => Stream<ProfileModel?>.value(profile)),
        allPlaceOptionsProvider.overrideWith((ref) async => _places),
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
  await tester.pumpAndSettle();
  // The screen asks Play for its price on open, and that ask is bounded by a
  // 10-second store timeout. Nothing here is reachable, so let the timer fire
  // now — the screen falls back to the built-in ₹199 and no timer is left
  // pending at teardown.
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpAndSettle();
  return AppLocalizations.delegate.load(locale);
}

/// Fills the CURRENTLY VISIBLE person card: name, date, time and birth place.
/// Every one of these goes through the real control the member touches — the
/// date picker dialog, the time picker dialog and the place sheet — because
/// the bug being guarded here lived in exactly that gap between what the form
/// holds and what a `Form` reports.
Future<void> _fillVisiblePerson(
  WidgetTester tester,
  AppLocalizations l10n, {
  required String name,
  required String placeQuery,
}) async {
  await tester.enterText(find.byType(TextFormField).first, name);
  await tester.pumpAndSettle();

  // Date of birth → the Material date picker → OK on its initial date.
  await tester.tap(find.byIcon(Icons.cake_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  // Time of birth → the Material time picker → OK on its initial time.
  await tester.tap(find.byIcon(Icons.access_time));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  // Place of birth → search → ONE tap on the result.
  await tester.tap(find.byType(PlacePickerField));
  await tester.pumpAndSettle();
  await tester.enterText(_sheetSearchBox, placeQuery);
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ListTile).first);
  await tester.pumpAndSettle();
}

/// The search box inside whichever picker sheet is currently open. Found by
/// its sheet rather than by "the last TextField on screen", which would just as
/// happily match a form field behind the sheet.
final Finder _sheetSearchBox = find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.byType(TextField),
);

/// Person 1 → Person 2 → Contact → Review, leaving the form on the pay step
/// with a complete, valid request.
Future<void> _walkToReview(WidgetTester tester, AppLocalizations l10n) async {
  // Step 1: Person 1 arrives complete from the profile.
  await tester.tap(find.text(l10n.continueLabel));
  await tester.pumpAndSettle();
  expect(find.text(l10n.personTwoDetails), findsOneWidget);

  // Step 2: the second chart, typed.
  await _fillVisiblePerson(tester, l10n,
      name: 'Meena Ravi', placeQuery: 'Viru');
  await tester.tap(find.text(l10n.continueLabel));
  await tester.pumpAndSettle();

  // Step 3: contact details, pre-filled from the profile.
  expect(find.text(l10n.contactDetailsTitle), findsOneWidget);
  await tester.tap(find.text(l10n.continueLabel));
  await tester.pumpAndSettle();

  // Step 4: review.
  expect(find.text(l10n.reviewAndPayTitle), findsOneWidget);
}

void main() {
  testWidgets('the whole request reaches the review step and stays there',
      (tester) async {
    final l10n = await _pump(tester, profile: _member());
    await _walkToReview(tester, l10n);
    expect(tester.takeException(), isNull);

    // The recap names both people, what it costs, and where the report goes.
    expect(find.text('Karthik Raja'), findsWidgets);
    expect(find.text('Meena Ravi'), findsOneWidget);
    expect(find.text(l10n.amountPayable), findsOneWidget);
    expect(find.text('+91 9876543210'), findsOneWidget);
    expect(find.text(l10n.payAndRequestReport('₹199')), findsOneWidget);
  });

  testWidgets('the pay CTA does not send the member back to the contact step',
      (tester) async {
    final l10n = await _pump(tester, profile: _member());
    await _walkToReview(tester, l10n);

    await tester.tap(find.text(l10n.payAndRequestReport('₹199')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // THE regression. Google Play is unreachable in a test, so the purchase
    // resolves as "unavailable" — but the member must still be standing on the
    // review step, being told what happened, not silently moved backwards.
    expect(find.text(l10n.reviewAndPayTitle), findsOneWidget);
    // The contact STEP is gone (its subtitle belongs to the form, not to the
    // recap heading of the same name on the review step) and the button still
    // asks for money rather than offering to continue.
    expect(find.text(l10n.contactDetailsSubtitle), findsNothing);
    expect(find.text(l10n.continueLabel), findsNothing);
    // …and it says what happened instead of failing silently.
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('a payment that does not complete keeps every detail',
      (tester) async {
    final l10n = await _pump(tester, profile: _member());
    await _walkToReview(tester, l10n);

    await tester.tap(find.text(l10n.payAndRequestReport('₹199')));
    await tester.pumpAndSettle();

    // Nothing typed is lost, and the CTA is live again for another try
    // (spec §16 — retry without re-entering anything).
    expect(find.text('Meena Ravi'), findsOneWidget);
    expect(find.text('+91 9876543210'), findsOneWidget);
    expect(find.text(l10n.payAndRequestReport('₹199')), findsOneWidget);

    // Going back to Person 2 finds it exactly as it was left.
    await tester.tap(find.text(l10n.back));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.back));
    await tester.pumpAndSettle();
    expect(find.text(l10n.personTwoDetails), findsOneWidget);
    expect(find.text('Meena Ravi'), findsOneWidget);
    expect(find.text('Virudhunagar, Virudhunagar, Tamil Nadu'), findsOneWidget);
  });

  testWidgets('the review step can jump to any step without losing anything',
      (tester) async {
    final l10n = await _pump(tester, profile: _member());
    await _walkToReview(tester, l10n);

    // Three Edit links: Person 1, Person 2, Contact.
    expect(find.text(l10n.edit), findsNWidgets(3));
    // The contact block sits at the bottom of the recap, behind the sticky pay
    // bar until the list is scrolled.
    await tester.ensureVisible(find.text(l10n.edit).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.edit).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.contactDetailsTitle), findsOneWidget);
    expect(find.text('Karthik Raja'), findsWidgets);
  });

  testWidgets('the person card is grouped into named sections',
      (tester) async {
    final l10n = await _pump(tester, profile: _member());
    expect(find.text(l10n.basicDetails), findsOneWidget);
    expect(find.text(l10n.horoscopeDetails), findsOneWidget);
    expect(find.text(l10n.additionalDetails), findsOneWidget);
  });

  testWidgets('birth place is chosen in one tap, with no Save button',
      (tester) async {
    final l10n = await _pump(tester, profile: _member());
    await tester.tap(find.text(l10n.continueLabel));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PlacePickerField));
    await tester.pumpAndSettle();
    await tester.enterText(_sheetSearchBox, 'Viru');
    await tester.pumpAndSettle();

    // The result carries the hierarchy the astrologer needs, not just a name.
    expect(find.text('Virudhunagar'), findsWidgets);
    expect(find.text('Virudhunagar, Tamil Nadu'), findsOneWidget);
    // No confirm step of any kind — the row IS the selection (spec §5).
    expect(find.text(l10n.save), findsNothing);

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    // Selected, the sheet closed, and the field shows all three levels.
    expect(_sheetSearchBox, findsNothing);
    expect(find.text('Virudhunagar, Virudhunagar, Tamil Nadu'), findsOneWidget);
  });

  testWidgets('a religion the list has never heard of is typed into the field',
      (tester) async {
    final l10n = await _pump(tester, profile: _member());

    // The Religion field is the searchable one carrying the religion label.
    final religion = find.ancestor(
      of: find.text('${l10n.religion} (${l10n.optional})'),
      matching: find.byType(SearchableWithAddField),
    );
    expect(religion, findsOneWidget);
    // It is the last field on the card, behind the sticky bottom bar until the
    // list is scrolled.
    await tester.ensureVisible(religion);
    await tester.pumpAndSettle();
    await tester.tap(religion);
    await tester.pumpAndSettle();

    // There is no "Others" escape hatch anywhere in the picker.
    expect(find.text(l10n.othersOption), findsNothing);

    await tester.enterText(_sheetSearchBox, 'Jainism');
    await tester.pumpAndSettle();

    // Type → + Add → selected, in one tap.
    final add = find.text(l10n.addValueLabel('Jainism'));
    expect(add, findsOneWidget);
    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(_sheetSearchBox, findsNothing);
    expect(find.text('Jainism'), findsOneWidget);
  });

  test('a person is complete without a Form, religion or nakshatra', () {
    final d = HoroscopePersonDraft()
      ..gender = 'Female'
      ..dob = DateTime(1998, 5, 4)
      ..hour = 7
      ..minute = 15
      ..place = const PlaceSelection(city: 'Erode', district: 'Erode');
    d.name.text = 'Meena Ravi';

    // The optional half really is optional.
    expect(d.isComplete, isTrue);

    // …and each required part is genuinely required.
    d.place = null;
    expect(d.isComplete, isFalse);
    d.place = const PlaceSelection(city: 'Erode', district: 'Erode');
    d.hour = null;
    expect(d.isComplete, isFalse);
  });

  test('a chosen place carries city, district, state AND country', () {
    final selection = _places.first.toSelection('en');
    expect(selection.city, 'Virudhunagar');
    expect(selection.district, 'Virudhunagar');
    expect(selection.state, TnState.nameEn);
    expect(selection.country, kDefaultCountry);

    // A typed village is still an Indian village.
    expect(const PlaceSelection.custom('Sirumalai').country, kDefaultCountry);
  });

  test('the stored snapshot keeps the whole location and the new fields', () {
    final d = HoroscopePersonDraft()
      ..gender = 'Female'
      ..dob = DateTime(1998, 5, 4)
      ..hour = 7
      ..minute = 15
      ..place = _places.first.toSelection('en')
      ..religion = 'Jainism'
      ..caste = 'Digambar';
    d.name.text = 'Meena Ravi';

    final map = d.toMap();
    expect(map['placeCity'], 'Virudhunagar');
    expect(map['placeDistrict'], 'Virudhunagar');
    expect(map['placeState'], TnState.nameEn);
    expect(map['placeCountry'], kDefaultCountry);
    expect(map['religion'], 'Jainism');
    expect(map['caste'], 'Digambar');
  });
}
