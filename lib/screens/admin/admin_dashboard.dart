import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_team_member.dart';
import '../../models/dashboard_analytics.dart';
import '../../providers/admin_provider.dart';
import '../../providers/astrology_team_provider.dart';
import 'admin_export.dart' show inr;

/// The admin Dashboard — intentionally minimal (per spec):
///
///   • REVENUE REPORTS — Today's Revenue · This Month Revenue · Total Revenue
///     (user subscriptions + paid astrology services, from
///     [dashboardAnalyticsProvider]).
///   • EMPLOYEE SUMMARY — Total · Available · Unavailable employees (live from
///     the `astrology_team` registry).
///
/// Nothing else: the old revenue charts, trend toggles, pending-verification
/// list, top performers, expiry alerts and activity timeline were removed.
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(dashboardAnalyticsProvider);
    final a = analyticsAsync.valueOrNull ?? const DashboardAnalytics();
    final loading =
        analyticsAsync.isLoading && analyticsAsync.valueOrNull == null;

    final team = ref.watch(allAstrologerTeamProvider).valueOrNull ??
        const <AstrologerTeamMember>[];
    final totalEmployees = team.length;
    final availableEmployees = team.where((m) => m.isAssignable).length;
    final unavailableEmployees = totalEmployees - availableEmployees;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(dashboardAnalyticsProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text('Dashboard',
              style: TextStyle(
                  fontSize: 24,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Operations overview',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 16),

          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            ),

          // ── Revenue Reports ─────────────────────────────────────────────
          const _SectionTitle('Revenue Reports'),
          _StatCard(
            icon: Icons.today_outlined,
            color: AppColors.success,
            label: "Today's Revenue",
            value: inr(a.revenueToday),
          ),
          const SizedBox(height: 10),
          _StatCard(
            icon: Icons.calendar_month_outlined,
            color: const Color(0xFF2F80ED),
            label: 'This Month Revenue',
            value: inr(a.revenueMonth),
          ),
          const SizedBox(height: 10),
          _StatCard(
            icon: Icons.account_balance_outlined,
            color: AppColors.gold,
            label: 'Total Revenue',
            value: inr(a.revenueTotal),
          ),
          const SizedBox(height: 24),

          // ── Employee Summary ────────────────────────────────────────────
          const _SectionTitle('Employee Summary'),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.badge_outlined,
                  color: AppColors.primary,
                  label: 'Total\nEmployees',
                  value: '$totalEmployees',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  icon: Icons.how_to_reg_outlined,
                  color: AppColors.success,
                  label: 'Available\nEmployees',
                  value: '$availableEmployees',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  icon: Icons.person_off_outlined,
                  color: AppColors.error,
                  label: 'Unavailable\nEmployees',
                  value: '$unavailableEmployees',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section title ────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 16,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold)),
      );
}

/// Full-width revenue stat card (icon · label · big value).
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 19,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Compact employee-summary tile (icon · value · two-line label).
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _MiniStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, height: 1.1)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}
