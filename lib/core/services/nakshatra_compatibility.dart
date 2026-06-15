import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import 'master_astrology_data.dart';

/// Loads the master Nakshatra compatibility dataset
/// (`master_nakshatra_compatibility.json`) and answers a single question:
/// **are two birth-stars a horoscope match?**
///
/// This NEVER filters profiles — it only powers an informational "Horoscope
/// Match" badge. A pair is considered a match when the target star falls in the
/// current star's `excellent` or `good` bucket.
class NakshatraCompatibility {
  /// englishKey → set of compatible englishKeys (excellent + good).
  final Map<String, Set<String>> _compatible;

  /// Tamil nakshatra name → lowercase english key (e.g. "அஸ்வினி" → "ashwini").
  final Map<String, String> _tamilToKey;

  const NakshatraCompatibility._(this._compatible, this._tamilToKey);

  static NakshatraCompatibility? _cache;
  static const _asset =
      'assets/master_data/astrology/master_nakshatra_compatibility.json';

  /// Loads & caches the dataset. Safe to call repeatedly.
  static Future<NakshatraCompatibility> load() async {
    if (_cache != null) return _cache!;

    final raw = await rootBundle.loadString(_asset);
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final compatible = <String, Set<String>>{};
    for (final entry in json.entries) {
      if (entry.key.startsWith('_')) continue; // skip _meta
      final node = entry.value;
      if (node is! Map) continue;
      final excellent = (node['excellent'] as List?)?.cast<String>() ?? const [];
      final good = (node['good'] as List?)?.cast<String>() ?? const [];
      compatible[entry.key.toLowerCase()] = {
        ...excellent.map((e) => e.toLowerCase()),
        ...good.map((e) => e.toLowerCase()),
      };
    }

    // Build Tamil → english-key map from the nakshatra master data so we can
    // accept the Tamil names that profiles actually store.
    final master = await MasterAstrologyData.load();
    final tamilToKey = <String, String>{};
    for (final n in master.nakshatras) {
      final key = n.nameEnglish.trim().toLowerCase();
      if (n.nameTamil.trim().isNotEmpty) tamilToKey[n.nameTamil.trim()] = key;
      // Also accept the english name directly.
      tamilToKey[n.nameEnglish.trim()] = key;
    }

    return _cache = NakshatraCompatibility._(compatible, tamilToKey);
  }

  /// Resolves any stored nakshatra value (Tamil or English) to the dataset key.
  String? _key(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    return _tamilToKey[v] ?? (_compatible.containsKey(v.toLowerCase())
        ? v.toLowerCase()
        : null);
  }

  /// True when [targetNakshatra] is an excellent/good match for
  /// [currentNakshatra]. Returns false (no badge) when either value is missing
  /// or unrecognised — it never throws and never hides a profile.
  bool isCompatible(String? currentNakshatra, String? targetNakshatra) {
    final a = _key(currentNakshatra);
    final b = _key(targetNakshatra);
    if (a == null || b == null) return false;
    return _compatible[a]?.contains(b) ?? false;
  }
}
