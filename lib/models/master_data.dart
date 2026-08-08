import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/data/master_option.dart';

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
///   religions  { id, name, nameTamil, aliases[] }
///   castes     { id, religionId, name, nameTamil, aliases[] }
///   subcastes  { id, casteId, name, nameTamil, aliases[] }
///
/// `aliases` are search-only spellings (§9) — "marakkayar" also answering to
/// "marakayar". They are never displayed. [asOption] converts any record into
/// the shared [MasterOption] the pickers search against.

class Religion {
  final String id;
  final String name;
  final String nameTamil;

  /// Search-only spellings (§9); never rendered.
  final List<String> aliases;
  const Religion({
    required this.id,
    required this.name,
    this.nameTamil = '',
    this.aliases = const [],
  });

  /// Tamil label in Tamil mode (when present), else the English name.
  String localizedName(bool tamil) =>
      tamil && nameTamil.trim().isNotEmpty ? nameTamil : name;

  /// The shared searchable form (English + Tamil + aliases).
  MasterOption get asOption =>
      MasterOption(id: id, en: name, ta: nameTamil, aliases: aliases);

  factory Religion.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return Religion.fromMap({'id': doc.id, ...d});
  }

  factory Religion.fromMap(Map<String, dynamic> m) => Religion(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        nameTamil: (m['nameTamil'] ?? '').toString(),
        aliases: [for (final a in (m['aliases'] as List? ?? const [])) a.toString()],
      );
}

class Caste {
  final String id;
  final String religionId;
  final String name;
  final String nameTamil;

  /// Search-only spellings (§9); never rendered.
  final List<String> aliases;
  const Caste({
    required this.id,
    required this.religionId,
    required this.name,
    this.nameTamil = '',
    this.aliases = const [],
  });

  String localizedName(bool tamil) =>
      tamil && nameTamil.trim().isNotEmpty ? nameTamil : name;

  /// The shared searchable form (English + Tamil + aliases).
  MasterOption get asOption => MasterOption(
      id: id, en: name, ta: nameTamil, aliases: aliases, parentId: religionId);

  factory Caste.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return Caste.fromMap({'id': doc.id, ...d});
  }

  factory Caste.fromMap(Map<String, dynamic> m) => Caste(
        id: (m['id'] ?? '').toString(),
        religionId: (m['religionId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        nameTamil: (m['nameTamil'] ?? '').toString(),
        aliases: [for (final a in (m['aliases'] as List? ?? const [])) a.toString()],
      );
}

class Subcaste {
  final String id;
  final String casteId;
  final String name;
  final String nameTamil;

  /// Search-only spellings (§9); never rendered.
  final List<String> aliases;
  const Subcaste({
    required this.id,
    required this.casteId,
    required this.name,
    this.nameTamil = '',
    this.aliases = const [],
  });

  String localizedName(bool tamil) =>
      tamil && nameTamil.trim().isNotEmpty ? nameTamil : name;

  /// The shared searchable form (English + Tamil + aliases).
  MasterOption get asOption => MasterOption(
      id: id, en: name, ta: nameTamil, aliases: aliases, parentId: casteId);

  factory Subcaste.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return Subcaste.fromMap({'id': doc.id, ...d});
  }

  factory Subcaste.fromMap(Map<String, dynamic> m) => Subcaste(
        id: (m['id'] ?? '').toString(),
        casteId: (m['casteId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        nameTamil: (m['nameTamil'] ?? '').toString(),
        aliases: [for (final a in (m['aliases'] as List? ?? const [])) a.toString()],
      );
}
