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
  final int completed;

  /// Sum of COMPLETED request amounts the user paid (₹) — the platform revenue
  /// this astrologer generated.
  final int revenue;

  /// Sum of per-completed-request commission owed to the astrologer (₹).
  final int commission;

  const AstrologerStats({
    required this.member,
    this.totalAssigned = 0,
    this.pending = 0,
    this.completed = 0,
    this.revenue = 0,
    this.commission = 0,
  });
}

/// Computes [AstrologerStats] for [m] from [all] requests + [cfg] commissions.
/// Earnings are based on COMPLETED requests only (spec §6).
AstrologerStats computeAstrologerStats(
  AstrologerTeamMember m,
  List<AstrologerRequestModel> all,
  AstrologyServiceConfig cfg,
) {
  if (m.uid.isEmpty) return AstrologerStats(member: m);
  final mine = all.where((r) => r.astrologerUid == m.uid).toList();
  final completed =
      mine.where((r) => r.status == AstrologerRequestStatus.completed).toList();
  final pending =
      mine.where((r) => r.status == AstrologerRequestStatus.pending).length;
  var revenue = 0;
  var commission = 0;
  for (final r in completed) {
    revenue += r.amount;
    commission += r.type == AstrologerRequestType.matching
        ? cfg.analysisCommission
        : cfg.appointmentCommission;
  }
  return AstrologerStats(
    member: m,
    totalAssigned: mine.length,
    pending: pending,
    completed: completed.length,
    revenue: revenue,
    commission: commission,
  );
}

/// Every `astrologer_requests` document (admin-only read) — powers the admin
/// performance dashboard's per-astrologer aggregation.
final allAstrologerRequestsProvider =
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
      ref.watch(allAstrologerRequestsProvider).valueOrNull ?? const [];
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
