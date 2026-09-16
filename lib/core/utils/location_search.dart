/// The ONE location search used by every place field — profile location,
/// native place, horoscope birth place, the second person's birth place and
/// partner-preference location (spec §23–§39).
///
/// Built once from the bundled location JSON (see `LocationRepository`), then
/// queried in memory — no network, no re-parsing per keystroke.
///
/// WHY places like "Virudhunagar" or "Kancheepuram" did not come up:
///
///  * The old search compared the query against CITY names only. A member who
///    typed their DISTRICT's name found nothing unless a town with the exact
///    same spelling existed — and for several districts the head-quarters town
///    is spelt differently in the dataset: district "Kancheepuram" / town
///    "Kanchipuram", "Viluppuram" / "Villupuram", "Kanniyakumari" /
///    "Kanyakumari", "Thoothukudi" / "Thoothukkudi", "Kallakurichi" /
///    "Kallakkurichi". Two districts (Tirunelveli, Tiruvannamalai) had no
///    same-name town row at all; the JSON now carries them.
///  * Nothing tolerated Tamil-to-English transliteration differences (th/t,
///    dh/d, ee/i, doubled consonants), so "Viruthunagar" or "Thanjavoor" failed.
///
/// Now a query is matched against town names, district names (and the known
/// district nicknames), with a transliteration-tolerant key, and ranked:
/// exact town → town prefix → district head-quarters town → other towns of that
/// district → contains / loose matches. Every result carries its district and
/// state, so identical names in different districts are never confused. When
/// nothing matches — a small locality missing from the data — the closest
/// recognised towns are offered instead, so the member always has a valid,
/// selectable place.
library;

import '../../models/location_model.dart';
import '../data/location_catalog.dart';

/// A spelling-tolerant key for Tamil place names written in English:
/// lower-case letters only, common transliteration pairs folded
/// (th→t, dh→d, zh→l, ee→i, oo→u, iy→y…) and doubled letters collapsed, and
/// the words "district", "dist", "the", "town", "city" ignored.
String placeKey(String name) {
  var k = name.toLowerCase();
  k = k.replaceAll(RegExp(r'\b(district|dist|the|town|city)\b'), ' ');
  k = k.replaceAll(RegExp(r'[^a-z]'), '');
  const folds = <List<String>>[
    ['th', 't'],
    ['dh', 'd'],
    ['zh', 'l'],
    ['bh', 'b'],
    ['kh', 'k'],
    ['ph', 'p'],
    ['sh', 's'],
    ['ee', 'i'],
    ['ii', 'i'],
    ['oo', 'u'],
    ['uu', 'u'],
    ['aa', 'a'],
    ['iy', 'y'],
    ['w', 'v'],
  ];
  for (final f in folds) {
    k = k.replaceAll(f[0], f[1]);
  }
  return k.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
}

