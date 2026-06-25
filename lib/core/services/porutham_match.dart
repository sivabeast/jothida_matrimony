import '../constants/app_constants.dart';
import '../utils/horoscope_utils.dart';
import '../../models/profile_model.dart';

/// Result of a single Porutham (marriage-matching factor) check.
class PoruthamResult {
  final String name;
  final bool matched;
  final int points; // weight contributed when matched (0 otherwise)
  final int maxPoints; // weight if it had matched
  final String note;
  const PoruthamResult({
    required this.name,
    required this.matched,
    required this.points,
    required this.maxPoints,
    required this.note,
  });
}

/// Final compatibility category, derived ONLY from how many of the 10
/// poruthams matched — there is no percentage / score anywhere. Only FOUR
/// standardized categories are used app-wide.
enum MatchCategory { excellent, good, average, poor }

extension MatchCategoryInfo on MatchCategory {
  /// Human label shown to the user.
  String get label => switch (this) {
        MatchCategory.excellent => 'Excellent Match',
        MatchCategory.good => 'Good Match',
        MatchCategory.average => 'Average Match',
        MatchCategory.poor => 'Poor Match',
      };

  /// Status emoji used on the profile-card badge.
  String get emoji => switch (this) {
        MatchCategory.excellent => '🟢',
        MatchCategory.good => '🟡',
        MatchCategory.average => '🟠',
        MatchCategory.poor => '🔴',
      };
}

/// Map matched-porutham count (0-10) → one of the four standardized categories:
/// 8-10 → Excellent · 6-7 → Good · 4-5 → Average · 0-3 → Poor.
MatchCategory categoryFromMatched(int matched) {
  if (matched >= 8) return MatchCategory.excellent;
  if (matched >= 6) return MatchCategory.good;
  if (matched >= 4) return MatchCategory.average;
  return MatchCategory.poor;
}

/// Overall Thirumana Porutham (10-porutham) compatibility between two members.
///
/// Computed from each member's **Nakshatra** (star) and **Rasi** (moon sign)
/// using the classical South-Indian rules — NOT a percentage / heuristic. The
/// result is purely the count of matched poruthams and the derived category.
class PoruthamMatchResult {
  final int matchedCount; // poruthams that matched (0-10)
  final int totalCount; // always 10
  final List<PoruthamResult> poruthams;
  final MatchCategory category;
  final String recommendation;

  const PoruthamMatchResult({
    required this.matchedCount,
    required this.totalCount,
    required this.poruthams,
    required this.category,
    required this.recommendation,
  });

  List<PoruthamResult> get matching =>
      poruthams.where((p) => p.matched).toList();
  List<PoruthamResult> get nonMatching =>
      poruthams.where((p) => !p.matched).toList();
}

/// Compute the 10-porutham compatibility between the logged-in member [me] and
/// the accepted member [other]. Returns `null` when either side has no usable
/// star/rasi data (stored or derivable from the birth date).
PoruthamMatchResult? computePorutham(ProfileModel me, ProfileModel other) {
  final a = _Chart.from(me);
  final b = _Chart.from(other);
  if (a == null || b == null) return null;

  // Directional poruthams count from the bride's star to the groom's star.
  final bride = a.isFemale ? a : b;
  final groom = a.isFemale ? b : a;

  final results = <PoruthamResult>[
    _dina(bride, groom),
    _gana(bride, groom),
    _mahendra(bride, groom),
    _streeDheerga(bride, groom),
    _yoni(bride, groom),
    _rasi(bride, groom),
    _rasiAdhipathi(bride, groom),
    _vasya(bride, groom),
    _rajju(bride, groom),
    _vedha(bride, groom),
  ];

  final matched = results.where((r) => r.matched).length;
  final category = categoryFromMatched(matched);
  final recommendation = switch (category) {
    MatchCategory.excellent => 'Excellent marriage compatibility.',
    MatchCategory.good => 'Good marriage compatibility.',
    MatchCategory.average =>
      'Average compatibility — astrologer consultation suggested.',
    MatchCategory.poor =>
      'Poor compatibility — astrologer guidance strongly advised.',
  };

  return PoruthamMatchResult(
    matchedCount: matched,
    totalCount: results.length,
    poruthams: results,
    category: category,
    recommendation: recommendation,
  );
}

