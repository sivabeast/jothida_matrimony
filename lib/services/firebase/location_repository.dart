import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/utils/location_search.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/location_model.dart';

/// Reads the location master data (districts + cities, English and Tamil)
/// from the **bundled JSON** under `assets/master_data/location/` — the
/// primary source (spec §23). Firestore `master_data/*` is used only if an
/// asset cannot be read.
///
/// It used to be the other way round: every session started with four
/// Firestore reads (plus chunk reads) before the first place picker could
/// open, and the app searched whatever copy Firestore held — a separately
/// seeded dataset that could differ from the one shipped with the app. The
/// bundled JSON is on the device already, identical for every member, and
/// needs no network.
///
/// All four files are read and joined ONCE per session into [TnDistrict] /
/// [TnCity] (one object carries both languages), and the shared
/// [PlaceSearchIndex] is built from them once — every picker afterwards
/// searches in memory. A failed load is not cached, so the next open retries.
class LocationRepository {
  static const _collection = 'master_data';
  static const _assetDir = 'assets/master_data/location';
  static const _keys = ['districts_en', 'districts_ta', 'cities_en', 'cities_ta'];

  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  /// Firestore is touched only if a bundled file cannot be read, so the
  /// instance is resolved lazily.
  LocationRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  // ── In-memory cache (loaded once, kept for the session) ────────────────────
  List<TnDistrict>? _districts;
  Map<int, TnDistrict>? _districtById;
  Map<int, List<TnCity>>? _citiesByDistrict;
  List<TnCity>? _cities;
  Future<void>? _loading;

  /// Loads & joins all four datasets exactly once. Concurrent callers share
  /// the same in-flight future; a failure resets so the next call can retry.
  Future<void> _ensureLoaded() => _loading ??= _load().catchError((e) {
        _loading = null;
        throw e;
      });

  Future<void> _load() async {
    final datasets = await Future.wait(_keys.map(_readDataset));
    final districtsEn = datasets[0], districtsTa = datasets[1];
    final citiesEn = datasets[2], citiesTa = datasets[3];

    final districtTa = {
      for (final r in districtsTa) (r['id'] as num).toInt(): '${r['name']}',
    };
    final cityTa = {
      for (final r in citiesTa) (r['id'] as num).toInt(): '${r['name']}',
    };

    final districts = [
      for (final r in districtsEn)
        TnDistrict(
          id: (r['id'] as num).toInt(),
          nameEn: '${r['name']}',
          nameTa: districtTa[(r['id'] as num).toInt()] ?? '${r['name']}',
        ),
    ]..sort((a, b) => a.nameEn.compareTo(b.nameEn));

    final cities = [
      for (final r in citiesEn)
        TnCity(
          id: (r['id'] as num).toInt(),
          districtId: (r['districtId'] as num).toInt(),
          nameEn: '${r['name']}',
          nameTa: cityTa[(r['id'] as num).toInt()] ?? '${r['name']}',
        ),
    ]..sort((a, b) => a.nameEn.compareTo(b.nameEn));

    final byDistrict = <int, List<TnCity>>{};
    for (final c in cities) {
      (byDistrict[c.districtId] ??= []).add(c);
    }

    _districts = districts;
    _districtById = {for (final d in districts) d.id: d};
    _cities = cities;
    _citiesByDistrict = byDistrict;

    // Register district/city English→Tamil names so [context.localizeValue]
    // renders stored English location values in Tamil anywhere (profile view,
    // My Profile, cards…) — storage stays English (spec §13/§14).
    registerMasterTamilNames({
      for (final d in districts) d.nameEn: d.nameTa,
      for (final c in cities) c.nameEn: c.nameTa,
    });

    debugPrint('[LocationRepository] ready — ${districts.length} districts, '
        '${cities.length} cities.');
  }

  /// One dataset: the bundled asset first; Firestore only when the asset
  /// cannot be read.
  Future<List<dynamic>> _readDataset(String key) async {
    try {
      final raw = await rootBundle.loadString('$_assetDir/$key.json');
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) {
        throw FormatException('Expected a non-empty array in $key.json');
      }
      return decoded;
    } catch (e) {
      debugPrint('[LocationRepository] bundled $key unavailable ($e) — '
          'trying Firestore.');
      return _readFirestoreDataset(key);
    }
  }

  Future<List<dynamic>> _readFirestoreDataset(String key) async {
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
  }

  PlaceSearchIndex? _index;

  /// The shared place search index, built once from the loaded data.
  Future<PlaceSearchIndex> searchIndex() async {
    await _ensureLoaded();
    return _index ??=
        PlaceSearchIndex.build(districts: _districts!, cities: _cities!);
  }

  Future<TnCity?> cityById(int id) async {
    await _ensureLoaded();
    for (final c in _cities!) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// All 38 districts, alphabetical by English name.
  Future<List<TnDistrict>> getDistricts() async {
    await _ensureLoaded();
    return List.unmodifiable(_districts!);
  }

  /// Cities belonging to [districtId], alphabetical by English name.
  Future<List<TnCity>> getCities(int districtId) async {
    await _ensureLoaded();
    return List.unmodifiable(_citiesByDistrict![districtId] ?? const []);
  }

  /// Every city in the dataset (used by the Birth Place picker).
  Future<List<TnCity>> getAllCities() async {
    await _ensureLoaded();
    return List.unmodifiable(_cities!);
  }

  Future<TnDistrict?> districtById(int id) async {
    await _ensureLoaded();
    return _districtById![id];
  }

  // ── Name matching (saved profiles + GPS detection) ────────────────────────
  // Saved values are canonical English, but matching also accepts Tamil and
  // sloppy spellings so old records and reverse-geocoder output still resolve.

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\bdistrict\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9஀-௿ ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _same(String a, String b) {
    final na = _norm(a), nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    // Transliteration-tolerant equality before the loose contains-match, so
    // "Kancheepuram" resolves to "Kanchipuram" rather than to whichever town
    // name merely CONTAINS the text.
    final ka = placeKey(a), kb = placeKey(b);
    if (ka.isNotEmpty && ka == kb) return true;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  Future<TnDistrict?> findDistrict(String name) async {
    if (name.trim().isEmpty) return null;
    await _ensureLoaded();
    for (final d in _districts!) {
      if (_norm(d.nameEn) == _norm(name) || _norm(d.nameTa) == _norm(name)) {
        return d;
      }
    }
    for (final d in _districts!) {
      if (_same(d.nameEn, name) || _same(d.nameTa, name)) return d;
    }
    return null;
  }

  /// Finds a city by English or Tamil name; [districtId] narrows the search.
  Future<TnCity?> findCity(String name, {int? districtId}) async {
    if (name.trim().isEmpty) return null;
    await _ensureLoaded();
    final pool = districtId != null
        ? (_citiesByDistrict![districtId] ?? const <TnCity>[])
        : _cities!;
    for (final c in pool) {
      if (_norm(c.nameEn) == _norm(name) || _norm(c.nameTa) == _norm(name)) {
        return c;
      }
    }
    for (final c in pool) {
      if (_same(c.nameEn, name) || _same(c.nameTa, name)) return c;
    }
    return null;
  }
}
