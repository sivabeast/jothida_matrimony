/// One selectable value that knows BOTH of its names and how to be searched.
///
/// Every structured dropdown in the app (education level, degree, employment
/// status, occupation, country, state…) is built from these. The point is that
/// a single object carries:
///
///  * [en] — the canonical value **written to Firestore**. Storage never
///    changes with the UI language, so matching, filters, the admin screens and
///    the website all keep working exactly as before.
///  * [ta] — the Tamil display name.
///  * [aliases] — extra spellings people actually type ("Virudunagar",
///    "bsc", "sw engineer"). Never displayed, only matched.
///
/// and that [matches] searches across all three, which is what makes §9's
/// bilingual search work: a member reading விருதுநகர் on screen can type
/// "viru", and a member reading "Virudhunagar" can type "விருது".
class MasterOption {
  /// Stable key. For hierarchical data this is what children point at via
  /// [parentId]; for flat lists it is just a slug of [en].
  final String id;

  /// Canonical English value — this is what gets stored.
  final String en;

  /// Tamil display name. Empty means "no Tamil form", and the English is shown
  /// in both languages (correct for things like "MBA" used as a proper noun).
  final String ta;

  /// Additional search-only spellings. Matched, never rendered.
  final List<String> aliases;

  /// Owning parent's [id] — religion for a caste, level for a degree,
  /// employment type for an occupation. Null for top-level entries.
  final String? parentId;

  const MasterOption({
    required this.id,
    required this.en,
    this.ta = '',
    this.aliases = const [],
    this.parentId,
  });

  factory MasterOption.fromMap(Map<String, dynamic> map) => MasterOption(
        id: (map['id'] ?? '').toString(),
        en: (map['en'] ?? map['name'] ?? '').toString(),
        ta: (map['ta'] ?? map['nameTamil'] ?? '').toString(),
        aliases: [
          for (final a in (map['aliases'] as List? ?? const []))
            a.toString(),
        ],
        parentId: (map['parentId'] ?? map['parent']) as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'en': en,
        if (ta.isNotEmpty) 'ta': ta,
        if (aliases.isNotEmpty) 'aliases': aliases,
        if (parentId != null) 'parentId': parentId,
      };

  /// What the member reads.
  ///
  /// [withEnglish] appends the English name in brackets — used for degrees and
  /// occupations, where the English term is what people actually say out loud
  /// ("இளங்கலை அறிவியல் (B.Sc)"). Ordinary vocabulary (gender, marital status,
  /// districts) is shown as pure Tamil, so it stays off by default.
  String display({required bool tamil, bool withEnglish = false}) {
    if (!tamil || ta.isEmpty || ta == en) return en;
    return withEnglish ? '$ta ($en)' : ta;
  }

  /// True when [query] matches the English name, the Tamil name or any alias.
  ///
  /// Matching is punctuation-insensitive on the English side so "bsc" finds
  /// "B.Sc" and "uiux" finds "UI / UX Designer".
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (ta.contains(query.trim())) return true;
    if (en.toLowerCase().contains(q)) return true;
    for (final a in aliases) {
      if (a.toLowerCase().contains(q)) return true;
    }
    final sq = squash(q);
    if (sq.isEmpty) return false;
    if (squash(en).contains(sq)) return true;
    for (final a in aliases) {
      if (squash(a).contains(sq)) return true;
    }
    return false;
  }

  /// Lower-cased with every non-alphanumeric character removed, so spacing,
  /// dots and slashes stop mattering ("B.Sc" → "bsc").
  static String squash(String s) {
    final buf = StringBuffer();
    for (final c in s.toLowerCase().codeUnits) {
      final isDigit = c >= 0x30 && c <= 0x39;
      final isLower = c >= 0x61 && c <= 0x7A;
      if (isDigit || isLower) buf.writeCharCode(c);
    }
    return buf.toString();
  }

  /// A url-safe slug of [value], used to mint ids for flat catalogues.
  static String slug(String value) {
    final buf = StringBuffer();
    var lastWasDash = true; // trims leading dashes
    for (final c in value.toLowerCase().codeUnits) {
      final isDigit = c >= 0x30 && c <= 0x39;
      final isLower = c >= 0x61 && c <= 0x7A;
      if (isDigit || isLower) {
        buf.writeCharCode(c);
        lastWasDash = false;
      } else if (!lastWasDash) {
        buf.write('_');
        lastWasDash = true;
      }
    }
    final s = buf.toString();
    return s.endsWith('_') ? s.substring(0, s.length - 1) : s;
  }

  @override
  bool operator ==(Object other) =>
      other is MasterOption && other.id == id && other.en == en;

  @override
  int get hashCode => Object.hash(id, en);

  @override
  String toString() => 'MasterOption($id, $en / $ta)';
}

/// Helpers for working with a catalogue of [MasterOption]s.
extension MasterOptionList on List<MasterOption> {
  /// Just the canonical English values, in list order — the shape the existing
  /// pickers and the stored profile fields still speak.
  List<String> get values => [for (final o in this) o.en];

  /// The option whose [MasterOption.en] equals [value], case-insensitively.
  MasterOption? byValue(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final o in this) {
      if (o.en.toLowerCase() == v) return o;
    }
    return null;
  }

  /// The option with [id].
  MasterOption? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final o in this) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Children of [parentId], in list order.
  List<MasterOption> childrenOf(String? parentId) =>
      [for (final o in this) if (o.parentId == parentId) o];

  /// Everything matching [query] (see [MasterOption.matches]).
  List<MasterOption> search(String query) =>
      [for (final o in this) if (o.matches(query)) o];
}
