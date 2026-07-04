/// A single auspicious marriage (muhurtham) date shown on the Marriage
/// Muhurtham Calendar. Only GOOD dates exist in the dataset — inauspicious
/// days are simply absent, so the calendar can never highlight a bad day.
class MuhurthamDate {
  final DateTime date;

  /// What ceremonies the day suits, e.g. ['Marriage', 'Engagement'].
  final List<String> suitableFor;

  // ── Panchang details ──
  final String tithi;
  final String nakshatra;
  final String yoga;
  final String karana;

  /// General explanation of why this date is auspicious.
  final String description;

  const MuhurthamDate({
    required this.date,
    required this.suitableFor,
    required this.tithi,
    required this.nakshatra,
    required this.yoga,
    required this.karana,
    required this.description,
  });

  /// Calendar-grid key: 'yyyy-m-d' (no zero padding — always built the same
  /// way by [keyFor], so lookups are consistent).
  String get key => keyFor(date);

  static String keyFor(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
