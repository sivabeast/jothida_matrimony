// Two fixes, pinned:
//
//  1. Location: members can add a place that is not listed (+ Add) — under the
//     right district / state / country, without duplicates, safely under
//     concurrent adds, persisted and merged back into every picker.
//  2. Admin → Users → Edit Profile: "no matrimony profile" is shown only when
//     the database confirms it; loading, errors and linked profiles are
//     handled, and the right member's profile is opened.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseException, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/core/data/location_catalog.dart';
import 'package:jothida_matrimony/core/data/master_option.dart';
import 'package:jothida_matrimony/core/utils/admin_member_rows.dart';
import 'package:jothida_matrimony/core/utils/member_profile_lookup.dart';
import 'package:jothida_matrimony/core/utils/place_additions.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';
import 'package:jothida_matrimony/models/location_model.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/models/user_model.dart';
import 'package:jothida_matrimony/providers/admin_provider.dart';
import 'package:jothida_matrimony/providers/auth_provider.dart';
import 'package:jothida_matrimony/providers/location_provider.dart';
import 'package:jothida_matrimony/router/auth_redirect.dart';
import 'package:jothida_matrimony/screens/admin/admin_edit_profile_screen.dart';
import 'package:jothida_matrimony/screens/profile/profile_creation_screen.dart';
import 'package:jothida_matrimony/services/firebase/location_repository.dart';
import 'package:jothida_matrimony/services/firebase/place_additions_service.dart';
import 'package:jothida_matrimony/widgets/common/location_picker_section.dart';
import 'package:jothida_matrimony/widgets/common/place_picker_field.dart';

import '../tool/merge_place_additions.dart' show mergePlaceAdditionsIntoAssets;

// ── Fixtures ────────────────────────────────────────────────────────────────

const _ramnad = TnDistrict(
  id: 1,
  nameEn: 'Ramanathapuram',
  nameTa: 'ராமநாதபுரம்',
);
const _sivaganga = TnDistrict(id: 2, nameEn: 'Sivaganga', nameTa: 'சிவகங்கை');

final _options = [
  const PlaceOption(
    city: TnCity(
      id: 10,
      districtId: 1,
      nameEn: 'Athikkolam',
      nameTa: 'அத்திக்கோலம்',
    ),
    district: _ramnad,
  ),
  const PlaceOption(
    city: TnCity(
      id: 11,
      districtId: 2,
      nameEn: 'Karaikudi',
      nameTa: 'காரைக்குடி',
    ),
    district: _sivaganga,
  ),
];

PlaceParent _parentIn(TnDistrict d) => PlaceParent.district(d);

/// Records every add and answers from a script.
class _FakePlaces extends PlaceAdditionsService {
  final List<({String name, PlaceParent parent, String uid})> calls = [];
  Future<PlaceAddResult> Function(String name, PlaceParent parent)? answer;
  int _nextId = kFirstAddedPlaceId;

  @override
  Stream<List<PlaceAddition>> watch() => Stream.value(const []);

  @override
  Future<PlaceAddResult> add({
    required String name,
    required PlaceParent parent,
    required String uid,
  }) {
    calls.add((name: name, parent: parent, uid: uid));
    final scripted = answer;
    if (scripted != null) return scripted(name, parent);
    return Future.value(
      PlaceAddResult(
        PlaceAddition(
          id: _nextId++,
          name: name,
          districtId: parent.districtId,
          state: parent.state,
          stateId: parent.stateId,
          country: parent.country,
          key: placeAdditionKey(name, parent),
          addedBy: uid,
        ),
        alreadyExisted: false,
      ),
    );
  }
}

Widget _app({required Widget child, required List<Override> overrides}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

final Finder _addRow = find.byKey(const ValueKey('place-add-row'));
final Finder _saveButton = find.byKey(const ValueKey('place-add-save'));
final Finder _sheetSearchBox = find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.byType(TextField),
);

