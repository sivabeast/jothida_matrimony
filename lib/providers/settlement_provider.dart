import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/consultation_model.dart';
import '../models/settlement_model.dart';
import 'service_providers.dart';

/// Every consultation on the platform (admin only). Powers all settlement /
/// payout derivation — the heavy `getDashboardAnalytics` Firestore pass is left
/// untouched (it still serves subscription revenue + verification + leaderboard).
final allConsultationsProvider =
    StreamProvider.autoDispose<List<ConsultationBooking>>(
        (ref) => ref.read(consultationServiceProvider).watchAll());

/// Live payout-settlement history (newest first).
final settlementsHistoryProvider =
    StreamProvider.autoDispose<List<Settlement>>(
        (ref) => ref.read(consultationServiceProvider).watchSettlements());

/// Per-astrologer payout summary — 100% of every delivered consultation, no
/// commission. All amounts in whole INR.
class AstrologerSettlement {
  final String astrologerId;
  final String name;
  final int completedBookings;
  final int total; // lifetime delivered earnings (= pending + paid)
  final int thisWeek; // delivered this week
  final int thisMonth; // delivered this month
  final int pendingPayout; // settleable, not yet paid out
  final int paidAmount; // already settled
  final DateTime? lastSettlement;

  const AstrologerSettlement({
    required this.astrologerId,
    required this.name,
    this.completedBookings = 0,
    this.total = 0,
    this.thisWeek = 0,
    this.thisMonth = 0,
    this.pendingPayout = 0,
    this.paidAmount = 0,
    this.lastSettlement,
  });
}

