/// Places that MEMBERS add to the location list — the villages and localities
/// the bundled dataset does not carry (spec: "+ Add Place").
///
/// WHY THEY ARE NOT WRITTEN INTO `assets/master_data/location/*.json`: those
/// files are packed inside the APK and are read-only on the device, and the
/// project runs Firebase on the Spark plan with no Cloud Functions, so there is
/// no server process that could rewrite a JSON file either. The shared,
/// persistent store the app already has for "values the bundled master data is
/// missing" is Firestore `master_options/{type}` (the "+ Add" system). Member
/// places live there as ONE document, `master_options/places`, whose
/// `entries` array holds rows in the SAME shape as `cities_en.json`
/// (`{id, districtId, name}`) plus the parent state/country and the generic
/// "+ Add" fields (`v`, `p`). `LocationRepository` merges them into the bundled
/// rows, so every place picker, the name resolver and the Tamil registry see
/// one dataset. `tool/merge_place_additions.dart` folds an export of the
/// document back into the bundled JSON for a release.
///
/// Everything in this file is pure — no Firestore — so the validation, the
/// duplicate rules and the concurrency-safe append plan are unit-tested.
library;

import '../../models/location_model.dart';
import '../data/location_catalog.dart';
import '../data/master_option.dart';
import 'location_search.dart';

/// Ids of member-added places start here. The bundled rows use 1…~1,100, so
/// the ranges can never collide — even after a future release adds more
/// bundled towns — and a profile's stored `cityId` keeps pointing at the same
/// place forever.
const int kFirstAddedPlaceId = 100001;

/// The longest place name accepted.
const int kMaxPlaceNameLength = 60;

/// Where a new place sits in the location hierarchy.
enum PlaceParentKind {
  /// A town or village inside one of the Tamil Nadu districts.
  district,

  /// A place in another Indian state (the dataset has no districts there).
  state,

  /// A place outside India.
  country,
}

/// The parent a new place is filed under. A city belongs to its district and
/// state; a place in another state belongs to that state; a place abroad to
/// its country — never an unrelated global list.
class PlaceParent {
  final PlaceParentKind kind;

  /// Tamil Nadu district (only for [PlaceParentKind.district]).
  final int? districtId;
  final String districtEn;

  /// Canonical English state name and its catalogue id ('' abroad).
  final String state;
  final String stateId;

  /// Canonical English country name.
  final String country;

  const PlaceParent._({
    required this.kind,
    this.districtId,
    this.districtEn = '',
    this.state = '',
    this.stateId = '',
    this.country = kDefaultCountry,
  });

  factory PlaceParent.district(TnDistrict d) => PlaceParent._(
    kind: PlaceParentKind.district,
    districtId: d.id,
    districtEn: d.nameEn,
    state: TnState.nameEn,
    stateId: 'st_tn',
  );

  factory PlaceParent.state(MasterOption s) =>
      PlaceParent._(kind: PlaceParentKind.state, state: s.en, stateId: s.id);

  factory PlaceParent.country(MasterOption c) =>
      PlaceParent._(kind: PlaceParentKind.country, country: c.en);

  /// The scope inside which two places with the same name are duplicates.
  /// The same village name in two different districts is NOT a duplicate —
  /// telling those apart is the point of the hierarchy.
  String get scopeKey => switch (kind) {
    PlaceParentKind.district => 'd:$districtId',
    PlaceParentKind.state =>
      's:${stateId.isEmpty ? placeText(state) : stateId}',
    PlaceParentKind.country => 'c:${placeText(country)}',
  };
}

/// One member-added place.
class PlaceAddition {
  final int id;

  /// The name as entered (normalised: trimmed, single spaces, title-cased
  /// when it was typed all in one case).
  final String name;

  /// Tamil display name when known — '' falls back to [name].
  final String nameTa;

  /// Tamil Nadu district id, or null for a place outside Tamil Nadu.
  final int? districtId;

  /// Canonical English state ('' for a place abroad) and its catalogue id.
  final String state;
  final String stateId;

  final String country;

  /// Duplicate-detection key: `scope|name key`.
  final String key;

  /// Who added it and when (epoch milliseconds) — for moderation.
  final String addedBy;
  final int addedAt;

  const PlaceAddition({
    required this.id,
    required this.name,
    this.nameTa = '',
    this.districtId,
    this.state = '',
    this.stateId = '',
    this.country = kDefaultCountry,
    required this.key,
    this.addedBy = '',
    this.addedAt = 0,
  });

  bool get isTamilNadu => districtId != null;

  String nameFor(String lang) =>
      lang == 'ta' && nameTa.trim().isNotEmpty ? nameTa : name;

