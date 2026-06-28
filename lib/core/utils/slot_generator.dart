import '../../models/astrologer_account_model.dart';

/// A single bookable time slot, as minutes-from-midnight.
class ConsultationSlot {
  final int startMinutes;
  final int endMinutes;

  /// Whether this slot is already taken by another booking.
  final bool booked;

  const ConsultationSlot({
    required this.startMinutes,
    required this.endMinutes,
    this.booked = false,
  });

  String get label => formatMinutes(startMinutes);
  String get rangeLabel =>
      '${formatMinutes(startMinutes)} – ${formatMinutes(endMinutes)}';

  ConsultationSlot copyWith({bool? booked}) => ConsultationSlot(
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        booked: booked ?? this.booked,
      );
}

/// Formats minutes-from-midnight as a 12-hour clock, e.g. 510 → "08:30 AM".
String formatMinutes(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final ampm = h24 >= 12 ? 'PM' : 'AM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $ampm';
}

/// Parses a `HHmm` slot key (e.g. "0830") to minutes-from-midnight, or null.
int? minutesFromSlotKey(String key) {
  if (key.length != 4) return null;
  final h = int.tryParse(key.substring(0, 2));
  final m = int.tryParse(key.substring(2));
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// `yyyy-MM-dd` key for a date (date-only, ignores time).
String dateKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Canonical Mon→Sun weekday name for a date (matches [kWeekdays]).
String weekdayNameOf(DateTime d) => kWeekdays[d.weekday - 1];

/// Generates the slots for a window, skipping any slot that overlaps the lunch
/// break. Pure — same inputs always yield the same slots.
///
/// A slot is kept only if it fits entirely within the available window and does
/// NOT overlap [lunchStart, lunchEnd).
List<ConsultationSlot> generateSlots({
  required int startMinutes,
  required int endMinutes,
  required int slotDuration,
  int? lunchStart,
  int? lunchEnd,
}) {
  final slots = <ConsultationSlot>[];
  if (slotDuration <= 0 || endMinutes <= startMinutes) return slots;
  final ls = lunchStart;
  final le = lunchEnd;
  for (var t = startMinutes; t + slotDuration <= endMinutes; t += slotDuration) {
    final slotEnd = t + slotDuration;
    // Skip a slot that overlaps the lunch break at all. The inline null checks
    // promote ls/le to non-null in the comparisons.
    if (ls != null && le != null && le > ls && t < le && slotEnd > ls) {
      continue;
    }
    slots.add(ConsultationSlot(startMinutes: t, endMinutes: slotEnd));
  }
  return slots;
}

/// Generates slots stepping by `slotDuration + breakDuration` so a configurable
/// BREAK gap sits after every slot (spec: Slot Duration + Break Time). Each slot
/// is [slotDuration] long; the next starts after the break. A slot that overlaps
/// the optional lunch window is skipped. Pure — same inputs, same output.
///
/// Example: start 540 (9:00), duration 30, break 0 → 9:00, 9:30, 10:00 …
///          start 540, duration 30, break 10 → 9:00, 9:40, 10:20 …
List<ConsultationSlot> generateSlotsWithBreak({
  required int startMinutes,
  required int endMinutes,
  required int slotDuration,
  int breakDuration = 0,
  int? lunchStart,
  int? lunchEnd,
}) {
  final slots = <ConsultationSlot>[];
  if (slotDuration <= 0 || endMinutes <= startMinutes) return slots;
  final step = slotDuration + (breakDuration > 0 ? breakDuration : 0);
  final ls = lunchStart;
  final le = lunchEnd;
  // Hard bound so a tiny step can't loop unreasonably long.
  var guard = 0;
  for (var t = startMinutes; t + slotDuration <= endMinutes; t += step) {
    if (guard++ > 500) break;
    final slotEnd = t + slotDuration;
    if (ls != null && le != null && le > ls && t < le && slotEnd > ls) {
      continue; // overlaps lunch
    }
    slots.add(ConsultationSlot(startMinutes: t, endMinutes: slotEnd));
  }
  return slots;
}

/// The next [count] working days (Mon–Fri by default), starting today and
/// skipping weekends (spec §8/§9). [workingWeekdays] uses Dart weekday ints
/// (Mon = 1 … Sun = 7). Never returns weekend dates and never looks a month
/// ahead — it stops as soon as [count] working days are collected.
List<DateTime> nextWorkingDays(
  int count, {
  List<int> workingWeekdays = const [1, 2, 3, 4, 5],
}) {
  final out = <DateTime>[];
  final today = DateTime.now();
  var d = DateTime(today.year, today.month, today.day);
  // Hard safety bound so a misconfigured (empty) weekday list can't loop forever.
  var guard = 0;
  while (out.length < count && guard < 60) {
    if (workingWeekdays.contains(d.weekday)) out.add(d);
    d = d.add(const Duration(days: 1));
    guard++;
  }
  return out;
}

/// The bookable days inside a ROLLING ONE-WEEK window (the new Astrology page
/// schedule): the next 7 CALENDAR days starting today, keeping only working
/// weekdays and dropping any [holidayDates] (`yyyy-MM-dd`). Weekends are never
/// shown. Re-evaluated every call, so the strip automatically rolls forward
/// each day.
///
/// Example (today = Wed, Mon–Fri working): Wed, Thu, Fri, Mon, Tue — Sat & Sun
/// are skipped because they fall outside the working weekdays.
List<DateTime> rollingWeekWorkingDays({
  List<int> workingWeekdays = const [1, 2, 3, 4, 5],
  List<String> holidayDates = const [],
  int calendarDays = 7,
}) {
  final out = <DateTime>[];
  final today = DateTime.now();
  final holidays = holidayDates.toSet();
  for (var i = 0; i < calendarDays; i++) {
    final d = DateTime(today.year, today.month, today.day + i);
    if (!workingWeekdays.contains(d.weekday)) continue; // weekend / non-working
    if (holidays.contains(dateKeyOf(d))) continue; // admin holiday
    out.add(d);
  }
  return out;
}

/// All slots for [account]'s configured window (no booking info applied).
List<ConsultationSlot> slotsForAccount(AstrologerAccount account) =>
    generateSlots(
      startMinutes: account.availableStartMinutes,
      endMinutes: account.availableEndMinutes,
      slotDuration: account.slotDurationMinutes,
      lunchStart: account.lunchStartMinutes,
      lunchEnd: account.lunchEndMinutes,
    );

/// Why a date can't be booked (or [DateAvailability.open] when it can).
enum DateAvailability { open, dayOff, unavailable, fullyBooked, past }

extension DateAvailabilityX on DateAvailability {
  bool get isSelectable => this == DateAvailability.open;
  String get label {
    switch (this) {
      case DateAvailability.open:
        return 'Available';
      case DateAvailability.dayOff:
        return 'Day off';
      case DateAvailability.unavailable:
        return 'Unavailable';
      case DateAvailability.fullyBooked:
        return 'Fully Booked';
      case DateAvailability.past:
        return 'Past';
    }
  }
}

/// Resolves whether a user may book [account] on [date], given the number of
/// active bookings already on that date ([activeBookingsOnDate]).
DateAvailability dateAvailability(
  AstrologerAccount account,
  DateTime date, {
  required int activeBookingsOnDate,
}) {
  final today = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final t0 = DateTime(today.year, today.month, today.day);
  if (d.isBefore(t0)) return DateAvailability.past;
  if (!account.workingDays.contains(weekdayNameOf(d))) {
    return DateAvailability.dayOff;
  }
  if (account.unavailableDates.contains(dateKeyOf(d))) {
    return DateAvailability.unavailable;
  }
  final totalSlots = slotsForAccount(account).length;
  if (totalSlots == 0) return DateAvailability.unavailable;
  final cap = account.maxBookingsPerDay > 0
      ? account.maxBookingsPerDay
      : totalSlots;
  if (activeBookingsOnDate >= cap || activeBookingsOnDate >= totalSlots) {
    return DateAvailability.fullyBooked;
  }
  return DateAvailability.open;
}

/// The soonest open date + slot for [account], scanning the next [withinDays]
/// days (skipping day-offs, unavailable & fully-booked dates and, for today,
/// slots already in the past). Returns null if nothing is open in the window.
({DateTime date, ConsultationSlot slot})? nextAvailableSlot(
  AstrologerAccount account,
  Map<String, Set<String>> bookedByDate, {
  int withinDays = 30,
}) {
  final today = DateTime.now();
  final nowMinutes = today.hour * 60 + today.minute;
  for (var i = 0; i < withinDays; i++) {
    final d = DateTime(today.year, today.month, today.day + i);
    final taken = bookedByDate[dateKeyOf(d)] ?? const <String>{};
    if (!dateAvailability(account, d, activeBookingsOnDate: taken.length)
        .isSelectable) {
      continue;
    }
    final takenMinutes =
        taken.map(minutesFromSlotKey).whereType<int>().toSet();
    for (final s in slotsForAccount(account)) {
      if (takenMinutes.contains(s.startMinutes)) continue;
      if (i == 0 && s.startMinutes <= nowMinutes) continue;
      return (date: d, slot: s);
    }
  }
  return null;
}

/// Returns [account]'s slots for [date] with [bookedStartMinutes] flagged as
/// taken, so the picker can disable already-booked slots.
List<ConsultationSlot> slotsForDate(
  AstrologerAccount account,
  DateTime date, {
  required Set<int> bookedStartMinutes,
}) {
  return slotsForAccount(account)
      .map((s) =>
          s.copyWith(booked: bookedStartMinutes.contains(s.startMinutes)))
      .toList();
}
