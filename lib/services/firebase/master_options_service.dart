import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// One user-added master-dropdown value. [parent] scopes dependent dropdowns
/// (caste → religionId, subcaste → casteId, district → state name, city →
/// district name); flat lists (education, occupation, income…) use ''.
typedef MasterOption = ({String value, String parent});

/// Firestore-backed CUSTOM master-dropdown values — the "+ Add" system that
/// replaced every "Others → textbox".
///
/// The canonical master data ships as bundled JSON assets (read-only), so
/// user additions live in ONE Firestore doc per dropdown type:
///   master_options/{type}  →  { entries: [ {v: value, p: parent}, … ] }
/// Additions are stored PERMANENTLY and stream live to every user, the admin
/// panel, search and filters. Values are de-duplicated case-insensitively per
/// (value, parent) pair.
class MasterOptionsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const collection = 'master_options';

  // Well-known dropdown type keys.
  static const education = 'education';
  static const occupation = 'occupation';
  static const income = 'income';
  static const religion = 'religion';
  static const caste = 'caste';
  static const subcaste = 'subcaste';
  static const state = 'state';
  static const district = 'district';
  static const city = 'city';
  static const nativePlace = 'native_place';

  DocumentReference<Map<String, dynamic>> _doc(String type) =>
      _db.collection(collection).doc(type);

  /// Live custom entries for [type] (empty on missing doc / read failure).
  Stream<List<MasterOption>> watch(String type) =>
      _doc(type).snapshots().map((d) {
        final raw = (d.data()?['entries'] as List?) ?? const [];
        return raw
            .whereType<Map>()
            .map((e) => (
                  value: (e['v'] ?? '').toString().trim(),
                  parent: (e['p'] ?? '').toString().trim(),
                ))
            .where((e) => e.value.isNotEmpty)
            .toList();
      }).handleError((e) {
        debugPrint('[MasterOptions] watch($type) failed: $e');
        return const <MasterOption>[];
      });

  /// Adds [value] (scoped by [parent]) permanently. No-op when an equal
  /// (case-insensitive) entry already exists. Returns the CANONICAL stored
  /// value (the existing spelling when it was already present).
  Future<String> add(String type,
      {required String value, String parent = ''}) async {
    final v = value.trim();
    if (v.isEmpty) return v;
    final p = parent.trim();

    final snap = await _doc(type).get();
    final raw = (snap.data()?['entries'] as List?) ?? const [];
    for (final e in raw.whereType<Map>()) {
      final ev = (e['v'] ?? '').toString().trim();
      final ep = (e['p'] ?? '').toString().trim();
      if (ev.toLowerCase() == v.toLowerCase() &&
          ep.toLowerCase() == p.toLowerCase()) {
        return ev; // duplicate → reuse the existing canonical spelling
      }
    }
    await _doc(type).set({
      'entries': FieldValue.arrayUnion([
        {'v': v, 'p': p}
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return v;
  }
}
