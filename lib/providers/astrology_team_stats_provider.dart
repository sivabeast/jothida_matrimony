import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/astrologer_request_model.dart';
import '../models/astrologer_team_member.dart';
import '../models/astrology_service_config.dart';
import '../models/payroll_payment.dart';
import 'astrology_config_provider.dart';
import 'astrology_team_provider.dart';
import 'service_providers.dart';

/// Weekly work counters (assigned / completed / pending) for one period.
class WeeklyStat {
  final int assigned;
  final int completed;
  final int pending;
  const WeeklyStat(
      {this.assigned = 0, this.completed = 0, this.pending = 0});

  /// Completion rate as a whole-number percentage (spec §15).
  int get completionRate =>
      assigned == 0 ? 0 : ((completed / assigned) * 100).round();
}

/// Performance metrics for one employee, computed from their assigned
/// requests. Earnings use a COMMISSION PER COMPLETED REPORT (a single global
/// rate the admin configures), not a salary.
class AstrologerStats {
  final AstrologerTeamMember member;
  final int totalAssigned;
  final int pending; // assigned, not yet completed
  final int inProgress;
  final int completed;
  final int todayAssigned;
  final int todayCompleted;
  final int monthCompleted;

  final WeeklyStat thisWeek;
  final WeeklyStat lastWeek;

  /// Sum of COMPLETED request amounts the user paid (₹) — platform revenue.
  final int revenue;

  /// Commission (₹) paid to the employee per completed report — the single
  /// global rate from `AstrologyServiceConfig.analysisCommission`.
  final int commissionPerReport;

  /// Reports completed in the CURRENT payroll cycle — i.e. since the admin
  /// last hit "Mark As Paid" (`member.lastPaidDate`). This is what the weekly
  /// payroll pays out: after a payment the cycle restarts from ZERO, so
  /// commission never accumulates across paid weeks.
  final int cycleCompleted;

  const AstrologerStats({
    required this.member,
    this.totalAssigned = 0,
    this.pending = 0,
    this.inProgress = 0,
    this.completed = 0,
    this.todayAssigned = 0,
    this.todayCompleted = 0,
    this.monthCompleted = 0,
    this.thisWeek = const WeeklyStat(),
    this.lastWeek = const WeeklyStat(),
    this.revenue = 0,
    this.commissionPerReport = 0,
    this.cycleCompleted = 0,
  });

  /// Commission earned this calendar week = completed-this-week × rate.
  int get weeklyCommission => thisWeek.completed * commissionPerReport;

  /// Commission earned this month = completed-this-month × rate.
  int get monthlyCommission => monthCompleted * commissionPerReport;

  /// Total commission earned (all-time) = total completed × rate.
  int get totalCommission => completed * commissionPerReport;

  /// Commission the admin has already paid out to this employee.
  int get paidCommission => member.paidCommission;

  /// THE payroll number: commission owed for the CURRENT cycle (reports
  /// completed since the last "Mark As Paid"). Resets to ₹0 the moment the
  /// admin pays — e.g. week 1 earns ₹5000, admin pays, week 2 earning ₹50
  /// shows ₹50 (never ₹5050).
  int get cycleCommission => cycleCompleted * commissionPerReport;

  /// Payment status for the current cycle: money owed → Pending; nothing owed
  /// after at least one payout → Paid; brand-new employee with no activity → —.
  String get paymentStatusLabel {
    if (cycleCommission > 0) return 'Pending';
    if (member.lastPaidDate != null) return 'Paid';
    return '—';
  }
}

DateTime _startOfWeek(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1)); // Monday 00:00
}

