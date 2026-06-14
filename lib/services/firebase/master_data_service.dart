import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/master_data.dart';

/// Reads the Religion → Caste → Subcaste master data from Firestore.
///
/// All queries are single-field equality only (no `orderBy`) so they never
/// require a composite index; results are sorted by name client-side. This is
/// the same pattern used elsewhere to keep queries index-free.
class MasterDataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String religionsCollection = 'master_religions';
  static const String castesCollection = 'master_castes';
  static const String subcastesCollection = 'master_subcastes';

  Future<List<Religion>> getReligions() async {
    final snap = await _db.collection(religionsCollection).get();
    final list = snap.docs.map(Religion.fromDoc).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<List<Caste>> getCastes(String religionId) async {
    if (religionId.isEmpty) return const [];
    final snap = await _db
        .collection(castesCollection)
        .where('religionId', isEqualTo: religionId)
        .get();
    final list = snap.docs.map(Caste.fromDoc).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<List<Subcaste>> getSubcastes(String casteId) async {
    if (casteId.isEmpty) return const [];
    final snap = await _db
        .collection(subcastesCollection)
        .where('casteId', isEqualTo: casteId)
        .get();
    final list = snap.docs.map(Subcaste.fromDoc).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}
