import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// One master record (Rasi / Nakshatra / Lagnam) from the bundled master JSON.
class MasterAstroEntry {
  final String id;
  final String nameTamil;
  final String nameEnglish;
  final int order; // 1-based position used to map an engine index → a name
  const MasterAstroEntry({
    required this.id,
    required this.nameTamil,
    required this.nameEnglish,
    required this.order,
  });

  factory MasterAstroEntry.fromMap(Map<String, dynamic> m) => MasterAstroEntry(
        id: m['id'] as String? ?? '',
        nameTamil: m['nameTamil'] as String? ?? '',
        nameEnglish: m['nameEnglish'] as String? ?? '',
        order: (m['order'] as num?)?.toInt() ?? 0,
      );
}

/// Loads and exposes the authoritative Rasi / Nakshatra / Lagnam master data
/// (`assets/master_data/astrology/*.json`) and validates engine output against
/// it. A computed value is accepted ONLY when it maps to an existing master
/// entry; otherwise the calculation is rejected (never persisted).
class MasterAstrologyData {
  MasterAstrologyData._(this.rasis, this.nakshatras, this.lagnams);

  final List<MasterAstroEntry> rasis; // 12, ordered by `order`
  final List<MasterAstroEntry> nakshatras; // 27, ordered by `order`
  final List<MasterAstroEntry> lagnams; // 12, ordered by `order`

  static MasterAstrologyData? _cache;

  /// Loads (and caches) the master data from bundled assets.
  static Future<MasterAstrologyData> load() async {
    if (_cache != null) return _cache!;
    final rasis = await _loadList('assets/master_data/astrology/master_rasi.json');
    final naks =
        await _loadList('assets/master_data/astrology/master_nakshatra.json');
    final lagnams =
        await _loadList('assets/master_data/astrology/master_lagnam.json');
    return _cache = MasterAstrologyData._(rasis, naks, lagnams);
  }

  static Future<List<MasterAstroEntry>> _loadList(String asset) async {
    final raw = await rootBundle.loadString(asset);
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final entries = list.map(MasterAstroEntry.fromMap).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return entries;
  }

  /// Returns the Rasi entry for a 0-based engine index, or `null` if the index
  /// is out of range (i.e. not a valid master value).
  MasterAstroEntry? rasiByIndex(int i) => _at(rasis, i);
  MasterAstroEntry? nakshatraByIndex(int i) => _at(nakshatras, i);
  MasterAstroEntry? lagnamByIndex(int i) => _at(lagnams, i);

  static MasterAstroEntry? _at(List<MasterAstroEntry> list, int i) =>
      (i >= 0 && i < list.length) ? list[i] : null;
}
