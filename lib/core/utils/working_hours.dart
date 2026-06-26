/// Working-hour math for astrologer response deadlines.
///
/// Match-analysis acceptance is measured in WORKING hours: the band
/// 00:00–07:00 (midnight → 7 AM) is excluded entirely — time does not count
/// while the astrologer is expected to be asleep. So "12 working hours" from an
/// 8 PM booking lands at 3 PM the next day, not 8 AM.
///
/// The exact same logic is mirrored server-side in `functions/index.js`
/// (`addWorkingTime` / `workingTimeBetween`) so the Cloud-Functions reminder /
/// expiry sweep and the on-device countdown always agree.
library;

/// First hour of the working window (07:00). Everything in [0, 7) is excluded.
const int kWorkingDayStartHour = 7;

/// The match-analysis response window, measured in WORKING hours (spec §6).
const Duration kMatchAnalysisWorkingWindow = Duration(hours: 12);

/// Moves [t] forward to 07:00 the same day if it falls inside 00:00–07:00.
DateTime _clampToWorking(DateTime t) => t.hour < kWorkingDayStartHour
    ? DateTime(t.year, t.month, t.day, kWorkingDayStartHour)
    : t;

/// The wall-clock instant reached by adding [amount] of WORKING time to [start],
/// skipping every 00:00–07:00 band along the way.
///
/// Example: start 20:00 + 12h working → 4h until midnight, then 8h from 07:00 →
/// 15:00 the next day.
DateTime addWorkingTime(DateTime start, Duration amount) {
  if (amount <= Duration.zero) return start;
  var remaining = amount;
  var cur = start;
  var guard = 0;
  while (remaining > Duration.zero && guard++ < 2000) {
    cur = _clampToWorking(cur);
    final endOfDay = DateTime(cur.year, cur.month, cur.day + 1); // next 00:00
    final avail = endOfDay.difference(cur);
    if (remaining <= avail) return cur.add(remaining);
    remaining -= avail;
    cur = endOfDay; // → next midnight, clamped to 07:00 on the next iteration
  }
  return cur;
}

/// The amount of WORKING time between [from] and [to] (zero if [to] ≤ [from]),
/// excluding every 00:00–07:00 band. Drives the live countdown so the timer
/// visibly pauses overnight and only counts working hours.
Duration workingTimeBetween(DateTime from, DateTime to) {
  if (!to.isAfter(from)) return Duration.zero;
  var cur = from;
  var total = Duration.zero;
  var guard = 0;
  while (cur.isBefore(to) && guard++ < 2000) {
    final c = _clampToWorking(cur);
    if (!c.isBefore(to)) break;
    final endOfDay = DateTime(c.year, c.month, c.day + 1);
    final segEnd = endOfDay.isBefore(to) ? endOfDay : to;
    total += segEnd.difference(c);
    cur = endOfDay;
  }
  return total;
}

/// The deadline by which a match-analysis booking created at [createdAt] must be
/// accepted (12 working hours later).
DateTime matchAnalysisDeadline(DateTime createdAt) =>
    addWorkingTime(createdAt, kMatchAnalysisWorkingWindow);

/// "8h 24m"-style label for a remaining duration. "0m" once expired/zero.
String formatWorkingRemaining(Duration d) {
  if (d <= Duration.zero) return '0m';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h <= 0) return '${m}m';
  return '${h}h ${m}m';
}