  /// The row as it is stored. `id`, `districtId`, `name` are exactly the
  /// `cities_en.json` columns; `v`/`p` are the fields every `master_options`
  /// entry carries.
  Map<String, dynamic> toMap() => {
    'id': id,
    'districtId': districtId,
    'name': name,
    if (nameTa.trim().isNotEmpty) 'nameTa': nameTa,
    'state': state,
    'stateId': stateId,
    'country': country,
    'v': name,
    'p': key.split('|').first,
    'k': key,
    'by': addedBy,
    'at': addedAt,
  };

  /// Defensive parse — null for a row that is not a usable place (a legacy or
  /// hand-edited entry), which is then left untouched in storage and ignored.
  static PlaceAddition? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = '${raw['name'] ?? raw['v'] ?? ''}'.trim();
    if (id is! num || name.isEmpty) return null;
    final districtRaw = raw['districtId'];
    final districtId = districtRaw is num
        ? districtRaw.toInt()
        : int.tryParse('${districtRaw ?? ''}');
    final country = '${raw['country'] ?? ''}'.trim();
    final state = '${raw['state'] ?? ''}'.trim();
    final stateId = '${raw['stateId'] ?? ''}'.trim();
    final parent = districtId != null
        ? 'd:$districtId'
        : state.isNotEmpty
        ? 's:${stateId.isEmpty ? placeText(state) : stateId}'
        : 'c:${placeText(country.isEmpty ? kDefaultCountry : country)}';
    final storedKey = '${raw['k'] ?? ''}'.trim();
    return PlaceAddition(
      id: id.toInt(),
      name: name,
      nameTa: '${raw['nameTa'] ?? ''}'.trim(),
      districtId: districtId,
      state: districtId != null ? TnState.nameEn : state,
      stateId: districtId != null ? 'st_tn' : stateId,
      country: country.isEmpty ? kDefaultCountry : country,
      key: storedKey.isNotEmpty ? storedKey : '$parent|${placeNameKey(name)}',
      addedBy: '${raw['by'] ?? ''}',
      addedAt: raw['at'] is num ? (raw['at'] as num).toInt() : 0,
    );
  }

  /// The Tamil Nadu town row this place becomes inside the location dataset.
  TnCity? toTnCity() => districtId == null
      ? null
      : TnCity(
          id: id,
          districtId: districtId!,
          nameEn: name,
          nameTa: nameTa.trim().isEmpty ? name : nameTa,
        );

  /// "Kerala, India" / "UAE" — the subtitle for a place outside Tamil Nadu.
  String get parentLabel =>
      [state, country].where((s) => s.trim().isNotEmpty).join(', ');

  /// The picker selection for a place OUTSIDE Tamil Nadu (Tamil Nadu places go
  /// through their [PlaceOption] so they carry the district).
  PlaceSelection toSelection(String lang) => PlaceSelection(
    city: nameFor(lang),
    cityEn: name,
    state: state,
    country: country,
    // Not a Tamil Nadu dataset row, so the profile keeps no numeric city id
    // for it — exactly like any other place outside the dataset.
    custom: true,
  );
}

// ── Validation ──────────────────────────────────────────────────────────────

/// Why a typed place name was refused.
enum PlaceNameProblem { empty, tooShort, tooLong, invalidCharacters }

/// Latin letters, Tamil script, spaces and the punctuation real place names
/// use ("St. Thomas Mount", "Ooty (Udhagamandalam)", "Kil-Ayur"). Digits and
/// symbols are refused, which also keeps phone numbers, pin codes, e-mail
/// addresses and links out of a list every member sees.
final RegExp _allowedPlaceChars = RegExp(r"^[A-Za-z஀-௿ .'()\-]+$");
final RegExp _placeLetter = RegExp(r'[A-Za-z஀-௿]');

/// Normalises [raw] (trim, single spaces, stray separators removed, and a name
/// typed all in lower or all in upper case title-cased) and validates it.
({String name, PlaceNameProblem? problem}) checkPlaceName(String raw) {
  var name = raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[,.\-\s]+|[,\-\s]+$'), '')
      .trim();
  if (name.isEmpty) return (name: '', problem: PlaceNameProblem.empty);
  if (!_allowedPlaceChars.hasMatch(name)) {
    return (name: name, problem: PlaceNameProblem.invalidCharacters);
  }
  if (_placeLetter.allMatches(name).length < 2) {
    return (name: name, problem: PlaceNameProblem.tooShort);
  }
  if (name.length > kMaxPlaceNameLength) {
    return (name: name, problem: PlaceNameProblem.tooLong);
  }
  final latin = name.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (latin.isNotEmpty &&
      (latin == latin.toLowerCase() || latin == latin.toUpperCase())) {
    name = name.splitMapJoin(
      RegExp(r"[A-Za-z]+"),
      onMatch: (m) {
        final w = m[0]!;
        return w[0].toUpperCase() + w.substring(1).toLowerCase();
      },
    );
  }
  return (name: name, problem: null);
}

