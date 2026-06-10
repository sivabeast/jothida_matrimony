import 'package:flutter/material.dart';
import '../../models/profile_model.dart';

/// One of the 10 Thirumana Poruthams (Tamil marriage-matching factors).
class PoruthamItem {
  final String name;
  final bool matched;
  final String note;
  const PoruthamItem(this.name, this.matched, this.note);
}

/// A scored compatibility category (e.g. Education, Location, Rasi).
class CompatibilityCategory {
  final String label;
  final IconData icon;
  final int score; // 0-100
  final String detail;
  const CompatibilityCategory(this.label, this.icon, this.score, this.detail);

  bool get isStrong => score >= 75;
}

/// Full compatibility result between two profiles. Computed deterministically
/// so the same pair always shows the same numbers (sample/heuristic only —
/// NOT real astrological computation).
///
/// TODO(astrology): replace these heuristics with a real porutham engine or an
/// astrologer-verified calculation when the backend is available.
class CompatibilityResult {
  final int matchPercent;
  final int matchedPoruthams;
  final int totalPoruthams;
  final List<PoruthamItem> poruthams;
  final List<CompatibilityCategory> categories;
  final List<String> strengths;
  final List<String> concerns;
  final String verdict;

  const CompatibilityResult({
    required this.matchPercent,
    required this.matchedPoruthams,
    required this.totalPoruthams,
    required this.poruthams,
    required this.categories,
    required this.strengths,
    required this.concerns,
    required this.verdict,
  });
}

const List<String> _poruthamNames = [
  'Dina',
  'Gana',
  'Mahendra',
  'Stree Deergha',
  'Yoni',
  'Rasi',
  'Rasi Adhipathi',
  'Vasya',
  'Rajju',
  'Vedha',
];

/// Compute a deterministic, sample compatibility between the logged-in user
/// ([me], may be null in demo mode) and [other].
CompatibilityResult computeCompatibility(ProfileModel? me, ProfileModel other) {
  final seed = ((me?.id ?? 'self').hashCode ^ other.id.hashCode).abs();
  int rnd(int salt, int mod) => ((seed ~/ (salt + 1)) + salt * 31) % mod;

  // ── Category scores ───────────────────────────────────────────────────
  final categories = <CompatibilityCategory>[];

  // Education
  final eduScore = _likeness(me?.education, other.education, base: 70, salt: seed + 1);
  categories.add(CompatibilityCategory('Education', Icons.school_outlined,
      eduScore, other.education));

  // Career / Occupation
  final careerScore = 65 + rnd(3, 31);
  categories.add(CompatibilityCategory('Career', Icons.work_outline,
      careerScore, other.occupation));

  // Location
  int locScore;
  String locDetail;
  if (me != null && me.city == other.city) {
    locScore = 100;
    locDetail = 'Same city · ${other.city}';
  } else if (me != null && me.state == other.state) {
    locScore = 78;
    locDetail = 'Same state · ${other.state}';
  } else {
    locScore = 60;
    locDetail = '${other.city}, ${other.state}';
  }
  categories.add(
      CompatibilityCategory('Location', Icons.location_on_outlined, locScore, locDetail));

  // Religion / Caste
  int faithScore;
  if (me == null) {
    faithScore = 80;
  } else if (me.religion == other.religion && me.caste == other.caste) {
    faithScore = 95;
  } else if (me.religion == other.religion) {
    faithScore = 80;
  } else {
    faithScore = 45;
  }
  categories.add(CompatibilityCategory('Religion & Caste', Icons.spa_outlined,
      faithScore, '${other.religion}${other.caste != null ? ' · ${other.caste}' : ''}'));

  // Rasi
  final rasiSame = me != null && me.horoscope.rasi == other.horoscope.rasi;
  final rasiScore = rasiSame ? 88 : 55 + rnd(5, 30);
  categories.add(CompatibilityCategory('Rasi', Icons.brightness_3_outlined,
      rasiScore, other.horoscope.rasi));

  // Nakshatra
  final nakSame = me != null && me.horoscope.nakshatra == other.horoscope.nakshatra;
  final nakScore = nakSame ? 92 : 58 + rnd(7, 28);
  categories.add(CompatibilityCategory('Nakshatra', Icons.star_outline,
      nakScore, other.horoscope.nakshatra));

  // Age preference fit
  int ageScore = 80;
  if (me != null) {
    final p = me.partnerPreferences;
    ageScore = (other.age >= p.minAge && other.age <= p.maxAge) ? 100 : 68;
  }
  categories.add(CompatibilityCategory('Age Preference', Icons.cake_outlined,
      ageScore, '${other.age} years'));

  // ── Poruthams (10) ────────────────────────────────────────────────────
  // Bias matches toward the average category score so it feels coherent.
  final avgCat = categories.map((c) => c.score).reduce((a, b) => a + b) ~/ categories.length;
  final poruthams = <PoruthamItem>[];
  int matched = 0;
  for (var i = 0; i < _poruthamNames.length; i++) {
    final threshold = 100 - (avgCat) + 5; // higher avg → lower threshold → more matches
    final roll = rnd(11 + i * 7, 100);
    final ok = roll >= threshold;
    if (ok) matched++;
    poruthams.add(PoruthamItem(
      _poruthamNames[i],
      ok,
      ok ? 'Compatible' : 'Needs review',
    ));
  }

  // ── Overall match % ───────────────────────────────────────────────────
  final poruthamPct = (matched / _poruthamNames.length) * 100;
  final matchPercent = ((avgCat * 0.6) + (poruthamPct * 0.4)).round().clamp(40, 99);

  // ── Strengths & concerns ──────────────────────────────────────────────
  final strengths = <String>[];
  final concerns = <String>[];
  for (final c in categories) {
    if (c.score >= 80) {
      strengths.add('${c.label}: strong compatibility (${c.score}%)');
    } else if (c.score < 60) {
      concerns.add('${c.label}: may need discussion (${c.score}%)');
    }
  }
  if (matched >= 7) {
    strengths.add('$matched of 10 poruthams matched — astrologically favourable');
  } else if (matched <= 4) {
    concerns.add('Only $matched of 10 poruthams matched — consult an astrologer');
  }
  if (strengths.isEmpty) strengths.add('Balanced overall compatibility');

  final verdict = matchPercent >= 80
      ? 'Excellent Match'
      : matchPercent >= 65
          ? 'Good Match'
          : 'Average Match';

  return CompatibilityResult(
    matchPercent: matchPercent,
    matchedPoruthams: matched,
    totalPoruthams: _poruthamNames.length,
    poruthams: poruthams,
    categories: categories,
    strengths: strengths,
    concerns: concerns,
    verdict: verdict,
  );
}

int _likeness(String? a, String b, {required int base, required int salt}) {
  if (a == null) return base;
  if (a.toLowerCase() == b.toLowerCase()) return 95;
  // share a keyword (e.g. both "M.Sc"/"M.S")
  final at = a.toLowerCase().split(RegExp(r'[ .,]')).where((w) => w.length > 2).toSet();
  final bt = b.toLowerCase().split(RegExp(r'[ .,]')).where((w) => w.length > 2).toSet();
  final overlap = at.intersection(bt).isNotEmpty;
  return overlap ? 85 : base + (salt.abs() % 15);
}
