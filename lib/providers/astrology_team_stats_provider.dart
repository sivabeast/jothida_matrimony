import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/astrologer_request_model.dart';
import '../models/astrologer_team_member.dart';
import '../models/astrology_service_config.dart';
import 'astrology_config_provider.dart';
import 'astrology_team_provider.dart';
import 'service_providers.dart';

/// Performance metrics for one astrologer, computed from their assigned
/// requests + the admin-configured per-completed-request commissions.
class AstrologerStats {
  final AstrologerTeamMember member;
  final int totalAssigned;
  final int pending;
  final int inProgress;
  final int completed;
  final int todayCompleted;
  final int monthCompleted;

  /// Sum of COMPLETED request amounts the user paid (₹) — the platform revenue
  /// this astrologer generated.
  final int revenue;

  /// Sum of per-completed-request commission owed to the astrologer (₹).
  final int commission;

  /// The current per-completed-report analysis commission (₹) from config.
  final int commissionPerReport;

  const AstrologerStats({
    required this.member,
    this.totalAssigned = 0,
    this.pending = 0,
    this.inProgress = 0,
    this.completed = 0,
    this.todayCompleted = 0,
    this.monthCompleted = 0,
    this.revenue = 0,
    this.commission = 0,
    this.commissionPerReport = 0,
  });
}

/// Computes [AstrologerStats] for [m] from [all] requests + [cfg] commissions.
/// Matches on the stable `astrologerEmail` (works before/after the astrologer's
/// first sign-in). Earnings are based on COMPLETED requests only (spec §6/§8).
AstrologerStats computeAstrologerStats(
  AstrologerTeamMember m,
  List<AstrologerRequestModel> all,
  AstrologyServiceConfig cfg,
) {
  final now = DateTime.now();
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  final mine = all.where((r) => r.astrologerEmail == m.email).toList();
  final completed =
      mine.where((r) => r.status == AstrologerRequestStatus.completed).toList();
  // Pending = assigned, not yet started; In Progress = started (inProgress).
  final pending = mine
      .where((r) =>
          r.status == AstrologerRequestStatus.pending && !r.inProgress)
      .length;
  final inProgress = mine
      .where(
          (r) => r.status == AstrologerRequestStatus.pending && r.inProgress)
      .length;
  var revenue = 0;
  var commission = 0;
  var todayCompleted = 0;
  var monthCompleted = 0;
  for (final r in completed) {
    revenue += r.amount;
    commission += r.type == AstrologerRequestType.matching
        ? cfg.analysisCommission
        : cfg.appointmentCommission;
    final c = r.completedAt;
    if (c != null) {
      if (sameDay(c, now)) todayCompleted++;
      if (c.year == now.year && c.month == now.month) monthCompleted++;
    }
  }
  return AstrologerStats(
    member: m,
    totalAssigned: mine.length,
    pending: pending,
    inProgress: inProgress,
    completed: completed.length,
    todayCompleted: todayCompleted,
    monthCompleted: monthCompleted,
    revenue: revenue,
    commission: commission,
    commissionPerReport: cfg.analysisCommission,
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