/// Computes [AstrologerStats] for [m] from [all] requests. Matches on the stable
/// `astrologerEmail` (works before/after first sign-in). Weekly buckets use
/// `assignedAt` (assigned) and `completedAt` (completed).
AstrologerStats computeAstrologerStats(
  AstrologerTeamMember m,
  List<AstrologerRequestModel> all,
  AstrologyServiceConfig cfg,
) {
  final now = DateTime.now();
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  final thisWeekStart = _startOfWeek(now);
  final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));

  final mine = all.where((r) => r.astrologerEmail == m.email).toList();
  final completedList =
      mine.where((r) => r.status == AstrologerRequestStatus.completed).toList();
  final pending = mine
      .where((r) =>
          r.status == AstrologerRequestStatus.pending && !r.inProgress)
      .length;
  final inProgress = mine
      .where(
          (r) => r.status == AstrologerRequestStatus.pending && r.inProgress)
      .length;

  var revenue = 0;
  var todayCompleted = 0;
  var monthCompleted = 0;
  var cycleCompleted = 0;
  final cycleStart = m.lastPaidDate; // null → everything is still unpaid
  for (final r in completedList) {
    revenue += r.amount;
    final c = r.completedAt;
    if (c != null) {
      if (sameDay(c, now)) todayCompleted++;
      if (c.year == now.year && c.month == now.month) monthCompleted++;
      if (cycleStart == null || c.isAfter(cycleStart)) cycleCompleted++;
    }
  }
  final todayAssigned = mine
      .where((r) => r.assignedAt != null && sameDay(r.assignedAt!, now))
      .length;

  bool notCompleted(AstrologerRequestModel r) =>
      r.status != AstrologerRequestStatus.completed;

  WeeklyStat weekly(DateTime start, DateTime end) {
    final assigned = mine
        .where((r) =>
            r.assignedAt != null &&
            !r.assignedAt!.isBefore(start) &&
            r.assignedAt!.isBefore(end))
        .toList();
    final completed = mine
        .where((r) =>
            r.completedAt != null &&
            !r.completedAt!.isBefore(start) &&
            r.completedAt!.isBefore(end))
        .length;
    final pend = assigned.where(notCompleted).length;
    return WeeklyStat(
        assigned: assigned.length, completed: completed, pending: pend);
  }

  return AstrologerStats(
    member: m,
    totalAssigned: mine.length,
    pending: pending,
    inProgress: inProgress,
    completed: completedList.length,
    todayAssigned: todayAssigned,
    todayCompleted: todayCompleted,
    monthCompleted: monthCompleted,
    thisWeek: weekly(thisWeekStart, now.add(const Duration(days: 1))),
    lastWeek: weekly(lastWeekStart, thisWeekStart),
    revenue: revenue,
    commissionPerReport: cfg.analysisCommission,
    cycleCompleted: cycleCompleted,
  );
}

/// Live stats for the SIGNED-IN astrologer (their own dashboard). Reads only
/// their own requests by email — no admin-wide read needed.
final myAstrologerStatsProvider =
    Provider.autoDispose<AstrologerStats?>((ref) {
  final member = ref.watch(myAstrologerTeamMemberProvider).valueOrNull;
  if (member == null) return null;
  final requests =
      ref.watch(myAssignedRequestsProvider).valueOrNull ?? const [];
  final cfg = ref.watch(astrologyServiceConfigValueProvider);
  return computeAstrologerStats(member, requests, cfg);
});

/// Every `astrologer_requests` document (admin-only read) — powers the admin
/// performance dashboard's per-astrologer aggregation. Private to this file to
/// avoid clashing with admin_provider's identically-named provider.
final _allRequestsForStatsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>((ref) {
  return ref.read(astrologerServiceProvider).watchAllRequests();
});

/// All astrologers with their performance stats, busiest (most completed)
/// first. Admin performance dashboard.
final astrologerStatsProvider =
    Provider.autoDispose<List<AstrologerStats>>((ref) {
  final members =
      ref.watch(allAstrologerTeamProvider).valueOrNull ?? const [];
  final requests =
      ref.watch(_allRequestsForStatsProvider).valueOrNull ?? const [];
  final cfg = ref.watch(astrologyServiceConfigValueProvider);
  final list = [
    for (final m in members) computeAstrologerStats(m, requests, cfg)
  ]..sort((a, b) => b.completed.compareTo(a.completed));
  return list;
});

/// Stats for a single astrologer by registry id (emailKey) — details page.
final astrologerStatsByIdProvider =
    Provider.autoDispose.family<AstrologerStats?, String>((ref, emailKey) {
  for (final s in ref.watch(astrologerStatsProvider)) {
    if (s.member.id == emailKey) return s;
  }
  return null;
});

// ── Weekly payroll ───────────────────────────────────────────────────────────

/// Total commission payable RIGHT NOW across all employees (sum of every
/// employee's current-cycle commission) — the Employees page payroll banner.
final totalPayableCommissionProvider = Provider.autoDispose<int>((ref) {
  var total = 0;
  for (final s in ref.watch(astrologerStatsProvider)) {
    total += s.cycleCommission;
  }
  return total;
});

/// Weekly payment history for one employee (newest first).
final payrollHistoryProvider = StreamProvider.autoDispose
    .family<List<PayrollPayment>, String>((ref, emailKey) {
  return ref.read(astrologyTeamServiceProvider).watchPayrollHistory(emailKey);
});

/// The signed-in employee's own weekly payment history.
final myPayrollHistoryProvider =
    StreamProvider.autoDispose<List<PayrollPayment>>((ref) {
  final member = ref.watch(myAstrologerTeamMemberProvider).valueOrNull;
  if (member == null) return Stream.value(const []);
  return ref.read(astrologyTeamServiceProvider).watchPayrollHistory(member.id);
});
