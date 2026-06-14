// Generator for master_nakshatra_compatibility.json
//
// Produces a 27×27 Tamil nakshatra marriage-compatibility dataset by APPLYING
// the documented classical Porutham / Koota rules — it does not invent or
// assume per-pair scores. Every classification is computed deterministically
// from the rule tables below, each of which comes from classical Tamil/Vedic
// astrology sources (see README.md for the source list and methodology).
//
// Convention: each top-level key is the GIRL'S (bride's) nakshatra; the entries
// inside its buckets are the BOY'S (groom's) nakshatra. This matches Tamil
// practice of reckoning porutham "from the girl's star". A few poruthams (Dina,
// Mahendra, Sthree Dheerga) are directional, so the table is intentionally
// asymmetric.
//
// Run:  dart run tool/generate_nakshatra_compatibility.dart

import 'dart:convert';
import 'dart:io';

// Nakshatra keys 1..27 (index 0 unused) — naming matches master_nakshatra.json.
const List<String> _keys = [
  '', // 0 placeholder
  'ashwini', 'bharani', 'karthigai', 'rohini', 'mirugasirisham',
  'thiruvathirai', 'punarpoosam', 'poosam', 'ayilyam', 'magham',
  'pooram', 'uthiram', 'hastham', 'chithirai', 'swathi',
  'visakam', 'anusham', 'kettai', 'moolam', 'pooradam',
  'uthiradam', 'thiruvonam', 'avittam', 'sathayam', 'poorattadhi',
  'uthirattadhi', 'revathi',
];

// ── Classical rule tables (nakshatra numbers are 1..27) ─────────────────────

/// Gana (temperament): 0 = Deva, 1 = Manushya, 2 = Rakshasa.
/// Source: classical Gana classification (Brihat Parashara / Tamil porutham).
int _gana(int s) {
  const deva = {1, 5, 7, 8, 13, 15, 17, 22, 27};
  const manushya = {2, 4, 6, 11, 12, 20, 21, 25, 26};
  if (deva.contains(s)) return 0;
  if (manushya.contains(s)) return 1;
  return 2; // Rakshasa
}

/// Nadi (constitution): 0 = Aadi/Vata, 1 = Madhya/Pitta, 2 = Antya/Kapha.
/// Same Nadi between partners = Nadi dosha (classically a ground to reject).
/// Source: Ashtakoota Nadi-koota classification.
int _nadi(int s) {
  const aadi = {1, 6, 7, 12, 13, 18, 19, 24, 25};
  const madhya = {2, 5, 8, 11, 14, 17, 20, 23, 26};
  if (aadi.contains(s)) return 0;
  if (madhya.contains(s)) return 1;
  return 2; // Antya
}

/// Rajju (group along the body): 0 Pada, 1 Kati, 2 Nabhi, 3 Kanta, 4 Sira.
/// Same Rajju between partners = Rajju dosha (the most serious affliction).
/// Source: Tamil Rajju porutham table.
int _rajju(int s) {
  const pada = {1, 9, 10, 18, 19, 27};
  const kati = {2, 8, 11, 17, 20, 26};
  const nabhi = {3, 7, 12, 16, 21, 25};
  const kanta = {4, 6, 13, 15, 22, 24};
  if (pada.contains(s)) return 0;
  if (kati.contains(s)) return 1;
  if (nabhi.contains(s)) return 2;
  if (kanta.contains(s)) return 3;
  return 4; // Sira: 5, 14, 23
}

/// Yoni (animal symbol) per nakshatra. Source: classical Yoni-koota table.
const Map<int, int> _yoni = {
  1: 0, 2: 1, 3: 2, 4: 3, 5: 3, 6: 4, 7: 5, 8: 2, 9: 5,
  10: 6, 11: 6, 12: 7, 13: 8, 14: 9, 15: 8, 16: 9, 17: 10,
  18: 10, 19: 4, 20: 11, 21: 12, 22: 11, 23: 13, 24: 0,
  25: 13, 26: 7, 27: 1,
};
// Naturally hostile yoni animals (mutual). Source: Yoni-koota enmity table.
const Map<int, int> _yoniEnemy = {
  0: 8, 8: 0, // Horse ↔ Buffalo
  1: 13, 13: 1, // Elephant ↔ Lion
  2: 11, 11: 2, // Sheep ↔ Monkey
  3: 12, 12: 3, // Serpent ↔ Mongoose
  5: 6, 6: 5, // Cat ↔ Rat
  4: 10, 10: 4, // Dog ↔ Deer
  7: 9, 9: 7, // Cow ↔ Tiger
};

/// Mutually obstructing (Vedha) star pairs. Source: Tamil Vedha porutham table.
const Map<int, int> _vedha = {
  1: 18, 18: 1, 2: 17, 17: 2, 3: 16, 16: 3, 4: 15, 15: 4,
  5: 23, 23: 5, 6: 22, 22: 6, 7: 21, 21: 7, 8: 20, 20: 8,
  9: 19, 19: 9, 10: 27, 27: 10, 11: 26, 26: 11, 12: 25, 25: 12,
  13: 24, 24: 13,
};