// ───────────────────────────────────────────────────────────────────────────
// Internal chart: resolves a member's nakshatra (1-27) and rasi (1-12) from
// stored horoscope fields, falling back to a derivation from the birth date.
// ───────────────────────────────────────────────────────────────────────────
class _Chart {
  final int star; // 1-27
  final int rasi; // 1-12
  final bool isFemale;
  const _Chart(this.star, this.rasi, this.isFemale);

  static _Chart? from(ProfileModel p) {
    final h = p.horoscope;
    var starIdx = AppConstants.nakshatraList.indexOf(h.nakshatra.trim());
    if (starIdx < 0 && h.nakshatra.trim().isEmpty) {
      starIdx =
          AppConstants.nakshatraList.indexOf(HoroscopeUtils.calculateNakshatra(p.dateOfBirth));
    }
    var rasiIdx = AppConstants.rasiList.indexOf(h.rasi.trim());
    if (rasiIdx < 0 && h.rasi.trim().isEmpty) {
      rasiIdx =
          AppConstants.rasiList.indexOf(HoroscopeUtils.calculateRasi(p.dateOfBirth));
    }
    if (starIdx < 0 || rasiIdx < 0) return null;
    final female = p.gender.trim().toLowerCase().startsWith('f');
    return _Chart(starIdx + 1, rasiIdx + 1, female);
  }
}

const _matched = 'Compatible';
const _notMatched = 'Needs attention';

// 1. Dina Porutham — health, prosperity, longevity.
PoruthamResult _dina(_Chart bride, _Chart groom) {
  final count = _count(bride.star, groom.star);
  final rem = count % 9;
  final ok = rem == 2 || rem == 4 || rem == 6 || rem == 8 || rem == 0;
  return PoruthamResult(
    name: 'Dina Porutham',
    matched: ok,
    points: ok ? 12 : 0,
    maxPoints: 12,
    note: ok ? _matched : _notMatched,
  );
}

// 2. Gana Porutham — temperament harmony (Deva / Manushya / Rakshasa).
PoruthamResult _gana(_Chart bride, _Chart groom) {
  final g1 = _gana3(bride.star); // bride
  final g2 = _gana3(groom.star); // groom
  // Same gana = best. Deva/Manushya pairings are acceptable. Any pairing with
  // Rakshasa across types is incompatible.
  final bool ok;
  if (g1 == g2) {
    ok = true;
  } else if ((g1 == 0 && g2 == 1) || (g1 == 1 && g2 == 0)) {
    ok = true; // Deva ↔ Manushya
  } else {
    ok = false;
  }
  return PoruthamResult(
    name: 'Gana Porutham',
    matched: ok,
    points: ok ? 12 : 0,
    maxPoints: 12,
    note: ok ? _matched : _notMatched,
  );
}

// 3. Mahendra Porutham — progeny and wellbeing.
PoruthamResult _mahendra(_Chart bride, _Chart groom) {
  final count = _count(bride.star, groom.star);
  const good = {4, 7, 10, 13, 16, 19, 22, 25};
  final ok = good.contains(count);
  return PoruthamResult(
    name: 'Mahendra Porutham',
    matched: ok,
    points: ok ? 8 : 0,
    maxPoints: 8,
    note: ok ? _matched : _notMatched,
  );
}

// 4. Sthree Dheerga Porutham — long married life / wellbeing of the bride.
PoruthamResult _streeDheerga(_Chart bride, _Chart groom) {
  final count = _count(bride.star, groom.star);
  final ok = count > 9; // groom's star well ahead of the bride's
  return PoruthamResult(
    name: 'Sthree Dheerga Porutham',
    matched: ok,
    points: ok ? 8 : 0,
    maxPoints: 8,
    note: ok ? _matched : _notMatched,
  );
}

// 5. Yoni Porutham — physical/biological compatibility (animal symbol).
PoruthamResult _yoni(_Chart bride, _Chart groom) {
  final y1 = _yoniOf(bride.star);
  final y2 = _yoniOf(groom.star);
  final bool ok;
  if (y1 == y2) {
    ok = true; // same yoni — excellent
  } else if (_yoniEnemies[y1] == y2) {
    ok = false; // natural enemies — incompatible
  } else {
    ok = true; // neutral / friendly
  }
  return PoruthamResult(
    name: 'Yoni Porutham',
    matched: ok,
    points: ok ? 12 : 0,
    maxPoints: 12,
    note: ok ? _matched : _notMatched,
  );
}