Future<void> _chooseDistrict(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('place-parent-district')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

ProfileModel _profile(
  String id,
  String userId, {
  DateTime? createdAt,
  String name = 'Member',
}) => ProfileModel.fromData(id, {
  'userId': userId,
  'fullName': name,
  if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════════
  group('place name validation', () {
    test('trims, collapses spaces and title-cases one-case input', () {
      expect(checkPlaceName('  kovil   patti ').name, 'Kovil Patti');
      expect(checkPlaceName('KOVILPATTI').name, 'Kovilpatti');
      expect(checkPlaceName('St. Thomas Mount').name, 'St. Thomas Mount');
      expect(
        checkPlaceName('McLeod Ganj').name,
        'McLeod Ganj',
        reason: 'mixed case is kept as typed',
      );
      expect(checkPlaceName('கோவில்பட்டி').problem, isNull);
      expect(checkPlaceName('Kovilpatti,').name, 'Kovilpatti');
    });

    test('refuses empty, too short, too long and non-place text', () {
      expect(checkPlaceName('   ').problem, PlaceNameProblem.empty);
      expect(checkPlaceName('K').problem, PlaceNameProblem.tooShort);
      expect(checkPlaceName('K' * 61).problem, PlaceNameProblem.tooLong);
      for (final junk in [
        '627701',
        'call 9876543210',
        'a@b.com',
        'x/y',
        '<b>',
      ]) {
        expect(
          checkPlaceName(junk).problem,
          PlaceNameProblem.invalidCharacters,
          reason: junk,
        );
      }
    });

    test('capitalisation, spacing and transliteration share one key', () {
      final k = placeNameKey('Kovilpatti');
      expect(placeNameKey(' kovil patti '), k);
      expect(placeNameKey('KOVILPATI'), k);
      expect(placeNameKey('Thanjavoor'), placeNameKey('Tanjavur'));
      expect(placeNameKey('கோவில்பட்டி'), isNotEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('append plan (the transaction body)', () {
    PlaceAdditionPlan plan(
      List<Object?> entries,
      String name,
      PlaceParent p, {
      int? nextId,
      String by = 'u1',
    }) => planPlaceAddition(
      rawEntries: entries,
      storedNextId: nextId,
      name: name,
      parent: p,
      addedBy: by,
      now: 1,
    );

    test('the first place gets the first added id', () {
      final r = plan(const [], 'Kovilpatti', _parentIn(_ramnad));
      expect(r.isDuplicate, isFalse);
      expect(r.added!.id, kFirstAddedPlaceId);
      expect(r.nextId, kFirstAddedPlaceId + 1);
      expect(r.entries, hasLength(1));
      final row = r.entries.single as Map;
      // The cities_en.json columns, plus the parent and the "+ Add" fields.
      expect(row['id'], kFirstAddedPlaceId);
      expect(row['districtId'], 1);
      expect(row['name'], 'Kovilpatti');
      expect(row['state'], 'Tamil Nadu');
      expect(row['country'], 'India');
      expect(row['v'], 'Kovilpatti');
      expect(row['p'], 'd:1');
    });

    test('existing entries are kept untouched and in order', () {
      final legacy = {'v': 'old flat value', 'p': ''};
      final first = plan(const [], 'Alpha', _parentIn(_ramnad)).entries.single;
      final r = plan(
        [legacy, first],
        'Beta',
        _parentIn(_ramnad),
        nextId: kFirstAddedPlaceId + 1,
      );
      expect(r.entries, hasLength(3));
      expect(identical(r.entries[0], legacy), isTrue);
      expect(identical(r.entries[1], first), isTrue);
      expect((r.entries[2] as Map)['name'], 'Beta');
    });

    test('a duplicate differing only in case / spaces is found, not added', () {
      final entries = plan(const [], 'Kovilpatti', _parentIn(_ramnad)).entries;
      final r = plan(
        entries,
        'kovil patti',
        _parentIn(_ramnad),
        nextId: kFirstAddedPlaceId + 1,
      );
      expect(r.isDuplicate, isTrue);
      expect(r.existing!.name, 'Kovilpatti');
      expect(identical(r.entries, entries), isTrue, reason: 'nothing written');
    });

    test('the same name under a DIFFERENT parent is a different place', () {
      final entries = plan(const [], 'Athikkolam', _parentIn(_ramnad)).entries;
      final r = plan(
        entries,
        'Athikkolam',
        _parentIn(_sivaganga),
        nextId: kFirstAddedPlaceId + 1,
      );
      expect(r.isDuplicate, isFalse);
      expect(r.added!.districtId, 2);
      final kerala = LocationCatalog.indianStates.byValue('Kerala')!;
      expect(
        plan(entries, 'Athikkolam', PlaceParent.state(kerala)).isDuplicate,
        isFalse,
      );
    });

    test('concurrent adds: the retried transaction never loses an entry', () {
      // Both members read the SAME document.
      final base = plan(const [], 'Alpha', _parentIn(_ramnad)).entries;
      const baseNext = kFirstAddedPlaceId + 1;
      final a = plan(
        base,
        'Beta',
        _parentIn(_ramnad),
        nextId: baseNext,
        by: 'A',
      );
      // Member B's first attempt is based on the stale read and would reuse
      // the same id — Firestore rejects that commit and re-runs B's
      // transaction on A's committed document:
      final bRetry = plan(
        a.entries,
        'Gamma',
        _parentIn(_ramnad),
        nextId: a.nextId,
        by: 'B',
      );
      final names = [for (final e in bRetry.entries) (e as Map)['name']];
      expect(names, ['Alpha', 'Beta', 'Gamma']);
      final ids = {for (final e in bRetry.entries) (e as Map)['id']};
      expect(ids, hasLength(3), reason: 'ids stay unique');

      // Both adding the SAME place at once resolves to ONE row.
      final bSame = plan(
        a.entries,
        'BETA',
        _parentIn(_ramnad),
        nextId: a.nextId,
        by: 'B',
      );
      expect(bSame.isDuplicate, isTrue);
      expect(bSame.entries, hasLength(2));
    });

    test('a stale id counter can never hand out a used id', () {
      final entries = [
        PlaceAddition(
          id: kFirstAddedPlaceId + 7,
          name: 'Zeta',
          districtId: 1,
          state: 'Tamil Nadu',
          key: placeAdditionKey('Zeta', _parentIn(_ramnad)),
        ).toMap(),
      ];
      final r = plan(entries, 'Eta', _parentIn(_ramnad), nextId: 5);
      expect(r.added!.id, kFirstAddedPlaceId + 8);
    });

    test('parsing skips unusable rows and keeps the first of a duplicate', () {
      final one = plan(const [], 'Alpha', _parentIn(_ramnad)).added!.toMap();
      final dup = Map<String, dynamic>.of(one)
        ..['id'] = kFirstAddedPlaceId + 1
        ..['name'] = 'ALPHA';
      final parsed = parsePlaceAdditions([
        {'v': 'legacy', 'p': ''},
        'garbage',
        one,
        dup,
      ]);
      expect(parsed, hasLength(1));
      expect(parsed.single.id, kFirstAddedPlaceId);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('location data with member-added places', () {
    late LocationRepository repo;
    late TnDistrict thoothukudi;

    setUp(() async {
      repo = LocationRepository();
      thoothukudi = (await repo.findDistrict('Thoothukudi'))!;
    });

    PlaceAddition added(int id, String name, TnDistrict d) => PlaceAddition(
      id: id,
      name: name,
      districtId: d.id,
      state: 'Tamil Nadu',
      stateId: 'st_tn',
      key: placeAdditionKey(name, PlaceParent.district(d)),
    );

    test(
      'a Tamil Nadu place joins its district and resolves by id and name',
      () async {
        final bundled = (await repo.getCities(thoothukudi.id)).length;
        repo.mergeAdditions([
          added(kFirstAddedPlaceId, 'Kovilpatti Colony', thoothukudi),
        ]);

        final cities = await repo.getCities(thoothukudi.id);
        expect(cities, hasLength(bundled + 1));
        final byId = await repo.cityById(kFirstAddedPlaceId);
        expect(byId?.nameEn, 'Kovilpatti Colony');
        expect(byId?.districtId, thoothukudi.id);
        expect(
          (await repo.findCity(
            'kovilpatti colony',
            districtId: thoothukudi.id,
          ))?.id,
          kFirstAddedPlaceId,
        );

        final index = await repo.searchIndex();
        final hit = index.search('Kovilpatti Colony').hits.first;
        expect(hit.option.city.id, kFirstAddedPlaceId);
        expect(hit.option.district.id, thoothukudi.id);
      },
    );

    test('a bundled town is never duplicated by an addition', () async {
      final existing = (await repo.getCities(thoothukudi.id)).first;
      final before = (await repo.getAllCities()).length;
      repo.mergeAdditions([
        added(kFirstAddedPlaceId, existing.nameEn.toUpperCase(), thoothukudi),
      ]);
      expect((await repo.getAllCities()).length, before);
    });

    test('a place added on this device survives an older snapshot', () async {
      await repo.getAllCities();
      final place = added(kFirstAddedPlaceId + 3, 'New Nagar', thoothukudi);
      repo.addAdditionLocally(place);
      repo.mergeAdditions(const []); // the stream has not caught up yet
      expect((await repo.cityById(place.id))?.nameEn, 'New Nagar');
      repo.mergeAdditions([place]); // …and now it has
      repo.mergeAdditions(const []); // an admin removed it
      expect(await repo.cityById(place.id), isNull);
    });

    test(
      'places outside Tamil Nadu are searchable by name and by state',
      () async {
        final kerala = LocationCatalog.indianStates.byValue('Kerala')!;
        final kochi = PlaceAddition(
          id: kFirstAddedPlaceId + 9,
          name: 'Kochi',
          state: 'Kerala',
          stateId: kerala.id,
          key: placeAdditionKey('Kochi', PlaceParent.state(kerala)),
        );
        repo.mergeAdditions([kochi]);
        final index = await repo.searchIndex();
        expect(index.searchOthers('koch').single.name, 'Kochi');
        expect(index.searchOthers('Kerala').single.name, 'Kochi');
        expect(index.hasExactPlace('Kochi'), isTrue);
      },
    );

    test('exact-place detection decides whether "+ Add" is offered', () async {
      final index = await repo.searchIndex();
      expect(index.hasExactPlace('Rajapalayam'), isTrue);
      expect(index.hasExactPlace('rajapalayam, Virudhunagar'), isTrue);
      expect(index.hasExactPlace('Rajapal'), isFalse, reason: 'a prefix');
      expect(index.hasExactPlace('Some Unlisted Village'), isFalse);
    });

    test('"Place, District" narrows the search to that district', () async {
      final index = await repo.searchIndex();
      expect(
        index.search('Rajapalayam, Virudhunagar').hits.first.option.city.nameEn,
        'Rajapalayam',
      );
      expect(index.search('Rajapalayam, Chennai').hits, isEmpty);
      expect(index.districtNamed('Tuticorin')?.id, thoothukudi.id);
      final virudhunagar = index.districtNamed('Virudhunagar District')!;
      expect(
        index.exactMatch('RAJAPALAYAM', districtId: virudhunagar.id),
        isNotNull,
      );
      expect(
        index.exactMatch('Rajapalayam', districtId: thoothukudi.id),
        isNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('place picker: search and + Add', () {
    late _FakePlaces places;

    List<Override> overrides({
      String? uid = 'member-1',
      List<PlaceAddition> additions = const [],
    }) => [
      allPlaceOptionsProvider.overrideWith((ref) async => _options),
      placeAdditionsProvider.overrideWith((ref) => Stream.value(additions)),
      placeAdditionsServiceProvider.overrideWithValue(places),
      memberUidProvider.overrideWithValue(uid),
    ];

    setUp(() => places = _FakePlaces());

    Future<List<PlaceSelection>> openPicker(
      WidgetTester tester, {
      String? uid = 'member-1',
      List<PlaceAddition> additions = const [],
    }) async {
      final picked = <PlaceSelection>[];
      await tester.pumpWidget(
        _app(
          overrides: overrides(uid: uid, additions: additions),
          child: PlacePickerField(label: 'Native Place', onChanged: picked.add),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PlacePickerField));
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('a listed place: suggestions appear and no "+ Add"', (
      tester,
    ) async {
      final picked = await openPicker(tester);
      await tester.enterText(_sheetSearchBox, 'Athikkolam');
      await tester.pumpAndSettle();
      expect(find.text('Ramanathapuram District, Tamil Nadu'), findsOneWidget);
      expect(_addRow, findsNothing, reason: 'the place is listed exactly');

      // A partial name still suggests it — and offers + Add for a new one.
      await tester.enterText(_sheetSearchBox, 'Athik');
      await tester.pumpAndSettle();
      expect(find.text('Athikkolam'), findsOneWidget);
      expect(_addRow, findsOneWidget);

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(picked.single.display, 'Athikkolam, Ramanathapuram, Tamil Nadu');
    });

    testWidgets('an unlisted place: + Add → district → saved and selected', (
      tester,
    ) async {
      final picked = await openPicker(tester);
      await tester.enterText(_sheetSearchBox, 'kovilpatti');
      await tester.pumpAndSettle();

      expect(_addRow, findsOneWidget);
      expect(find.text('Add "kovilpatti"'), findsOneWidget);
      expect(
        find.descendant(of: _addRow, matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );

      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      expect(find.text('Add a new place'), findsOneWidget);
      // Normalised in the form.
      expect(find.widgetWithText(TextField, 'Kovilpatti'), findsOneWidget);

      // No parent yet → refused with a clear message, nothing saved.
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(find.text('Choose the district'), findsWidgets);
      expect(places.calls, isEmpty);

      await _chooseDistrict(tester, 'Sivaganga');
      expect(
        find.text(
          'Will be saved as: Kovilpatti, Sivaganga District, Tamil Nadu',
        ),
        findsOneWidget,
      );
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(places.calls, hasLength(1));
      expect(places.calls.single.name, 'Kovilpatti');
      expect(places.calls.single.parent.districtId, 2);
      expect(places.calls.single.uid, 'member-1');

      final s = picked.single;
      expect(s.custom, isFalse, reason: 'it is a real town row now');
      expect(s.cityId, kFirstAddedPlaceId);
      expect(s.districtId, 2);
      expect(s.display, 'Kovilpatti, Sivaganga, Tamil Nadu');
      expect(
        find.text('"Kovilpatti" was added to the list and selected.'),
        findsOneWidget,
      );
    });

    testWidgets('"Place, District" pre-selects the district', (tester) async {
      final picked = await openPicker(tester);
      await tester.enterText(_sheetSearchBox, 'Pudur, Sivaganga');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(places.calls.single.name, 'Pudur');
      expect(picked.single.display, 'Pudur, Sivaganga, Tamil Nadu');
    });

    testWidgets('a place already listed is offered instead of a duplicate', (
      tester,
    ) async {
      final picked = await openPicker(tester);
      await tester.enterText(_sheetSearchBox, 'Athi');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('place-add-name')),
        'ATHIK KOLAM',
      );
      await _chooseDistrict(tester, 'Ramanathapuram');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(places.calls, isEmpty, reason: 'no duplicate is written');
      expect(find.textContaining('is already listed under'), findsOneWidget);
      await tester.ensureVisible(find.text('Select "Athikkolam"'));
      await tester.tap(find.text('Select "Athikkolam"'));
      await tester.pumpAndSettle();
      expect(picked.single.cityId, 10);
    });

    testWidgets('another member added it a moment ago: it is selected', (
      tester,
    ) async {
      places.answer = (name, parent) async => PlaceAddResult(
        PlaceAddition(
          id: kFirstAddedPlaceId + 4,
          name: 'Pudur',
          districtId: parent.districtId,
          state: 'Tamil Nadu',
          key: placeAdditionKey('Pudur', parent),
        ),
        alreadyExisted: true,
      );
      final picked = await openPicker(tester);
      await tester.enterText(_sheetSearchBox, 'pudur, Ramanathapuram');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(picked.single.cityId, kFirstAddedPlaceId + 4);
      expect(
        find.text('"Pudur" is already on the list — it has been selected.'),
        findsOneWidget,
      );
    });

    testWidgets('saving shows progress and cannot be submitted twice', (
      tester,
    ) async {
      final gate = Completer<PlaceAddResult>();
      places.answer = (name, parent) => gate.future;
      final picked = await openPicker(tester);
      await tester.enterText(_sheetSearchBox, 'Pudur, Sivaganga');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();

      await tester.tap(_saveButton);
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(_saveButton, warnIfMissed: false);
      await tester.pump();
      expect(places.calls, hasLength(1), reason: 'one submission only');

      gate.complete(
        PlaceAddResult(
          PlaceAddition(
            id: kFirstAddedPlaceId,
            name: 'Pudur',
            districtId: 2,
            state: 'Tamil Nadu',
            key: placeAdditionKey('Pudur', _parentIn(_sivaganga)),
          ),
          alreadyExisted: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(picked.single.cityId, kFirstAddedPlaceId);
    });

    testWidgets('a failed save explains why and never blocks the member', (
      tester,
    ) async {
      var attempts = 0;
      places.answer = (name, parent) async {
        attempts++;
        throw const PlaceSaveException(PlaceSaveFailure.offline);
      };
      final picked = await openPicker(tester);
      await tester.enterText(_sheetSearchBox, 'Pudur, Sivaganga');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not save the place — check your internet connection '
          'and try again.',
        ),
        findsOneWidget,
      );
      expect(picked, isEmpty, reason: 'the sheet stays open');

      await tester.ensureVisible(find.text('Try Again'));
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(attempts, 2);

      await tester.ensureVisible(find.text('Use for this form only'));
      await tester.tap(find.text('Use for this form only'));
      await tester.pumpAndSettle();
      expect(picked.single.custom, isTrue);
      expect(picked.single.districtId, 2);
      expect(picked.single.display, 'Pudur, Sivaganga, Tamil Nadu');
    });

    testWidgets('a guest session fills the form without writing', (
      tester,
    ) async {
      final picked = await openPicker(tester, uid: null);
      await tester.enterText(_sheetSearchBox, 'Pudur, Sivaganga');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(places.calls, isEmpty);
      expect(picked.single.display, 'Pudur, Sivaganga, Tamil Nadu');
    });

    testWidgets('invalid names are refused inline', (tester) async {
      await openPicker(tester);
      await tester.enterText(_sheetSearchBox, 'Pudur, Sivaganga');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('place-add-name')),
        '600001',
      );
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Use letters only — no numbers or symbols'),
        findsOneWidget,
      );
      expect(places.calls, isEmpty);
    });

    testWidgets('a place in another state is filed under that state', (
      tester,
    ) async {
      final picked = await openPicker(tester);
      await tester.enterText(_sheetSearchBox, 'Munnar, Kerala');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      // Pre-selected from what was typed.
      expect(find.byKey(const ValueKey('place-parent-state')), findsOneWidget);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(places.calls.single.parent.kind, PlaceParentKind.state);
      expect(places.calls.single.parent.state, 'Kerala');
      expect(picked.single.state, 'Kerala');
      expect(picked.single.display, 'Munnar, Kerala');
    });

    testWidgets('member-added places elsewhere show up in the suggestions', (
      tester,
    ) async {
      final kerala = LocationCatalog.indianStates.byValue('Kerala')!;
      final picked = await openPicker(
        tester,
        additions: [
          PlaceAddition(
            id: kFirstAddedPlaceId,
            name: 'Munnar',
            state: 'Kerala',
            stateId: kerala.id,
            key: placeAdditionKey('Munnar', PlaceParent.state(kerala)),
          ),
        ],
      );
      await tester.enterText(_sheetSearchBox, 'Munn');
      await tester.pumpAndSettle();
      expect(find.text('Kerala, India'), findsOneWidget);
      await tester.tap(find.text('Munnar'));
      await tester.pumpAndSettle();
      expect(picked.single.display, 'Munnar, Kerala');
    });

    testWidgets('the keyboard never hides the + Add option (phone size)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2160); // 360 × 720 dp
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await openPicker(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3.0);
      await tester.enterText(_sheetSearchBox, 'Some Unlisted Village');
      await tester.pumpAndSettle();

      final row = tester.getRect(_addRow);
      expect(
        row.bottom,
        lessThan(720 - 300),
        reason: 'the row must sit above the on-screen keyboard',
      );
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      expect(find.text('Add a new place'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('profile location field', () {
    // The real bundled JSON, read with real async: large assets are decoded
    // on a background isolate, which fake-async widget time never finishes.
    Future<LocationRepository> loadedRepo(WidgetTester tester) async {
      final repo = LocationRepository();
      await tester.runAsync(() => repo.getAllCities());
      return repo;
    }

    testWidgets('an added place is saved with its district, state and id', (
      tester,
    ) async {
      final repo = await loadedRepo(tester);
      final places = _FakePlaces();
      final emitted = <LocationSelection>[];
      await tester.pumpWidget(
        _app(
          overrides: [
            locationRepositoryProvider.overrideWithValue(repo),
            placeAdditionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            placeAdditionsServiceProvider.overrideWithValue(places),
            memberUidProvider.overrideWithValue('member-1'),
          ],
          child: SingleChildScrollView(
            child: LocationPickerSection(onChanged: emitted.add),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PlacePickerField));
      await tester.pumpAndSettle();
      await tester.enterText(_sheetSearchBox, 'Kovilpatti Colony, Thoothukudi');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      final loc = emitted.last;
      expect(loc.city, 'Kovilpatti Colony');
      expect(loc.cityId, '$kFirstAddedPlaceId');
      expect(loc.district, 'Thoothukudi');
      expect(loc.state, 'Tamil Nadu');
      expect(loc.country, 'India');
      expect(
        find.text('Kovilpatti Colony, Thoothukudi, Tamil Nadu'),
        findsOneWidget,
      );
    });

    testWidgets('reopening a saved profile shows the added place again', (
      tester,
    ) async {
      final repo = await loadedRepo(tester);
      final thoothukudi = (await tester.runAsync(
        () => repo.findDistrict('Thoothukudi'),
      ))!;
      final place = PlaceAddition(
        id: kFirstAddedPlaceId + 1,
        name: 'Kovilpatti Colony',
        districtId: thoothukudi.id,
        state: 'Tamil Nadu',
        key: placeAdditionKey(
          'Kovilpatti Colony',
          PlaceParent.district(thoothukudi),
        ),
      );
      final emitted = <LocationSelection>[];
      await tester.pumpWidget(
        _app(
          overrides: [
            locationRepositoryProvider.overrideWithValue(repo),
            placeAdditionsProvider.overrideWith((ref) => Stream.value([place])),
          ],
          child: LocationPickerSection(
            initialCountry: 'India',
            initialState: 'Tamil Nadu',
            initialDistrict: 'Thoothukudi',
            initialCity: 'Kovilpatti Colony',
            initialCityId: '${place.id}',
            onChanged: emitted.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Kovilpatti Colony, Thoothukudi, Tamil Nadu'),
        findsOneWidget,
      );
      expect(
        emitted.last.cityId,
        '${place.id}',
        reason: 'an edit keeps the id instead of degrading to plain text',
      );
    });

    testWidgets('a place abroad keeps its country', (tester) async {
      final repo = await loadedRepo(tester);
      final emitted = <LocationSelection>[];
      await tester.pumpWidget(
        _app(
          overrides: [
            locationRepositoryProvider.overrideWithValue(repo),
            placeAdditionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            placeAdditionsServiceProvider.overrideWithValue(_FakePlaces()),
            memberUidProvider.overrideWithValue('member-1'),
          ],
          child: LocationPickerSection(onChanged: emitted.add),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PlacePickerField));
      await tester.pumpAndSettle();
      await tester.enterText(_sheetSearchBox, 'Al Barsha, UAE');
      await tester.pumpAndSettle();
      await tester.tap(_addRow);
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(emitted.last.country, 'UAE');
      expect(emitted.last.state, '');
      expect(emitted.last.city, 'Al Barsha');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('JSON asset merge tool', () {
    test('appends new Tamil Nadu places and never touches existing rows', () {
      final en = [
        {'id': 1, 'districtId': 1, 'name': 'Ariyalur'},
      ];
      final ta = [
        {'id': 1, 'districtId': 1, 'name': 'அரியலூர்'},
      ];
      final ariyalur = TnDistrict(
        id: 1,
        nameEn: 'Ariyalur',
        nameTa: 'அரியலூர்',
      );
      final kerala = LocationCatalog.indianStates.byValue('Kerala')!;
      PlaceAddition tn(int id, String name) => PlaceAddition(
        id: id,
        name: name,
        districtId: 1,
        state: 'Tamil Nadu',
        key: placeAdditionKey(name, PlaceParent.district(ariyalur)),
      );
      final result = mergePlaceAdditionsIntoAssets(
        citiesEn: en,
        citiesTa: ta,
        districtIds: {1},
        additions: [
          tn(100001, 'Sendurai North'),
          tn(100002, 'ARIYALUR'),
          PlaceAddition(
            id: 100003,
            name: 'Kochi',
            state: 'Kerala',
            key: placeAdditionKey('Kochi', PlaceParent.state(kerala)),
          ),
        ],
      );
      expect(result.appended, 1);
      expect(result.citiesEn.first, en.first);
      expect(result.citiesEn.last, {
        'id': 100001,
        'districtId': 1,
        'name': 'Sendurai North',
      });
      expect(result.citiesTa.last['id'], 100001);
      expect(en, hasLength(1), reason: 'inputs are not mutated');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('admin member profile lookup', () {
    Future<ProfileModel?> resolve({
      List<ProfileModel> cached = const [],
      bool cachedFromCache = false,
      Object? serverError,
      List<ProfileModel> server = const [],
      List<String> pointers = const [],
      Map<String, ProfileModel> docs = const {},
      List<String>? log,
    }) => resolveMemberProfile(
      uid: 'member-A',
      byUserId: ({required bool serverOnly}) async {
        log?.add(serverOnly ? 'server' : 'default');
        if (!serverOnly) return (profiles: cached, fromCache: cachedFromCache);
        if (serverError != null) throw serverError;
        return (profiles: server, fromCache: false);
      },
      pointerProfileIds: () async {
        log?.add('pointers');
        return pointers;
      },
      profileById: (id) async => docs[id],
    );

    test('the profile filed under the uid is returned directly', () async {
      final log = <String>[];
      final p = await resolve(cached: [_profile('p1', 'member-A')], log: log);
      expect(p?.id, 'p1');
      expect(log, ['default']);
    });

    test('an EMPTY cached answer is confirmed with the server', () async {
      final p = await resolve(
        cachedFromCache: true,
        server: [_profile('p1', 'member-A')],
      );
      expect(p?.id, 'p1');
    });

    test('a network failure is an error, never "no profile"', () async {
      await expectLater(
        resolve(
          cachedFromCache: true,
          serverError: FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          ),
        ),
        throwsA(isA<FirebaseException>()),
      );
    });

    test(
      'a profile with a blank userId is found through the pointers',
      () async {
        final p = await resolve(
          pointers: ['p9'],
          docs: {'p9': _profile('p9', '')},
        );
        expect(p?.id, 'p9');
      },
    );

    test('a pointer to ANOTHER member\'s profile is refused', () async {
      final p = await resolve(
        pointers: ['p7'],
        docs: {'p7': _profile('p7', 'member-B')},
      );
      expect(p, isNull);
    });

    test('null only when nothing is filed and nothing is linked', () async {
      expect(await resolve(pointers: ['missing']), isNull);
    });

    test('the newest of two profiles under one uid wins', () async {
      final p = await resolve(
        cached: [
          _profile('old', 'member-A', createdAt: DateTime(2025)),
          _profile('new', 'member-A', createdAt: DateTime(2026)),
        ],
      );
      expect(p?.id, 'new');
    });

    test('the Users list joins a blank-userId profile through the account', () {
      final now = DateTime(2026);
      UserModel user(String uid, {String? profileId}) => UserModel(
        uid: uid,
        profileId: profileId,
        createdAt: now,
        updatedAt: now,
      );
      final map = profilesByMember(
        [_profile('p1', 'u1'), _profile('p2', ''), _profile('p3', 'u9')],
        [user('u1'), user('u2', profileId: 'p2'), user('u3', profileId: 'p3')],
      );
      expect(map['u1']?.id, 'p1');
      expect(map['u2']?.id, 'p2');
      expect(map['u3'], isNull, reason: 'p3 belongs to u9');
      expect(map['u9']?.id, 'p3');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('admin Edit Profile screen', () {
    Future<void> pumpEditor(
      WidgetTester tester,
      String uid,
      Future<ProfileModel?> Function(String uid) resolve,
    ) async {
      await tester.pumpWidget(
        _app(
          overrides: [
            adminEditProfileTargetProvider.overrideWith(
              (ref, uid) => resolve(uid),
            ),
          ],
          child: AdminEditProfileScreen(uid: uid),
        ),
      );
    }

    const noProfileText =
        'This account has not created a matrimony profile yet, so there is '
        'nothing to edit.';

    testWidgets('while loading: a spinner, never "no profile"', (tester) async {
      final pending = Completer<ProfileModel?>();
      await pumpEditor(tester, 'member-A', (_) => pending.future);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(noProfileText), findsNothing);
    });

    testWidgets('a failed load shows the reason and Retry works', (
      tester,
    ) async {
      var calls = 0;
      await pumpEditor(tester, 'member-A', (_) async {
        calls++;
        if (calls == 1) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        }
        return null;
      });
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load this member\'s profile'),
        findsOneWidget,
      );
      expect(find.textContaining('Permission denied'), findsOneWidget);
      expect(find.text(noProfileText), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text(noProfileText), findsOneWidget);
    });

    testWidgets('a confirmed "no profile" offers navigation, creates nothing', (
      tester,
    ) async {
      await pumpEditor(tester, 'member-A', (_) async => null);
      await tester.pumpAndSettle();
      expect(find.text(noProfileText), findsOneWidget);
      expect(find.text('View User Details'), findsOneWidget);
      expect(find.byType(ProfileCreationScreen), findsNothing);
    });

    testWidgets('each member opens THEIR profile in the shared wizard', (
      tester,
    ) async {
      final byUid = {
        'member-A': _profile('profile-A', 'member-A'),
        'member-B': _profile('profile-B', 'member-B'),
      };
      for (final uid in byUid.keys) {
        await pumpEditor(tester, uid, (u) async => byUid[u]);
        await tester.pump();
        await tester.pump();
        final wizard = tester.widget<ProfileCreationScreen>(
          find.byType(ProfileCreationScreen),
        );
        expect(wizard.editProfileId, byUid[uid]!.id);
        expect(
          wizard.ownerUserId,
          uid,
          reason: 'saves go to the member, never to the signed-in admin',
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a profile owned by someone else is never opened', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        'member-A',
        (_) async => _profile('profile-B', 'member-B'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfileCreationScreen), findsNothing);
      expect(
        find.text('Profile does not belong to this member'),
        findsOneWidget,
      );
    });
  });

  group('admin editing is admin-only', () {
    test('a regular member cannot open the admin editor', () {
      final now = DateTime(2026);
      final member = UserModel(
        uid: 'u1',
        role: 'user',
        isProfileComplete: true,
        createdAt: now,
        updatedAt: now,
      );
      final redirect = resolveAuthRedirect(
        location: '/admin/user/someone/edit',
        isAuthenticated: true,
        userDocLoading: false,
        user: member,
      );
      expect(redirect, isNotNull);
      expect(redirect!.startsWith('/admin'), isFalse);
    });
  });
}
