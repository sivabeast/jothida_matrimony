import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/astrology_service_config.dart';

/// Read / stream / update the single internal astrology service config document
/// (`astrology_service/config`). The doc is world-readable to signed-in users
/// (service page + booking need the charge/slots/office) and writable only by
/// the admin / internal astrology account (enforced in firestore.rules).
class AstrologyConfigService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _collection = 'astrology_service';
  static const String _docId = 'config';

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection(_collection).doc(_docId);

  /// Live config, falling back to [AstrologyServiceConfig.defaults] until the
  /// admin has saved one.
  Stream<AstrologyServiceConfig> watch() => _doc.snapshots().map((d) =>
      d.exists
          ? AstrologyServiceConfig.fromFirestore(d)
          : AstrologyServiceConfig.defaults);

  Future<AstrologyServiceConfig> get() async {
    final d = await _doc.get();
    return d.exists
        ? AstrologyServiceConfig.fromFirestore(d)
        : AstrologyServiceConfig.defaults;
  }

  /// Admin save (merge) of the full config.
  Future<void> save(AstrologyServiceConfig config) =>
      _doc.set(config.toFirestore(), SetOptions(merge: true));

  /// Best-effort: stamp the internal astrology account's real uid onto the
  /// config the first time it logs in, so purchases can pre-create the chat.
  Future<void> setInternalUid(String uid) =>
      _doc.set({'internalUid': uid}, SetOptions(merge: true));
}