// 6. Rasi Porutham — avoids the 6-8 (Shashtashtaka) moon-sign affliction.
PoruthamResult _rasi(_Chart bride, _Chart groom) {
  final d = (groom.rasi - bride.rasi) % 12; // 0-11
  // 6th/8th from each other (count 5 or 7) is the principal rasi dosham.
  final ok = d != 5 && d != 7;
  return PoruthamResult(
    name: 'Rasi Porutham',
    matched: ok,
    points: ok ? 12 : 0,
    maxPoints: 12,
    note: ok ? _matched : _notMatched,
  );
}

// 7. Rasi Adhipathi Porutham — friendship of the two moon-sign lords.
PoruthamResult _rasiAdhipathi(_Chart bride, _Chart groom) {
  final l1 = _rasiLord[bride.rasi - 1];
  final l2 = _rasiLord[groom.rasi - 1];
  final ok = l1 == l2 || _planetFriends[l1]!.contains(l2);
  return PoruthamResult(
    name: 'Rasi Athipathi Porutham',
    matched: ok,
    points: ok ? 10 : 0,
    maxPoints: 10,
    note: ok ? _matched : _notMatched,
  );
}

// 8. Vasya Porutham — mutual attraction / magnetism between the signs.
PoruthamResult _vasya(_Chart bride, _Chart groom) {
  final ok = (_vasyaOf[bride.rasi] ?? const {}).contains(groom.rasi) ||
      (_vasyaOf[groom.rasi] ?? const {}).contains(bride.rasi);
  return PoruthamResult(
    name: 'Vasya Porutham',
    matched: ok,
    points: ok ? 8 : 0,
    maxPoints: 8,
    note: ok ? _matched : _notMatched,
  );
}

// 9. Rajju Porutham — most important; same Rajju group is inauspicious.
PoruthamResult _rajju(_Chart bride, _Chart groom) {
  final ok = _rajjuOf(bride.star) != _rajjuOf(groom.star);
  return PoruthamResult(
    name: 'Rajju Porutham',
    matched: ok,
    points: ok ? 12 : 0,
    maxPoints: 12,
    note: ok ? _matched : _notMatched,
  );
}

// 10. Vedha Porutham — certain star pairs obstruct each other.
PoruthamResult _vedha(_Chart bride, _Chart groom) {
  final ok = _vedhaPairs[bride.star] != groom.star;
  return PoruthamResult(
    name: 'Vedha Porutham',
    matched: ok,
    points: ok ? 6 : 0,
    maxPoints: 6,
    note: ok ? _matched : _notMatched,
  );
}

// ── Helpers & classical tables (nakshatra numbers are 1-27) ────────────────

/// Forward count from star [a] to star [b] in the 27-star cycle (1-27).
int _count(int a, int b) => ((b - a) % 27) + 1;

/// Gana: 0 = Deva, 1 = Manushya, 2 = Rakshasa.
int _gana3(int star) {
  const deva = {1, 5, 7, 8, 13, 15, 17, 22, 27};
  const manushya = {2, 4, 6, 11, 12, 20, 21, 25, 26};
  if (deva.contains(star)) return 0;
  if (manushya.contains(star)) return 1;
  return 2; // Rakshasa
}