/// Monday 00:00 of the week containing [now].
DateTime weekStart(DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

/// First day 00:00 of [now]'s month.
DateTime monthStart(DateTime now) => DateTime(now.year, now.month, 1);

bool _isToday(DateTime? t, DateTime now) =>
    t != null && t.year == now.year && t.month == now.month && t.day == now.day;

/// Builds per-astrologer settlement summaries from every consultation, sorted by
/// pending payout (most owed first).
final astrologerSettlementsProvider =
    Provider.autoDispose<List<AstrologerSettlement>>((ref) {
  final all = ref.watch(allConsultationsProvider).valueOrNull ??
      const <ConsultationBooking>[];
  final now = DateTime.now();
  final ws = weekStart(now);
  final ms = monthStart(now);

  // astrologerId → mutable accumulator.
  final acc = <String, _Acc>{};
  for (final b in all) {
    if (b.astrologerId.isEmpty) continue;
    final a = acc.putIfAbsent(
        b.astrologerId, () => _Acc(b.astrologerId, b.astrologerName));
    if (b.astrologerName.isNotEmpty) a.name = b.astrologerName;

    if (b.isCompletedEarning && b.paid && b.refundedAt == null) {
      a.completedBookings++;
      a.total += b.amount;
      final dt = b.completedAt ?? b.createdAt;
      if (!dt.isBefore(ws)) a.thisWeek += b.amount;
      if (!dt.isBefore(ms)) a.thisMonth += b.amount;
      if (b.settled) {
        a.paidAmount += b.amount;
        if (b.settledAt != null &&
            (a.lastSettlement == null || b.settledAt!.isAfter(a.lastSettlement!))) {
          a.lastSettlement = b.settledAt;
        }
      } else {
        a.pendingPayout += b.amount;
      }
    }
  }

  final out = acc.values
      .map((a) => AstrologerSettlement(
            astrologerId: a.id,
            name: a.name,
            completedBookings: a.completedBookings,
            total: a.total,
            thisWeek: a.thisWeek,
            thisMonth: a.thisMonth,
            pendingPayout: a.pendingPayout,
            paidAmount: a.paidAmount,
            lastSettlement: a.lastSettlement,
          ))
      .toList()
    ..sort((x, y) => y.pendingPayout.compareTo(x.pendingPayout));
  return out;
});

/// Settlement summary for a single astrologer (the admin profile Payouts tab and
/// the astrologer's own earnings screen).
final astrologerSettlementByIdProvider = Provider.autoDispose
    .family<AstrologerSettlement, String>((ref, astrologerId) {
  final list = ref.watch(astrologerSettlementsProvider);
  return list.firstWhere(
    (s) => s.astrologerId == astrologerId,
    orElse: () => AstrologerSettlement(astrologerId: astrologerId, name: ''),
  );
});

/// The settleable bookings for one astrologer (what "Mark as Paid" will cover).
final settleableBookingsProvider = Provider.autoDispose
    .family<List<ConsultationBooking>, String>((ref, astrologerId) {
  final all = ref.watch(allConsultationsProvider).valueOrNull ??
      const <ConsultationBooking>[];
  return all
      .where((b) => b.astrologerId == astrologerId && b.isSettleable)
      .toList()
    ..sort((a, b) => (b.completedAt ?? b.createdAt)
        .compareTo(a.completedAt ?? a.createdAt));
});

/// Every paid booking awaiting an admin refund (astrologer rejected it).
final refundsDueProvider =
    Provider.autoDispose<List<ConsultationBooking>>((ref) {
  final all = ref.watch(allConsultationsProvider).valueOrNull ??
      const <ConsultationBooking>[];
  return all.where((b) => b.needsRefund).toList()
    ..sort((a, b) =>
        (b.respondedAt ?? b.createdAt).compareTo(a.respondedAt ?? a.createdAt));
});

/// Platform-wide settlement headline for the admin Dashboard.
class PlatformSettlementTotals {
  final int todaysBookings;
  final int todaysPaymentsReceived;
  final int pendingSettlements;
  final int totalSettled;
  final int refundsDue;
  final int weekEarned; // delivered this week
  final int weekSettled; // paid out this week
  final int monthEarned;
  final int monthSettled;

  const PlatformSettlementTotals({
    this.todaysBookings = 0,
    this.todaysPaymentsReceived = 0,
    this.pendingSettlements = 0,
    this.totalSettled = 0,
    this.refundsDue = 0,
    this.weekEarned = 0,
    this.weekSettled = 0,
    this.monthEarned = 0,
    this.monthSettled = 0,
  });
}

final platformSettlementTotalsProvider =
    Provider.autoDispose<PlatformSettlementTotals>((ref) {
  final all = ref.watch(allConsultationsProvider).valueOrNull ??
      const <ConsultationBooking>[];
  final now = DateTime.now();
  final ws = weekStart(now);
  final ms = monthStart(now);

  var todaysBookings = 0,
      todaysPaymentsReceived = 0,
      pendingSettlements = 0,
      totalSettled = 0,
      refundsDue = 0,
      weekEarned = 0,
      weekSettled = 0,
      monthEarned = 0,
      monthSettled = 0;

  for (final b in all) {
    if (_isToday(b.createdAt, now)) todaysBookings++;
    if (b.paid && b.refundedAt == null && _isToday(b.paidAt, now)) {
      todaysPaymentsReceived += b.amount;
    }
    if (b.isSettleable) pendingSettlements += b.amount;
    if (b.needsRefund) refundsDue += b.amount;

    if (b.settled) {
      totalSettled += b.amount;
      final st = b.settledAt;
      if (st != null && !st.isBefore(ws)) weekSettled += b.amount;
      if (st != null && !st.isBefore(ms)) monthSettled += b.amount;
    }
    if (b.isCompletedEarning && b.paid && b.refundedAt == null) {
      final dt = b.completedAt ?? b.createdAt;
      if (!dt.isBefore(ws)) weekEarned += b.amount;
      if (!dt.isBefore(ms)) monthEarned += b.amount;
    }
  }

  return PlatformSettlementTotals(
    todaysBookings: todaysBookings,
    todaysPaymentsReceived: todaysPaymentsReceived,
    pendingSettlements: pendingSettlements,
    totalSettled: totalSettled,
    refundsDue: refundsDue,
    weekEarned: weekEarned,
    weekSettled: weekSettled,
    monthEarned: monthEarned,
    monthSettled: monthSettled,
  );
});

/// Internal mutable accumulator for [astrologerSettlementsProvider].
class _Acc {
  final String id;
  String name;
  int completedBookings = 0;
  int total = 0;
  int thisWeek = 0;
  int thisMonth = 0;
  int pendingPayout = 0;
  int paidAmount = 0;
  DateTime? lastSettlement;
  _Acc(this.id, this.name);
}
