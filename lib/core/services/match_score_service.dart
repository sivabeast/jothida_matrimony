import '../../models/profile_model.dart';

/// The computed compatibility between the signed-in user and a candidate
/// profile, expressed as a 0–100 percentage with a per-factor breakdown.
class MatchScore {
  /// 0–100, already clamped to a display-friendly range.
  final int percent;

  /// Points contributed by each factor (for an optional "why this match"
  /// breakdown). Keys: age, education, location, occupation, religion, caste,
  /// preferences.
  final Map<String, int> breakdown;

  const MatchScore(this.percent, this.breakdown);

  /// Match QUALITY label — NO percentage is ever shown to users.
  /// "Excellent Match" ≥ 80, "Good Match" ≥ 60, "Average Match" otherwise.
  String get quality {
    if (percent >= 80) return 'Excellent Match';
    if (percent >= 60) return 'Good Match';
    return 'Average Match';
  }

  /// Single-word quality for dense badges ("Excellent" / "Good" / "Average").
  String get shortQuality {
    if (percent >= 80) return 'Excellent';
    if (percent >= 60) return 'Good';
    return 'Average';
  }

  /// Back-compat alias for callers that used to print a "% Match" chip — now
  /// always the quality label, never a percentage.
  String get label => quality;

  /// Coarse bucket used to colour the badge — aligned with [quality].
  /// excellent ≥ 80, good ≥ 60, average otherwise.
  String get tier {
    if (percent >= 80) return 'excellent';
    if (percent >= 60) return 'good';
    return 'average';
  }
}

/// Computes a profile-compatibility score between two members.
///
/// The raw percentage is used only internally (ranking); the UI shows the
/// coarse [MatchScore.quality] label ("Excellent / Good / Average Match") and
/// never a percentage — distinct from the astrological *porutham* (10-kūṭa)
/// matching in [porutham_match.dart], which only compares Rasi/Nakshatra.
///
/// The score blends raw attribute similarity (age, education, location,
/// occupation, religion, caste — 75 pts) with how well the candidate satisfies
/// the viewer's stated [PartnerPreferences] (25 pts). All inputs are tolerant
/// of empty/legacy values and the result is clamped to a realistic [40, 99]
/// display band so cards never show absurd 0%/100% figures.
class MatchScoreService {
  const MatchScoreService._();

  // Factor weights (sum = 100). 75 from attribute similarity, 25 from prefs.
  static const int _wAge = 15;
  static const int _wEducation = 10;
  static const int _wLocation = 15;
  static const int _wOccupation = 10;
  static const int _wReligion = 15;
  static const int _wCaste = 10;
  static const int _wPreferences = 25;

  /// Compatibility of [candidate] for [viewer] (the signed-in user). The
  /// preference portion is evaluated from the **viewer's** [PartnerPreferences].
  static MatchScore compute({
    required ProfileModel viewer,
    required ProfileModel candidate,
  }) {
    final age = _ageScore(viewer.age, candidate.age);
    final edu = _stringScore(
      viewer.education,
      candidate.education,
      exact: _wEducation,
      bothPresent: 5,
      base: 2,
    );
    final loc = _locationScore(viewer, candidate);
    final occ = _stringScore(
      viewer.occupation,
      candidate.occupation,
      exact: _wOccupation,
      bothPresent: 5,
      base: 2,
    );
    final rel = _categoricalScore(
      viewer.religion,
      candidate.religion,
      equal: _wReligion,
      oneEmpty: 7,
      different: 0,
    );
    final caste = _categoricalScore(
      viewer.caste ?? '',
      candidate.caste ?? '',
      equal: _wCaste,
      oneEmpty: 5,
      different: 2,
    );
    final prefs = _preferenceScore(viewer.partnerPreferences, candidate);

    final breakdown = <String, int>{
      'age': age,
      'education': edu,
      'location': loc,
      'occupation': occ,
      'religion': rel,
      'caste': caste,
      'preferences': prefs,
    };

    final raw = breakdown.values.fold<int>(0, (a, b) => a + b);
    final percent = raw.clamp(40, 99);
    return MatchScore(percent, breakdown);
  }

  /// Sorts [candidates] by descending compatibility for [viewer].
  /// Returns a new list of (profile, score) pairs.
  static List<MapEntry<ProfileModel, MatchScore>> rank({
    required ProfileModel viewer,
    required List<ProfileModel> candidates,
  }) {
    final scored = candidates
        .map((c) => MapEntry(c, compute(viewer: viewer, candidate: c)))
        .toList()
      ..sort((a, b) => b.value.percent.compareTo(a.value.percent));
    return scored;
  }

  // ── Factor scorers ─────────────────────────────────────────────────────────

  static int _ageScore(int a, int b) {
    if (a <= 0 || b <= 0) return (_wAge * 0.6).round();
    final diff = (a - b).abs();
    final pts = _wAge * (1 - diff / 12);
    return pts.clamp(0, _wAge).round();
  }

