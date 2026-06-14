import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/master_location_model.dart';

/// Reads the location master data (countries → states → districts → cities)
/// from the **bundled JSON assets** under `assets/master_data/location/`.
///
/// No Firestore dependency: the three files are loaded from the AssetBundle
/// exactly once, parsed, indexed and cached in memory for the rest of the
/// session. Children are filtered by the parent id (`stateId` / `districtId`)
/// and returned alphabetically.
///
/// This replaces the previous Firestore-backed reader — the source of the
/// "Couldn't load states" error, which occurred because the `master_states`
/// collection was empty / unreachable. The data now ships with the app.
class MasterLocationService {
  static const _statesAsset = 'assets/master_data/location/master_states.json';
  static const _districtsAsset =
      'assets/master_data/location/master_districts.json';
  static const _citiesAsset = 'assets/master_data/location/master_cities.json';

  // ── In-memory cache (loaded once, kept for the session) ────────────────────
  List<MasterState>? _states;
  Map<String, List<MasterDistrict>>? _districtsByState;
  Map<String, List<MasterCity>>? _citiesByDistrict;
  Future<void>? _loading;

  /// Loads & indexes all three asset files exactly once. Concurrent callers
  /// share the same in-flight future.
  Future<void> _ensureLoaded() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _readJsonList(_statesAsset),
        _readJsonList(_districtsAsset),
        _readJsonList(_citiesAsset),
      ]);

      final states = results[0]
          .map((e) => MasterState.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final districtsByState = <String, List<MasterDistrict>>{};
      for (final e in results[1]) {
        final d = MasterDistrict.fromJson(e as Map<String, dynamic>);
        (districtsByState[d.stateId] ??= []).add(d);
      }
      for (final list in districtsByState.values) {
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }

      final citiesByDistrict = <String, List<MasterCity>>{};
      for (final e in results[2]) {
        final c = MasterCity.fromJson(e as Map<String, dynamic>);
        (citiesByDistrict[c.districtId] ??= []).add(c);
      }
      for (final list in citiesByDistrict.values) {
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }

      _states = states;
      _districtsByState = districtsByState;
      _citiesByDistrict = citiesByDistrict;

      debugPrint('[MasterLocationService] loaded ${states.length} states, '
          '${results[1].length} districts, ${results[2].length} cities '
          'from bundled JSON.');
    } catch (e, st) {
      // Reset so a later call can retry, and surface a clear error.
      _loading = null;
      debugPrint('[MasterLocationService] FAILED to load location assets: $e\n$st');
      rethrow;
    }
  }

  Future<List<dynamic>> _readJsonList(String asset) async {
    final raw = await rootBundle.loadString(asset);
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('Expected a JSON array in $asset');
    }
    return decoded;
  }

  /// Distinct countries present in the master data (always includes India,
  /// listed first). Derived from `master_states.json` — no hardcoded list.
  Future<List<String>> getCountries() async {
    await _ensureLoaded();
    final set = <String>{};
    for (final s in _states!) {
      if (s.country.trim().isNotEmpty) set.add(s.country.trim());
    }
    final list = set.toList()..sort();
    // Ensure India is present and first.
    list.remove('India');
    return ['India', ...list];
  }

  /// All states (optionally filtered by [country]), alphabetically.
  Future<List<MasterState>> getStates({String? country}) async {
    await _ensureLoaded();
    final all = _states!;
    if (country == null || country.trim().isEmpty) return List.unmodifiable(all);
    final filtered = all
        .where((s) => s.country.toLowerCase() == country.toLowerCase())
        .toList();
    // If we have no data for that country (master data is India-only), fall
    // back to all states rather than showing an empty dropdown.
    return List.unmodifiable(filtered.isEmpty ? all : filtered);
  }

  /// Districts belonging to [stateId], alphabetically.
  Future<List<MasterDistrict>> getDistricts(String stateId) async {
    if (stateId.trim().isEmpty) return const [];
    await _ensureLoaded();
    return List.unmodifiable(_districtsByState![stateId] ?? const []);
  }

  /// Cities belonging to [districtId], alphabetically.
  Future<List<MasterCity>> getCities(String districtId) async {
    if (districtId.trim().isEmpty) return const [];
    await _ensureLoaded();
    return List.unmodifiable(_citiesByDistrict![districtId] ?? const []);
  }
}
