import 'package:cloud_firestore/cloud_firestore.dart';

/// Master-data records — **Firestore is the single source of truth**
/// (`master_data/{key}`, seeded from the website's canonical bilingual JSON);
/// the bundled `assets/master_data/*.json` are the offline / not-yet-seeded
/// fallback. See [MasterDataService].
///
/// Every record carries the canonical English `name` (what profiles store and
/// what matching/filters key off) plus `nameTamil` for display. Storage stays
/// English; only DISPLAY switches with the app language via [localizedName] /
/// `context.localizeValue`.
///
/// Firestore item shape (inside `master_data/{key}.items[]` or a chunk):
///   religions  { id, name, nameTamil }
///   castes     { id, religionId, name, nameTamil }
///   subcastes  { id, casteId, name, nameTamil }

class Religion {
  final String id;
  final String name;
  final String nameTamil;
  const Religion({required this.id, required this.name, this.nameTamil = ''});

  /// Tamil label in Tamil mode (when present), else the English name.
  String localizedName(bool tamil) =>
      tamil && nameTamil.trim().isNotEmpty ? nameTamil : name;

  factory Religion.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return Religion.fromMap({'id': doc.id, ...d});
  }

  factory Religion.fromMap(Map<String, dynamic> m) => Religion(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        nameTamil: (m['nameTamil'] ?? '').toString(),
      );
}

class Caste {
  final String id;
  final String religionId;
  final String name;
  final String nameTamil;
  const Caste({
    required this.id,
    required this.religionId,
    required this.name,
    this.nameTamil = '',
  });

  String localizedName(bool tamil) =>
      tamil && nameTamil.trim().isNotEmpty ? nameTamil : name;

  factory Caste.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return Caste.fromMap({'id': doc.id, ...d});
  }

  factory Caste.fromMap(Map<String, dynamic> m) => Caste(
        id: (m['id'] ?? '').toString(),
        religionId: (m['religionId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        nameTamil: (m['nameTamil'] ?? '').toString(),
      );
}

class Subcaste {
  final String id;
  final String casteId;
  final String name;
  final String nameTamil;
  const Subcaste({
    required this.id,
    required this.casteId,
    required this.name,
    this.nameTamil = '',
  });

  String localizedName(bool tamil) =>
      tamil && nameTamil.trim().isNotEmpty ? nameTamil : name;

  factory Subcaste.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return Subcaste.fromMap({'id': doc.id, ...d});
  }

  factory Subcaste.fromMap(Map<String, dynamic> m) => Subcaste(
        id: (m['id'] ?? '').toString(),
        casteId: (m['casteId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        nameTamil: (m['nameTamil'] ?? '').toString(),
      );
}