/// A plain comparable form that keeps Tamil script: lower-case, punctuation
/// removed, spaces collapsed.
String placeText(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9஀-௿ ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// One search hit.
class PlaceSearchHit {
  final PlaceOption option;
  final int score;

  /// True when the hit came from the DISTRICT name rather than the town name
  /// (the town is shown because it belongs to the district searched).
  final bool viaDistrict;

  const PlaceSearchHit(this.option, this.score, {this.viaDistrict = false});
}

/// Result of [PlaceSearchIndex.search].
class PlaceSearchResult {
  final List<PlaceSearchHit> hits;

  /// True when there was no direct match and [hits] are the closest
  /// recognised towns — the "your locality is not listed" fallback.
  final bool isFallback;

  const PlaceSearchResult(this.hits, {this.isFallback = false});
}

class _Entry {
  final PlaceOption option;
  final String cityText; // English, placeText
  final String cityTa; // Tamil, placeText
  final String cityKey;
  final bool isDistrictHq;

  _Entry(this.option, {required this.isDistrictHq})
      : cityText = placeText(option.city.nameEn),
        cityTa = placeText(option.city.nameTa),
        cityKey = placeKey(option.city.nameEn);
}

class _District {
  final TnDistrict district;
  final List<String> texts; // English + Tamil + aliases, placeText
  final List<String> keys; // placeKey of English name + aliases

  _District(this.district, List<String> aliases)
      : texts = [
          placeText(district.nameEn),
          placeText(district.nameTa),
          for (final a in aliases) placeText(a),
        ],
        keys = {
          placeKey(district.nameEn),
          for (final a in aliases) placeKey(a),
        }.where((k) => k.isNotEmpty).toList();
}

class PlaceSearchIndex {
  final List<_Entry> _entries;
  final Map<int, _District> _districts;

  PlaceSearchIndex._(this._entries, this._districts);

  /// Builds the index from the location dataset. Pure and cheap (a single
  /// pass); build it once and keep it.
  factory PlaceSearchIndex.build({
    required List<TnDistrict> districts,
    required List<TnCity> cities,
  }) {
    final byId = <int, _District>{
      for (final d in districts) d.id: _District(d, _aliasesFor(d)),
    };
    final entries = <_Entry>[];
    for (final c in cities) {
      final d = byId[c.districtId];
      if (d == null) continue;
      final key = placeKey(c.nameEn);
      // The district's head-quarters town: same name as the district (allowing
      // for transliteration), or starting with one of its known nicknames
      // (e.g. "Ooty (Udhagamandalam)" for the Nilgiris).
      final hq = key.isNotEmpty &&
          d.keys.any((k) => k == key || (k.length >= 3 && key.startsWith(k)));
      entries.add(_Entry(PlaceOption(city: c, district: d.district),
          isDistrictHq: hq));
    }
    return PlaceSearchIndex._(entries, byId);
  }

  /// Builds the index from already-joined [PlaceOption]s (every town with its
  /// district) — the same list the place providers serve.
  factory PlaceSearchIndex.fromOptions(List<PlaceOption> options) {
    final districts = <int, TnDistrict>{};
    final cities = <TnCity>[];
    for (final o in options) {
      districts[o.district.id] = o.district;
      cities.add(o.city);
    }
    return PlaceSearchIndex.build(
        districts: districts.values.toList(), cities: cities);
  }

  /// Known nicknames of [d] from [LocationCatalog.districtAliases], matched to
  /// the dataset's district by the same transliteration-tolerant key (the
  /// catalogue spells some districts differently from the JSON).
  static List<String> _aliasesFor(TnDistrict d) {
    final key = placeKey(d.nameEn);
    for (final entry in LocationCatalog.districtAliases.entries) {
      final k = placeKey(entry.key);
      if (k == key ||
          (k.length >= 5 && key.length >= 5 && (k.startsWith(key) || key.startsWith(k)))) {
        return [entry.key, ...entry.value];
      }
    }
    return const [];
  }

  /// Every district row, alphabetical.
  List<TnDistrict> get districts =>
      _districts.values.map((d) => d.district).toList()
        ..sort((a, b) => a.nameEn.compareTo(b.nameEn));

  /// Searches [query]. Needs at least two characters.
  PlaceSearchResult search(String query, {int limit = 60}) {
    final q = placeText(query);
    if (q.length < 2) return const PlaceSearchResult([]);
    final qk = placeKey(query);

    // Districts the query names (exactly or as a prefix).
    final exactDistricts = <int>{};
    final prefixDistricts = <int>{};
    for (final d in _districts.values) {
      final exact = d.texts.contains(q) || (qk.isNotEmpty && d.keys.contains(qk));
      if (exact) {
        exactDistricts.add(d.district.id);
      } else if (d.texts.any((t) => t.startsWith(q)) ||
          (qk.length >= 3 && d.keys.any((k) => k.startsWith(qk)))) {
        prefixDistricts.add(d.district.id);
      }
    }

    final hits = <PlaceSearchHit>[];
    for (final e in _entries) {
      var score = 0;
      var viaDistrict = false;
      if (e.cityText == q || e.cityTa == q) {
        score = 100;
      } else if (qk.isNotEmpty && e.cityKey == qk) {
        score = 90;
      } else if (e.cityText.startsWith(q) || e.cityTa.startsWith(q)) {
        score = 80;
      } else if (qk.length >= 3 && e.cityKey.startsWith(qk)) {
        score = 70;
      }
      final districtId = e.option.district.id;
      if (exactDistricts.contains(districtId)) {
        final s = e.isDistrictHq ? 95 : 40;
        if (s > score) {
          score = s;
          viaDistrict = true;
        }
      } else if (prefixDistricts.contains(districtId)) {
        final s = e.isDistrictHq ? 60 : 20;
        if (s > score) {
          score = s;
          viaDistrict = true;
        }
      }
      if (score == 0 &&
          (e.cityText.contains(q) ||
              e.cityTa.contains(q) ||
              (qk.length >= 4 && e.cityKey.contains(qk)))) {
        score = 30;
      }
      if (score > 0) {
        hits.add(PlaceSearchHit(e.option, score, viaDistrict: viaDistrict));
      }
    }

    if (hits.isNotEmpty) {
      hits.sort(_byRelevance);
      return PlaceSearchResult(hits.take(limit).toList());
    }

    // Nothing matched — the exact locality is not in the data. Offer the
    // closest recognised towns rather than an empty list.
    if (qk.length < 3) return const PlaceSearchResult([]);
    final near = <PlaceSearchHit>[];
    for (final e in _entries) {
      final s = _similarity(qk, e.cityKey);
      if (s >= 0.5) {
        near.add(PlaceSearchHit(e.option, (s * 100).round()));
      }
    }
    near.sort(_byRelevance);
    return PlaceSearchResult(near.take(8).toList(), isFallback: near.isNotEmpty);
  }

  /// The district head-quarters town of [districtId], if the data has one —
  /// the recognised main town offered for a district.
  PlaceOption? headquartersOf(int districtId) {
    for (final e in _entries) {
      if (e.option.district.id == districtId && e.isDistrictHq) return e.option;
    }
    return null;
  }

  static int _byRelevance(PlaceSearchHit a, PlaceSearchHit b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byCity = a.option.city.nameEn.compareTo(b.option.city.nameEn);
    return byCity != 0
        ? byCity
        : a.option.district.nameEn.compareTo(b.option.district.nameEn);
  }

  /// Dice coefficient over letter bigrams — a cheap "looks like" measure.
  static double _similarity(String a, String b) {
    if (a.length < 2 || b.length < 2) return 0;
    final grams = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      final g = a.substring(i, i + 2);
      grams[g] = (grams[g] ?? 0) + 1;
    }
    var overlap = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final g = b.substring(i, i + 2);
      final n = grams[g] ?? 0;
      if (n > 0) {
        overlap++;
        grams[g] = n - 1;
      }
    }
    return (2 * overlap) / ((a.length - 1) + (b.length - 1));
  }
}

/// A state (other than the one the dataset covers in depth) named in a
/// free-typed place such as "Kochi, Kerala" — so a place outside the listed
/// data still records its real state instead of defaulting to Tamil Nadu.
String? stateNamedIn(String text) {
  final parts = text.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty);
  for (final part in parts.toList().reversed) {
    final t = placeText(part);
    for (final s in LocationCatalog.indianStates) {
      if (s.id == 'st_other') continue;
      if (placeText(s.en) == t ||
          placeText(s.ta) == t ||
          s.aliases.any((a) => placeText(a) == t)) {
        return s.en;
      }
    }
  }
  return null;
}
