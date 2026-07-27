import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import '../../core/utils/value_l10n.dart';
import '../../models/master_data.dart';

/// Reads the Religion → Caste → Subcaste master data with **Firestore as the
/// single source of truth** (`master_data/{key}`) and the bundled JSON assets
/// as the offline / not-yet-seeded fallback — the exact architecture
/// [LocationRepository] already uses for Tamil Nadu locations.
///
/// Firestore layout (seeded by matrimony_website/scripts/seed-master-data.mjs,
/// the same project both the website and this app point at):
///   master_data/religions  { items: [ {id, name, nameTamil} ] }
///   master_data/castes     { items: [ {id, religionId, name, nameTamil} ] }
///   master_data/subcastes  { items: [ {id, casteId, name, nameTamil} ] }
///   — a dataset over ~0.8 MB keeps its rows in a `chunks` subcollection
///     ({ index, items }); Firestore documents max out at 1 MB.
///
/// All three datasets are fetched once per session, indexed in memory (scoped
/// by religionId / casteId) and their Tamil names registered with the value
/// localizer, so every dropdown open after the first is instant, language
/// switching needs no re-fetch, and any stored caste renders in Tamil via
/// `context.localizeValue` while profiles keep storing canonical English.
///
/// This replaced the old JSON-primary loader: reading Firestore first makes an
/// admin/website master-data change propagate to every device, instead of the
/// app being pinned to whatever shipped in its bundle (spec §1/§11/§12/§15).
class MasterDataService {
  static const String _collection = 'master_data';
  static const String _assetDir = 'assets/master_data';

  final FirebaseFirestore _db;
  MasterDataService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // ── Session cache (loaded once, kept for the app session) ──────────────────
  List<Religion>? _religions;
  Map<String, List<Caste>>? _castesByReligion;
  Map<String, List<Subcaste>>? _subcastesByCaste;
  Future<void>? _loading;

  /// Loads all three datasets exactly once. Concurrent callers share the same
  /// in-flight future; a failure resets so the next call can retry.
  Future<void> _ensureLoaded() => _loading ??= _load().catchError((e) {
        _loading = null;
        throw e;
      });

  Future<void> _load() async {
    final results = await Future.wait([
      _readDataset('religions', 'master_religions.json'),
      _readDataset('castes', 'master_castes.json'),
      _readDataset('subcastes', 'master_subcastes.json'),
    ]);

    final religions = [for (final m in results[0]) Religion.fromMap(_asMap(m))]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final byReligion = <String, List<Caste>>{};
    for (final m in results[1]) {
      final c = Caste.fromMap(_asMap(m));
      (byReligion[c.religionId] ??= []).add(c);
    }
    for (final list in byReligion.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    final byCaste = <String, List<Subcaste>>{};
    for (final m in results[2]) {
      final s = Subcaste.fromMap(_asMap(m));
      (byCaste[s.casteId] ??= []).add(s);
    }
    for (final list in byCaste.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    // Feed the value localizer so caste / sub-caste names (hundreds of them,
    // too many to hardcode) display in Tamil wherever a stored value is shown.
    registerMasterTamilNames({
      for (final r in religions) r.name: r.nameTamil,
      for (final list in byReligion.values)
        for (final c in list) c.name: c.nameTamil,
      for (final list in byCaste.values)
        for (final s in list) s.name: s.nameTamil,
    });

    _religions = religions;
    _castesByReligion = byReligion;
    _subcastesByCaste = byCaste;
    debugPrint('[MasterData] ready — ${religions.length} religions, '
        '${byReligion.values.fold<int>(0, (n, l) => n + l.length)} castes, '
        '${byCaste.values.fold<int>(0, (n, l) => n + l.length)} subcastes.');
  }

  Map<String, dynamic> _asMap(dynamic e) => Map<String, dynamic>.from(e as Map);

  /// One dataset: Firestore first, bundled asset when Firestore is unreachable
  /// or not seeded yet. Mirrors [LocationRepository._readDataset].
  Future<List<dynamic>> _readDataset(String key, String assetFile) async {
    try {
      final snap = await _db.collection(_collection).doc(key).get();
      if (!snap.exists) throw StateError('master_data/$key not seeded');
      final meta = snap.data()!;
      if (meta['chunked'] == true) {
        final chunks = await _db
            .collection(_collection)
            .doc(key)
            .collection('chunks')
            .orderBy('index')
            .get();
        return [
          for (final c in chunks.docs) ...(c.data()['items'] as List? ?? []),
        ];
      }
      final items = meta['items'];
      if (items is! List || items.isEmpty) {
        throw StateError('master_data/$key has no items');
      }
      return items;
    } catch (e) {
      debugPrint('[MasterData] Firestore $key unavailable ($e) — '
          'using bundled asset.');
      final raw = await rootBundle.loadString('$_assetDir/$assetFile');
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw FormatException('Expected a JSON array in $assetFile');
      }
      return decoded;
    }
  }

  // ── Reads (same signatures the providers already call) ─────────────────────

  /// All religions, alphabetical by English name.
  Future<List<Religion>> getReligions() async {
    await _ensureLoaded();
    return List.unmodifiable(_religions!);
  }

  /// Castes scoped to [religionId] (empty when none selected / unknown id).
  Future<List<Caste>> getCastes(String religionId) async {
    if (religionId.trim().isEmpty) return const [];
    await _ensureLoaded();
    return List.unmodifiable(_castesByReligion![religionId] ?? const []);
  }

  /// Subcastes scoped to [casteId] (empty when none selected / unknown id).
  Future<List<Subcaste>> getSubcastes(String casteId) async {
    if (casteId.trim().isEmpty) return const [];
    await _ensureLoaded();
    return List.unmodifiable(_subcastesByCaste![casteId] ?? const []);
  }
}