/// Forward count from girl's star [g] to boy's star [b] in the 27-cycle (1..27).
int _count(int g, int b) => ((b - g) % 27) + 1;

// ── Per-pair evaluation (girl = g, boy = b) ─────────────────────────────────
String _classify(int g, int b) {
  // Critical doshas → reject (poor) regardless of other factors.
  if (_rajju(g) == _rajju(b)) return 'poor'; // Rajju dosha
  if (_nadi(g) == _nadi(b)) return 'poor'; // Nadi dosha

  // Dina (Tara) porutham: count/9 remainder in {2,4,6,8,0} is favourable.
  final cnt = _count(g, b);
  final dinaOk = const {2, 4, 6, 8, 0}.contains(cnt % 9);

  // Gana porutham: same gana, or Deva↔Manushya, is favourable.
  final g1 = _gana(g), g2 = _gana(b);
  final ganaOk = g1 == g2 || (g1 == 0 && g2 == 1) || (g1 == 1 && g2 == 0);

  // Yoni porutham: same yoni or non-enemy is favourable; enemy is a defect.
  final yoniEnemy = _yoniEnemy[_yoni[g]] == _yoni[b];
  final yoniOk = !yoniEnemy;

  // Mahendra porutham: count in {4,7,10,13,16,19,22,25} is favourable.
  final mahendraOk = const {4, 7, 10, 13, 16, 19, 22, 25}.contains(cnt);

  // Sthree Dheerga porutham: count from girl to boy greater than 9.
  final streeOk = cnt > 9;

  // Vedha porutham: a vedha pair is a defect.
  final vedhaPresent = _vedha[g] == b;
  final vedhaOk = !vedhaPresent;

  // Weighted score. Rajju & Nadi already passed (2 pts each); remaining six
  // factors carry 1 pt each → max 10, baseline 4 when both criticals pass.
  var score = 4; // rajjuOk(2) + nadiOk(2)
  if (dinaOk) score++;
  if (ganaOk) score++;
  if (yoniOk) score++;
  if (mahendraOk) score++;
  if (streeOk) score++;
  if (vedhaOk) score++;

  var category = score >= 9
      ? 'excellent'
      : score >= 7
          ? 'good'
          : score >= 5
              ? 'average'
              : 'poor';

  // A Yoni-enemy or Vedha defect caps the result at "average" even if other
  // factors are strong (both are classically significant negatives).
  if ((yoniEnemy || vedhaPresent) &&
      (category == 'excellent' || category == 'good')) {
    category = 'average';
  }
  return category;
}

void main() {
  final out = <String, dynamic>{};

  out['_meta'] = {
    'title': 'Tamil Nakshatra Marriage Compatibility (27×27)',
    'convention':
        'Top-level key = girl/bride nakshatra; bucket entries = boy/groom nakshatra.',
    'categories': ['excellent', 'good', 'average', 'poor'],
    'derivation':
        'Computed by applying the classical Porutham/Koota rules (Dina/Tara, '
            'Gana, Yoni, Mahendra, Sthree Dheerga, Rajju, Nadi, Vedha). Not '
            'transcribed from a per-pair lookup and not invented.',
    'criticalDoshas': ['Rajju (same group)', 'Nadi (same group)'],
    'generatedBy': 'tool/generate_nakshatra_compatibility.dart',
  };

  const sources = [
    {
      'reference':
          'Traditional Tamil Thirumana Porutham tables (Dina, Gana, Mahendra, '
              'Sthree Dheerga, Yoni, Rajju, Vedha)',
      'type': 'Book / Astrology Table',
      'notes':
          'Standard ten-porutham marriage-matching system used in Tamil Nadu.',
    },
    {
      'reference':
          'Ashtakoota Guna Milan — Nadi koota and Yoni koota classifications '
              '(classical Vedic, after Brihat Parashara Hora Shastra)',
      'type': 'Classical Vedic Reference',
      'notes':
          'Used for the Nadi grouping and Yoni animal/enmity classifications.',
    },
  ];

  var pairCount = 0;
  for (var g = 1; g <= 27; g++) {
    final buckets = {
      'excellent': <String>[],
      'good': <String>[],
      'average': <String>[],
      'poor': <String>[],
    };
    for (var b = 1; b <= 27; b++) {
      if (b == g) continue; // skip self
      buckets[_classify(g, b)]!.add(_keys[b]);
      pairCount++;
    }
    out[_keys[g]] = {
      'excellent': buckets['excellent'],
      'good': buckets['good'],
      'average': buckets['average'],
      'poor': buckets['poor'],
      'sources': sources,
    };
  }

  final file = File('master_data/astrology/master_nakshatra_compatibility.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));

  // Validation summary to stdout.
  stdout.writeln('Wrote ${file.path}');
  stdout.writeln('Nakshatras: 27, directed pairs: $pairCount (expected 702)');
}
