import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrologer_team_member.dart';
import '../../models/dashboard_analytics.dart';
import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/astrology_team_provider.dart';
import '../../providers/report_provider.dart';
import 'admin_export.dart' show inr;

/// The admin Dashboard — a realtime Matrimony CRM overview:
///
///   • LIVE OVERVIEW — users / profiles / approvals / astrology-request /
///     registration counters, all streamed from Firestore (no manual refresh):
///     [allUsersProvider], [allProfilesProvider],
///     [allAstrologerRequestsProvider] and the polled
///     [adminAggregateCountsProvider]. Dummy (seeded) profiles are excluded
///     from every profile stat.
///   • QUICK ACTIONS — Pending Approvals (live queue count) and Activity Log.
///   • REVENUE REPORTS — Today's · This Month · Total revenue
///     (from [dashboardAnalyticsProvider]).
///   • EMPLOYEE SUMMARY — Total · Available · Unavailable employees (live from
///     the `astrology_team` registry).
///   • MODERATION — pending user-reports queue.
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(dashboardAnalyticsProvider);
    final a = analyticsAsync.valueOrNull ?? const DashboardAnalytics();
    final loading =
        analyticsAsync.isLoading && analyticsAsync.valueOrNull == null;

    // ── Live CRM stats ──────────────────────────────────────────────────────
    final aggregates = ref.watch(adminAggregateCountsProvider).valueOrNull;
    final users =
        ref.watch(allUsersProvider).valueOrNull ?? const <UserModel>[];
    // Dummy (seeded) profiles are excluded from EVERY profile stat.
    final profiles = (ref.watch(allProfilesProvider).valueOrNull ??
            const <ProfileModel>[])
        .where((p) => !p.isDummy)
        .toList();
    final requests = ref.watch(allAstrologerRequestsProvider).valueOrNull ??
        const <AstrologerRequestModel>[];

    final now = DateTime.now();
    final activeCutoff = now.subtract(const Duration(days: 30));

    final totalUsers = aggregates?.totalUsers ?? users.length;
    final activeUsers = users
        .where((u) =>
            u.lastLoginAt != null && u.lastLoginAt!.isAfter(activeCutoff))
        .length;

    final totalProfiles = profiles.length;
    final maleProfiles =
        profiles.where((p) => p.gender.toLowerCase() == 'male').length;
    final femaleProfiles =
        profiles.where((p) => p.gender.toLowerCase() == 'female').length;
    final pendingProfiles =
        profiles.where((p) => p.status == 'pending').length;
    final approvedProfiles =
        profiles.where((p) => p.status == 'approved').length;
    final rejectedProfiles =
        profiles.where((p) => p.status == 'rejected').length;

    // Active = not completed / rejected / expired (terminal states).
    final activeAstroRequests = requests
        .where((r) =>
            r.status != AstrologerRequestStatus.completed &&
            r.status != AstrologerRequestStatus.rejected &&
            !r.isEffectivelyExpired)
        .length;

    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;
    final todayRegistrations =
        profiles.where((p) => isToday(p.createdAt)).length;
    final monthRegistrations = profiles
        .where((p) =>
            p.createdAt.year == now.year && p.createdAt.month == now.month)
        .length;

    // Live moderation queue count (dummies excluded, like every profile stat).
    final pendingApprovals =
        (ref.watch(pendingProfilesProvider).valueOrNull ??
                const <ProfileModel>[])
            .where((p) => !p.isDummy)
            .length;

    // ── Employee summary ────────────────────────────────────────────────────
    final team = ref.watch(allAstrologerTeamProvider).valueOrNull ??
        const <AstrologerTeamMember>[];
    final totalEmployees = team.length;
    final availableEmployees = team.where((m) => m.isAssignable).length;
    final unavailableEmployees = totalEmployees - availableEmployees;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(dashboardAnalyticsProvider);
        ref.invalidate(adminAggregateCountsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text('Dashboard',
              style: TextStyle(
                  fontSize: 24,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Matrimony CRM overview — live',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 16),

          // ── Live Overview ───────────────────────────────────────────────
          const _SectionTitle('Live Overview'),
          _HeroCard(
            icon: Icons.groups_outlined,
            value: '$totalUsers',
            label: 'Total Users',
            subLabel: 'Registered accounts',
          ),
          const SizedBox(height: 10),
          _statRow(
            _GridStat(
              icon: Icons.online_prediction,
              color: AppColors.success,
              value: '$activeUsers',
              label: 'Active Users',
              subLabel: 'Last 30 days',
            ),
            _GridStat(
              icon: Icons.badge_outlined,
              color: AppColors.primary,
              value: '$totalProfiles',
              label: 'Total Profiles',
            ),
          ),
          const SizedBox(height: 10),
          _statRow(
            _GridStat(
              icon: Icons.male,
              color: const Color(0xFF2F80ED),
              value: '$maleProfiles',
              label: 'Male Profiles',
            ),
            _GridStat(
              icon: Icons.female,
              color: const Color(0xFFD81B60),
              value: '$femaleProfiles',
              label: 'Female Profiles',
            ),
          ),
          const SizedBox(height: 10),
          _statRow(
            _GridStat(
              icon: Icons.hourglass_top_outlined,
              color: AppColors.warning,
              value: '$pendingProfiles',
              label: 'Pending Profiles',
            ),
            _GridStat(
              icon: Icons.verified_outlined,
              color: AppColors.success,
              value: '$approvedProfiles',
              label: 'Approved Profiles',
            ),
          ),
          const SizedBox(height: 10),
          _statRow(
            _GridStat(
              icon: Icons.cancel_outlined,
              color: AppColors.error,
              value: '$rejectedProfiles',
              label: 'Rejected Profiles',
            ),
            _GridStat(
              icon: Icons.workspace_premium_outlined,
              color: AppColors.gold,
              value: '0',
              label: 'Premium Members',
              subLabel: 'All features free',
            ),
          ),
          const SizedBox(height: 10),
          _statRow(
            _GridStat(
              icon: Icons.auto_awesome_outlined,
              color: const Color(0xFF7B1FA2),
              value: '$activeAstroRequests',
              label: 'Active Astrology Requests',
            ),
            _GridStat(
              icon: Icons.notifications_active_outlined,
              color: AppColors.info,
              value: aggregates == null
                  ? '—'
                  : '${aggregates.totalNotifications}',
              label: 'Notifications Sent',
            ),
          ),
          const SizedBox(height: 10),
          _statRow(
            _GridStat(
              icon: Icons.today_outlined,
              color: AppColors.success,
              value: '$todayRegistrations',
              label: "Today's Registrations",
            ),
            _GridStat(
              icon: Icons.calendar_month_outlined,
              color: AppColors.primary,
              value: '$monthRegistrations',
              label: "This Month's Registrations",
            ),
          ),
          const SizedBox(height: 24),

          // ── Quick Actions ───────────────────────────────────────────────
          const _SectionTitle('Quick Actions'),
          _ActionCard(
            icon: Icons.fact_check_outlined,
            color:
                pendingApprovals > 0 ? AppColors.warning : AppColors.primary,
            title: 'Pending Approvals',
            count: pendingApprovals,
            highlighted: pendingApprovals > 0,
            onTap: () => context.push('/admin/approvals'),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.history_outlined,
            color: AppColors.info,
            title: 'Activity Log',
            onTap: () => context.push('/admin/activity-log'),
          ),
          const SizedBox(height: 24),

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
          const SizedBox(height: 24),

          // ── Moderation ──────────────────────────────────────────────────
          const _SectionTitle('Moderation'),
          _ActionCard(
            icon: Icons.flag_outlined,
            color: AppColors.error,
            title: 'Pending Reports',
            count: ref.watch(pendingReportsCountProvider),
            onTap: () => context.go('/admin/reports'),
          ),
        ],
      ),
    );
  }

  /// Two equal-width grid stats side by side, stretched to the same height.
  static Widget _statRow(Widget left, Widget right) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        ),
      );
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

/// Full-width gradient hero counter (Total Users).
class _HeroCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String subLabel;
  const _HeroCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      height: 1.1)),
              Text(label,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 13.5)),
              Text(subLabel,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Premium grid stat card — icon bubble, big number, label, optional
/// sub-label, on a subtle tinted background.
class _GridStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? subLabel;
  const _GridStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  height: 1.1)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
          if (subLabel != null) ...[
            const SizedBox(height: 1),
            Text(subLabel!,
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ],
        ],
      ),
    );
  }
}

/// Tappable navigation card — icon, title, optional count pill and a chevron.
/// When [highlighted] the card takes on the [color]'s tint (used for the
/// amber Pending Approvals state).
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final int? count;
  final bool highlighted;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    this.count,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: highlighted
                ? color.withValues(alpha: 0.10)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: highlighted
                ? Border.all(color: color.withValues(alpha: 0.35))
                : null,
            boxShadow: highlighted
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8)
                  ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600)),
              ),
              if (count != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }
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
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
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
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
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
