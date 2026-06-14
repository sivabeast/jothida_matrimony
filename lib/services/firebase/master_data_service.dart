import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import '../../models/master_data.dart';

/// Reads the Religion → Caste → Subcaste master data.
///
/// PRIMARY source is the bundled JSON in `assets/master_data/` — it is the
/// canonical master data (the very files `seed_master_data.js` uploads to
/// Firestore) and it loads instantly and OFFLINE, so the dropdowns are never
/// empty even before Firestore is seeded or its security rules are deployed.
/// This is the fix for the "No options found" bug, which happened because the
/// app read ONLY Firestore and that collection was empty / unreadable.
///
/// Firestore is kept as a FALLBACK (used only if the asset is missing/empty).
/// All filtering and sorting is done in memory — no composite indexes required.
class MasterDataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String religionsCollection = 'master_religions';
  static const String castesCollection = 'master_castes';
  static const String subcastesCollection = 'master_subcastes';

  static const String _assetDir = 'assets/master_data';

  // ── Religions ─────────────────────────────────────────────────────────────
  Future<List<Religion>> getReligions() async {
    final rows = await _loadJson('master_religions.json');
    if (rows.isNotEmpty) {
      final list = rows.map((m) => Religion.fromMap(m)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      debugPrint('[MasterData] religions ← JSON: ${list.length}');
      return list;
    }
    try {
      final snap = await _db.collection(religionsCollection).get();
      final list = snap.docs.map(Religion.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      debugPrint('[MasterData] religions ← Firestore: ${list.length}');
      return list;
    } catch (e) {
      debugPrint('[MasterData] religions: JSON empty AND Firestore failed ($e)');
      return const [];
    }
  }

  // ── Castes (scoped to a religion) ──────────────────────────────────────────
  Future<List<Caste>> getCastes(String religionId) async {
    if (religionId.trim().isEmpty) return const [];

    final rows = await _loadJson('master_castes.json');
    if (rows.isNotEmpty) {
      final list = rows
          .map((m) => Caste.fromMap(m))
          .where((c) => c.religionId == religionId)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      debugPrint('[MasterData] castes($religionId) ← JSON: ${list.length}');
      return list;
    }
    try {
      final snap = await _db
          .collection(castesCollection)
          .where('religionId', isEqualTo: religionId)
          .get();
      final list = snap.docs.map(Caste.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      debugPrint('[MasterData] castes($religionId) ← Firestore: ${list.length}');
      return list;
    } catch (e) {
      debugPrint('[MasterData] castes($religionId): JSON empty AND Firestore failed ($e)');
      return const [];
    }
  }

  // ── Subcastes (scoped to a caste) ──────────────────────────────────────────
  Future<List<Subcaste>> getSubcastes(String casteId) async {
    if (casteId.trim().isEmpty) return const [];

    final rows = await _loadJson('master_subcastes.json');
    if (rows.isNotEmpty) {
      final list = rows
          .map((m) => Subcaste.fromMap(m))
          .where((s) => s.casteId == casteId)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      debugPrint('[MasterData] subcastes($casteId) ← JSON: ${list.length}');
      return list;
    }
    try {
      final snap = await _db
          .collection(subcastesCollection)
          .where('casteId', isEqualTo: casteId)
          .get();
      final list = snap.docs.map(Subcaste.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      debugPrint('[MasterData] subcastes($casteId) ← Firestore: ${list.length}');
      return list;
    } catch (e) {
      debugPrint('[MasterData] subcastes($casteId): JSON empty AND Firestore failed ($e)');
      return const [];
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  /// Loads + decodes a bundled JSON array of objects. Returns [] on any failure
  /// (missing asset, bad JSON, wrong shape) so callers can fall back to
  /// Firestore and the UI degrades gracefully rather than crashing.
  Future<List<Map<String, dynamic>>> _loadJson(String file) async {
    try {
      final raw = await rootBundle.loadString('$_assetDir/$file');
      final decoded = json.decode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      debugPrint('[MasterData] $file: unexpected JSON shape (${decoded.runtimeType})');
      return const [];
    } catch (e) {
      debugPrint('[MasterData] $file: asset load failed ($e)');
      return const [];
    }
  }
}
