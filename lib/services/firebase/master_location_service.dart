import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/master_location_model.dart';

/// Reads the location master data (states → districts → cities) from Firestore.
///
/// Children are filtered by the parent's DOCUMENT id (`stateId` / `districtId`)
/// and sorted by name CLIENT-SIDE on purpose: a server `where(parentId) +
/// orderBy(name)` would require a composite index, whereas a single equality
/// filter needs only Firestore's automatic index. Master data is small (a few
/// hundred rows per parent at most), so client sorting is effectively free.
class MasterLocationService {
  final FirebaseFirestore _db;

  MasterLocationService([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  static const _statesCol = 'master_states';
  static const _districtsCol = 'master_districts';
  static const _citiesCol = 'master_cities';

  /// All states, alphabetically. Sorted client-side (no `orderBy`) to match the
  /// index-free convention used across the master-data readers.
  Future<List<MasterState>> getStates() async {
    final snap = await _db.collection(_statesCol).get();
    final list = snap.docs.map(MasterState.fromDoc).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Districts belonging to [stateId], alphabetically.
  Future<List<MasterDistrict>> getDistricts(String stateId) async {
    if (stateId.trim().isEmpty) return const [];
    final snap = await _db
        .collection(_districtsCol)
        .where('stateId', isEqualTo: stateId)
        .get();
    final list = snap.docs.map(MasterDistrict.fromDoc).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Cities belonging to [districtId], alphabetically.
  Future<List<MasterCity>> getCities(String districtId) async {
    if (districtId.trim().isEmpty) return const [];
    final snap = await _db
        .collection(_citiesCol)
        .where('districtId', isEqualTo: districtId)
        .get();
    final list = snap.docs.map(MasterCity.fromDoc).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}