/// Yoni animal symbol per nakshatra.
int _yoniOf(int star) => _yoniTable[star]!;
const Map<int, int> _yoniTable = {
  1: 0, // Horse
  2: 1, // Elephant
  3: 2, // Sheep
  4: 3, // Serpent
  5: 3, // Serpent
  6: 4, // Dog
  7: 5, // Cat
  8: 2, // Sheep
  9: 5, // Cat
  10: 6, // Rat
  11: 6, // Rat
  12: 7, // Cow
  13: 8, // Buffalo
  14: 9, // Tiger
  15: 8, // Buffalo
  16: 9, // Tiger
  17: 10, // Deer
  18: 10, // Deer
  19: 4, // Dog
  20: 11, // Monkey
  21: 12, // Mongoose
  22: 11, // Monkey
  23: 13, // Lion
  24: 0, // Horse
  25: 13, // Lion
  26: 7, // Cow
  27: 1, // Elephant
};
// Mutually hostile yoni animals.
const Map<int, int> _yoniEnemies = {
  0: 8, // Horse ↔ Buffalo
  8: 0,
  1: 13, // Elephant ↔ Lion
  13: 1,
  2: 11, // Sheep ↔ Monkey
  11: 2,
  3: 12, // Serpent ↔ Mongoose
  12: 3,
  5: 6, // Cat ↔ Rat
  6: 5,
  4: 10, // Dog ↔ Deer
  10: 4,
  7: 9, // Cow ↔ Tiger
  9: 7,
};

/// Rasi lords (index 0-11 → planet code). Planets: 0 Sun, 1 Moon, 2 Mars,
/// 3 Mercury, 4 Jupiter, 5 Venus, 6 Saturn.
const List<int> _rasiLord = [
  2, // Mesham — Mars
  5, // Rishabam — Venus
  3, // Mithunam — Mercury
  1, // Kadagam — Moon
  0, // Simmam — Sun
  3, // Kanni — Mercury
  5, // Thulam — Venus
  2, // Viruchigam — Mars
  4, // Dhanusu — Jupiter
  6, // Makaram — Saturn
  6, // Kumbam — Saturn
  4, // Meenam — Jupiter
];
// Natural planetary friendships (mutual or one-way treated as compatible).
const Map<int, Set<int>> _planetFriends = {
  0: {1, 2, 4}, // Sun: Moon, Mars, Jupiter
  1: {0, 3}, // Moon: Sun, Mercury
  2: {0, 1, 4}, // Mars: Sun, Moon, Jupiter
  3: {0, 5}, // Mercury: Sun, Venus
  4: {0, 1, 2}, // Jupiter: Sun, Moon, Mars
  5: {3, 6}, // Venus: Mercury, Saturn
  6: {3, 5}, // Saturn: Mercury, Venus
};

/// Vasya sets keyed by rasi (1-12) → rasis it holds sway over.
const Map<int, Set<int>> _vasyaOf = {
  1: {5, 8}, // Mesham → Simmam, Viruchigam
  2: {4, 7}, // Rishabam → Kadagam, Thulam
  3: {6}, // Mithunam → Kanni
  4: {8, 9}, // Kadagam → Viruchigam, Dhanusu
  5: {7}, // Simmam → Thulam
  6: {3, 12}, // Kanni → Mithunam, Meenam
  7: {6, 10}, // Thulam → Kanni, Makaram
  8: {4}, // Viruchigam → Kadagam
  9: {12}, // Dhanusu → Meenam
  10: {1, 11}, // Makaram → Mesham, Kumbam
  11: {1}, // Kumbam → Mesham
  12: {10}, // Meenam → Makaram
};

/// Rajju group: 0 Pada(foot), 1 Kati(waist), 2 Nabhi(navel), 3 Kanta(neck),
/// 4 Sira(head). Same group between partners is inauspicious.
int _rajjuOf(int star) {
  const pada = {1, 9, 10, 18, 19, 27};
  const kati = {2, 8, 11, 17, 20, 26};
  const nabhi = {3, 7, 12, 16, 21, 25};
  const kanta = {4, 6, 13, 15, 22, 24};
  if (pada.contains(star)) return 0;
  if (kati.contains(star)) return 1;
  if (nabhi.contains(star)) return 2;
  if (kanta.contains(star)) return 3;
  return 4; // Sira: 5, 14, 23
}

/// Mutually obstructing (vedha) star pairs.
const Map<int, int> _vedhaPairs = {
  1: 18, 18: 1,
  2: 17, 17: 2,
  3: 16, 16: 3,
  4: 15, 15: 4,
  5: 23, 23: 5,
  6: 22, 22: 6,
  7: 21, 21: 7,
  8: 20, 20: 8,
  9: 19, 19: 9,
  10: 27, 27: 10,
  11: 26, 26: 11,
  12: 25, 25: 12,
  13: 24, 24: 13,
};
