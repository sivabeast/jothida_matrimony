import 'package:cloud_firestore/cloud_firestore.dart';

/// Master-data records loaded from Firestore (replaces the old hardcoded
/// `SelectionData`/`AppConstants` religion & caste lists).
///
/// Collections:
///   master_religions   { name }
///   master_castes      { religionId, name }
///   master_subcastes   { casteId, name }
/// (the document id is the stable religionId / casteId / subcasteId.)

class Religion {
  final String id;
  final String name;
  const Religion({required this.id, required this.name});

  factory Religion.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return Religion(id: doc.id, name: (d['name'] ?? '').toString());
  }

  /// Parse a bundled-JSON record (the `id` is a field, not a doc id).
  factory Religion.fromMap(Map<String, dynamic> m) => Religion(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
      );
}

class Caste {
  final String id;
  final String religionId;
  final String name;
  const Caste({required this.id, required this.religionId, required this.name});

  factory Caste.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return Caste(
      id: doc.id,
      religionId: (d['religionId'] ?? '').toString(),
      name: (d['name'] ?? '').toString(),
    );
  }

  factory Caste.fromMap(Map<String, dynamic> m) => Caste(
        id: (m['id'] ?? '').toString(),
        religionId: (m['religionId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
      );
}

class Subcaste {
  final String id;
  final String casteId;
  final String name;
  const Subcaste({required this.id, required this.casteId, required this.name});

  factory Subcaste.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return Subcaste(
      id: doc.id,
      casteId: (d['casteId'] ?? '').toString(),
      name: (d['name'] ?? '').toString(),
    );
  }

  factory Subcaste.fromMap(Map<String, dynamic> m) => Subcaste(
        id: (m['id'] ?? '').toString(),
        casteId: (m['casteId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
      );
}
