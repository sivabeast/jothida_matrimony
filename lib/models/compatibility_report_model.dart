import 'package:cloud_firestore/cloud_firestore.dart';

/// Tri-state answer keys for the உண்டு / இல்லை selections. Stored as stable
/// strings so the report map stays readable in Firestore.
class CompatAnswer {
  static const String none = '';
  static const String yes = 'yes'; // உண்டு
  static const String no = 'no'; // இல்லை
}

/// The bride's / groom's details snapshotted INTO the report at save time so
/// the finished certificate never changes when a profile is edited later.
class CompatPerson {
  final String name;
  final String dob;
  final String birthTime;
  final String birthPlace;
  final String star;
  final String rasi;

  const CompatPerson({
    this.name = '',
    this.dob = '',
    this.birthTime = '',
    this.birthPlace = '',
    this.star = '',
    this.rasi = '',
  });

  factory CompatPerson.fromMap(Map<String, dynamic>? m) => CompatPerson(
        name: (m?['name'] ?? '').toString(),
        dob: (m?['dob'] ?? '').toString(),
        birthTime: (m?['birthTime'] ?? '').toString(),
        birthPlace: (m?['birthPlace'] ?? '').toString(),
        star: (m?['star'] ?? '').toString(),
        rasi: (m?['rasi'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'dob': dob,
        'birthTime': birthTime,
        'birthPlace': birthPlace,
        'star': star,
        'rasi': rasi,
      };
}

/// One திருமண பொருத்தம் table row: the bride/groom values written by the
/// employee plus the உண்டு / இல்லை verdict.
class PoruthamRow {
  final String bride;
  final String groom;
  final String match; // CompatAnswer

  const PoruthamRow({this.bride = '', this.groom = '', this.match = ''});

  factory PoruthamRow.fromMap(Map<String, dynamic>? m) => PoruthamRow(
        bride: (m?['bride'] ?? '').toString(),
        groom: (m?['groom'] ?? '').toString(),
        match: (m?['match'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() =>
      {'bride': bride, 'groom': groom, 'match': match};
}

/// One dosham table row (செவ்வாய் / பிற தோஷங்கள்): உண்டு / இல்லை for each side.
class DoshamRow {
  final String bride; // CompatAnswer
  final String groom; // CompatAnswer

  const DoshamRow({this.bride = '', this.groom = ''});

  factory DoshamRow.fromMap(Map<String, dynamic>? m) => DoshamRow(
        bride: (m?['bride'] ?? '').toString(),
        groom: (m?['groom'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {'bride': bride, 'groom': groom};
}

/// One திசா சந்தி table row: free-text values for each side.
class DasaRow {
  final String bride;
  final String groom;

  const DasaRow({this.bride = '', this.groom = ''});

  factory DasaRow.fromMap(Map<String, dynamic>? m) => DasaRow(
        bride: (m?['bride'] ?? '').toString(),
        groom: (m?['groom'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {'bride': bride, 'groom': groom};
}

/// The structured Professional Marriage Compatibility Report an employee fills
/// for a Horoscope Compatibility booking. Stored as ONE map under
/// `astrologer_requests/{id}.compatReport` (the assigned employee's update
/// rule already covers this write — no rules change).
class CompatibilityReport {
  /// The 11 porutham rows, in certificate order. ஆயுள் / இனம் / மொத்தம் are
  /// intentionally absent (spec: removed completely).
  static const List<String> poruthamNames = [
    'தினம்',
    'கணம்',
    'மகேந்திரம்',
    'ஸ்திரீதீர்க்கம்',
    'யோனி',
    'ராசி',
    'ராசி அதிபதி',
    'வசியம்',
    'ரஜ்ஜு',
    'வேதை',
    'நாடி',
  ];

  static const List<String> sevvaiNames = [
    'லக்னத்திற்கு',
    'சந்திரனுக்கு',
    'சுக்கிரனுக்கு',
  ];

  /// "பிற தோஷங்கள்" catch-all row is intentionally absent (spec: removed).
  static const List<String> otherDoshamNames = [
    'சர்ப்ப தோஷம்',
    'மாங்கல்ய தோஷம்',
  ];

  static const List<String> dasaNames = [
    'திசா சந்தி',
    'நடப்பு திசாபுத்தி',
  ];

  static const String statusDraft = 'draft';
  static const String statusSubmitted = 'submitted';

  final String status; // draft | submitted
  final CompatPerson bride;
  final CompatPerson groom;
  final List<PoruthamRow> porutham; // 11, aligned with [poruthamNames]
  final List<DoshamRow> sevvai; // 3, aligned with [sevvaiNames]
  final List<DoshamRow> otherDosham; // 2, aligned with [otherDoshamNames]
  final List<DasaRow> dasa; // 2, aligned with [dasaNames]
  final String explanation; // பொருத்தம் குறிப்பு / விளக்கம்
  final String finalResult; // CompatAnswer — பொருத்தம் உண்டு / இல்லை
  final String employeeName;
  final DateTime? submittedAt;
  final DateTime? updatedAt;

  const CompatibilityReport({
    this.status = statusDraft,
    this.bride = const CompatPerson(),
    this.groom = const CompatPerson(),
    this.porutham = const [],
    this.sevvai = const [],
    this.otherDosham = const [],
    this.dasa = const [],
    this.explanation = '',
    this.finalResult = '',
    this.employeeName = '',
    this.submittedAt,
    this.updatedAt,
  });

  bool get isSubmitted => status == statusSubmitted;

  /// Row at [i], tolerating shorter stored lists (older drafts).
  PoruthamRow poruthamAt(int i) =>
      i < porutham.length ? porutham[i] : const PoruthamRow();
  DoshamRow sevvaiAt(int i) =>
      i < sevvai.length ? sevvai[i] : const DoshamRow();
  DoshamRow otherDoshamAt(int i) =>
      i < otherDosham.length ? otherDosham[i] : const DoshamRow();
  DasaRow dasaAt(int i) => i < dasa.length ? dasa[i] : const DasaRow();

  /// Stable user-facing report number derived from the booking id.
  static String reportNumber(String requestId) {
    final clean = requestId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final part =
        (clean.length >= 8 ? clean.substring(0, 8) : clean).toUpperCase();
    return 'JM-$part';
  }

  /// Null when [raw] is absent/empty — the booking has no structured report.
  static CompatibilityReport? tryFrom(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return null;
    return CompatibilityReport.fromMap(raw);
  }

  factory CompatibilityReport.fromMap(Map<String, dynamic> m) {
    List<T> rows<T>(dynamic v, T Function(Map<String, dynamic>?) parse) {
      if (v is! List) return const [];
      return v
          .map((e) =>
              parse(e is Map ? Map<String, dynamic>.from(e) : null))
          .toList();
    }

    DateTime? date(dynamic v) => v is Timestamp ? v.toDate() : null;

    return CompatibilityReport(
      status: (m['status'] ?? statusDraft).toString(),
      bride: CompatPerson.fromMap(
          m['bride'] is Map ? Map<String, dynamic>.from(m['bride']) : null),
      groom: CompatPerson.fromMap(
          m['groom'] is Map ? Map<String, dynamic>.from(m['groom']) : null),
      porutham: rows(m['porutham'], PoruthamRow.fromMap),
      sevvai: rows(m['sevvai'], DoshamRow.fromMap),
      otherDosham: rows(m['otherDosham'], DoshamRow.fromMap),
      dasa: rows(m['dasa'], DasaRow.fromMap),
      explanation: (m['explanation'] ?? '').toString(),
      finalResult: (m['finalResult'] ?? '').toString(),
      employeeName: (m['employeeName'] ?? '').toString(),
      submittedAt: date(m['submittedAt']),
      updatedAt: date(m['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'status': status,
        'bride': bride.toMap(),
        'groom': groom.toMap(),
        'porutham': porutham.map((r) => r.toMap()).toList(),
        'sevvai': sevvai.map((r) => r.toMap()).toList(),
        'otherDosham': otherDosham.map((r) => r.toMap()).toList(),
        'dasa': dasa.map((r) => r.toMap()).toList(),
        'explanation': explanation,
        'finalResult': finalResult,
        'employeeName': employeeName,
        'submittedAt':
            submittedAt != null ? Timestamp.fromDate(submittedAt!) : null,
        'updatedAt':
            updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      };
}