/// The duplicate-detection key of a place name: capitalisation, spacing,
/// punctuation and common Tamil→English transliteration differences
/// ("Kovilpati" / "kovil patti") all collapse to one key. A name written in
/// Tamil script keys on its normalised Tamil text.
String placeNameKey(String name) {
  final latin = placeKey(name);
  if (latin.isNotEmpty) return latin;
  return placeText(name).replaceAll(' ', '');
}

/// `scope|name key` for [name] filed under [parent].
String placeAdditionKey(String name, PlaceParent parent) =>
    '${parent.scopeKey}|${placeNameKey(name)}';

// ── The append plan (runs inside a Firestore transaction) ─────────────────

/// What saving a place resolves to, computed from the document's CURRENT
/// contents.
class PlaceAdditionPlan {
  /// The place already on the list (same name, same parent) — select it, do
  /// not write anything.
  final PlaceAddition? existing;

  /// The new place, when one is appended.
  final PlaceAddition? added;

  /// The complete `entries` array to write: every existing raw entry
  /// untouched and in order, plus [added].
  final List<Object?> entries;

  /// The id counter to store after this append.
  final int nextId;

  const PlaceAdditionPlan._({
    this.existing,
    this.added,
    required this.entries,
    required this.nextId,
  });

  bool get isDuplicate => existing != null;
}

/// Plans appending [name] under [parent] to a document holding [rawEntries]
/// and the id counter [storedNextId].
///
/// Run inside a transaction this is safe under concurrency: the transaction
/// re-runs the plan on the latest document whenever another member's append
/// landed first, so an append never replaces someone else's entry, the same
/// place added twice at once resolves to ONE row, and ids stay unique.
PlaceAdditionPlan planPlaceAddition({
  required List<Object?> rawEntries,
  required int? storedNextId,
  required String name,
  required PlaceParent parent,
  required String addedBy,
  required int now,
}) {
  final key = placeAdditionKey(name, parent);
  var maxId = kFirstAddedPlaceId - 1;
  for (final raw in rawEntries) {
    final place = PlaceAddition.fromMap(raw);
    if (place == null) continue;
    if (place.key == key) {
      return PlaceAdditionPlan._(
        existing: place,
        entries: rawEntries,
        nextId: storedNextId ?? kFirstAddedPlaceId,
      );
    }
    if (place.id > maxId) maxId = place.id;
  }
  var id = storedNextId ?? kFirstAddedPlaceId;
  if (id <= maxId) id = maxId + 1;
  if (id < kFirstAddedPlaceId) id = kFirstAddedPlaceId;
  final added = PlaceAddition(
    id: id,
    name: name,
    districtId: parent.districtId,
    state: parent.state,
    stateId: parent.stateId,
    country: parent.country,
    key: key,
    addedBy: addedBy,
    addedAt: now,
  );
  return PlaceAdditionPlan._(
    added: added,
    entries: [...rawEntries, added.toMap()],
    nextId: id + 1,
  );
}

/// Parses every usable place in [rawEntries]. When two rows share a key (two
/// old clients raced), the FIRST one wins, so the list never shows a place
/// twice.
List<PlaceAddition> parsePlaceAdditions(List<Object?> rawEntries) {
  final seen = <String>{};
  final out = <PlaceAddition>[];
  for (final raw in rawEntries) {
    final place = PlaceAddition.fromMap(raw);
    if (place != null && seen.add(place.key)) out.add(place);
  }
  return out;
}

// ── Reading the parent out of what was typed ────────────────────────────────

/// A country other than India named in [text] ("Dubai, UAE" → UAE).
MasterOption? countryNamedIn(String text) {
  final parts = text.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty);
  for (final part in parts.toList().reversed) {
    final t = placeText(part);
    for (final c in LocationCatalog.countries) {
      if (c.id == 'ctry_india' || c.id == 'ctry_other') continue;
      if (placeText(c.en) == t ||
          placeText(c.ta) == t ||
          c.aliases.any((a) => placeText(a) == t)) {
        return c;
      }
    }
  }
  return null;
}

/// The place part of a typed "Place, District" / "Place, State" query.
String placePartOf(String text) {
  final first = text.split(',').first.trim();
  return first.isEmpty ? text.trim() : first;
}
