import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/location_model.dart';

/// Reads the Tamil Nadu location master data (districts + cities, English and
/// Tamil) with **Firestore as the source of truth** and the bundled JSON
/// assets as the offline / not-yet-seeded fallback.
///
/// Firestore layout (seeded by matrimony_website/scripts/seed-master-data.mjs):
///   master_data/districts_en · master_data/districts_ta
///   master_data/cities_en    · master_data/cities_ta
///   — each { key, version, itemCount, chunked, items } (chunked datasets keep
///     their rows in a `chunks` subcollection, Firestore docs max out at 1 MB).
///
/// All four datasets are fetched once per session, joined by id into
/// [TnDistrict] / [TnCity] (one object carries both languages) and indexed in
/// memory, so every dropdown open after the first is instant and language
/// switching needs no re-fetch. Firestore's own offline persistence caches the
/// documents across launches; a cold start with no network still works via the
/// bundled assets.
class LocationRepository {
  static const _collection = 'master_data';
  static const _assetDir = 'assets/master_data/location';
  static const _keys = ['districts_en', 'districts_ta', 'cities_en', 'cities_ta'];

  final FirebaseFirestore _db;

  LocationRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

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
    debugPrint('[LocationRepository] ready — ${districts.length} districts, '
        '${cities.length} cities.');
  }

  /// One dataset: Firestore first, bundled asset when Firestore is
  /// unreachable or not seeded yet.
  Future<List<dynamic>> _readDataset(String key) async {
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
      debugPrint('[LocationRepository] Firestore $key unavailable ($e) — '
          'using bundled asset.');
      final raw = await rootBundle.loadString('$_assetDir/$key.json');
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw FormatException('Expected array in $key.json');
      return decoded;
    }
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