  static int _stringScore(
    String a,
    String b, {
    required int exact,
    required int bothPresent,
    required int base,
  }) {
    final na = _norm(a), nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return base;
    if (na == nb || na.contains(nb) || nb.contains(na)) return exact;
    return bothPresent;
  }

  static int _categoricalScore(
    String a,
    String b, {
    required int equal,
    required int oneEmpty,
    required int different,
  }) {
    final na = _norm(a), nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return oneEmpty;
    return na == nb ? equal : different;
  }

  static int _locationScore(ProfileModel v, ProfileModel c) {
    if (_eq(v.city, c.city)) return _wLocation;
    if (_eq(v.district, c.district)) return (_wLocation * 0.8).round();
    if (_eq(v.state, c.state)) return (_wLocation * 0.6).round();
    if (_eq(v.country, c.country)) return (_wLocation * 0.33).round();
    return 2;
  }

  /// 0–25 based on the fraction of the viewer's *specified* preferences the
  /// candidate satisfies. With no preferences set, returns a neutral 18.
  static int _preferenceScore(PartnerPreferences p, ProfileModel c) {
    var specified = 0;
    var satisfied = 0;

    void check(bool isSpecified, bool ok) {
      if (!isSpecified) return;
      specified++;
      if (ok) satisfied++;
    }

    // Age range (always considered specified).
    check(true, c.age >= p.minAge && c.age <= p.maxAge);

    // Height range (only when all three heights parse).
    final lo = _heightInches(p.minHeight);
    final hi = _heightInches(p.maxHeight);
    final ch = _heightInches(c.height);
    if (lo != null && hi != null && ch != null) {
      check(true, ch >= lo - 0.5 && ch <= hi + 0.5);
    }

    check(p.education.isNotEmpty, _listContains(p.education, c.education));
    check(p.occupation.isNotEmpty, _listContains(p.occupation, c.occupation));
    check(_isSet(p.income), _eq(p.income, c.annualIncome));
    check(_isSet(p.religion), _eq(p.religion, c.religion));
    check(_isSet(p.caste), _eq(p.caste ?? '', c.caste ?? ''));
    check(_isSet(p.subCaste), _eq(p.subCaste ?? '', c.subCaste ?? ''));
    check(_isSet(p.city), _eq(p.city ?? '', c.city));
    check(_isSet(p.state), _eq(p.state ?? '', c.state));
    check(_isSet(p.maritalStatus), _eq(p.maritalStatus, c.maritalStatus));
    check(_isSet(p.physicalStatus), _eq(p.physicalStatus, c.physicalStatus));
    check(_isSet(p.employmentType), _eq(p.employmentType, c.employmentType));
    check(_isSet(p.motherTongue), _eq(p.motherTongue, c.motherTongue));
    check(_isSet(p.rasi ?? ''), _eq(p.rasi ?? '', c.horoscope.rasi));
    check(_isSet(p.nakshatra ?? ''),
        _eq(p.nakshatra ?? '', c.horoscope.nakshatra));

    if (specified == 0) return (_wPreferences * 0.72).round(); // neutral 18
    return (_wPreferences * satisfied / specified).round();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _eq(String a, String b) {
    final na = _norm(a), nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  /// A preference value counts as "set" when it is non-empty and not the
  /// "Any" sentinel used throughout the preference UI.
  static bool _isSet(String? v) {
    final n = _norm(v ?? '');
    return n.isNotEmpty && n != 'any';
  }

  static bool _listContains(List<String> list, String value) {
    final nv = _norm(value);
    if (nv.isEmpty) return false;
    return list.any((e) {
      final ne = _norm(e);
      return ne.isNotEmpty && (ne == nv || ne.contains(nv) || nv.contains(ne));
    });
  }

  /// Best-effort height → inches. Handles `5'10"`, `5' 10`, `5ft 10in`,
  /// `5.10` (feet.inches), `175 cm`, and bare numbers. Returns null when
  /// nothing sensible can be parsed.
  static double? _heightInches(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;

    final cm = RegExp(r'(\d+(?:\.\d+)?)\s*cm').firstMatch(s);
    if (cm != null) return double.parse(cm.group(1)!) / 2.54;

    final fi = RegExp(r"(\d+)\s*(?:'|’|ft|feet|foot)\s*(\d+(?:\.\d+)?)?")
        .firstMatch(s);
    if (fi != null) {
      final ft = int.parse(fi.group(1)!);
      final double inch =
          fi.group(2) != null ? double.parse(fi.group(2)!) : 0.0;
      return ft * 12 + inch;
    }

    final dec = RegExp(r'^(\d)[.,](\d{1,2})$').firstMatch(s);
    if (dec != null) {
      return int.parse(dec.group(1)!) * 12 + double.parse(dec.group(2)!);
    }

    final n = RegExp(r'^(\d+(?:\.\d+)?)$').firstMatch(s);
    if (n != null) {
      final v = double.parse(n.group(1)!);
      if (v > 90) return v / 2.54; // looks like cm
      if (v >= 4 && v <= 8) return v * 12; // looks like feet
    }
    return null;
  }
}
