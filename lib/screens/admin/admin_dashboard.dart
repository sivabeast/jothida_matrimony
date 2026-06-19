import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dashboard_analytics.dart';
import '../../providers/admin_provider.dart';
import 'admin_export.dart' show inr;

/// Mobile-first admin Dashboard.
///
/// Summary metrics grouped into sections — Users · Subscriptions · Astrologers ·
/// Engagement · Revenue — followed by Quick Actions. Counts come from
/// [adminStatsProvider] (extended breakdowns) and revenue / verification numbers
/// from [dashboardAnalyticsProvider]. Both are read defensively so the page
/// always renders whatever data is available.
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);
    final analyticsAsync = ref.watch(dashboardAnalyticsProvider);
    final stats = statsAsync.valueOrNull;
    final a = analyticsAsync.valueOrNull ?? const DashboardAnalytics();
    final loading = stats == null && analyticsAsync.isLoading;

    int n(String k) => (stats?[k] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(adminStatsProvider);
        ref.invalidate(dashboardAnalyticsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text('Dashboard',
              style: TextStyle(
                  fontSize: 24,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Welcome back, Admin!',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 18),

          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            ),

          // ── Users ───────────────────────────────────────────────────────
          _Section(title: 'Users', children: [
            _StatTile('Total Users', '${n('totalUsers')}', Icons.groups,
                AppColors.primary),
            _StatTile('Male Users', '${n('maleUsers')}', Icons.male,
                const Color(0xFF2F80ED)),
            _StatTile('Female Users', '${n('femaleUsers')}', Icons.female,
                const Color(0xFFEB5757)),
            _StatTile('Active Users', '${n('activeUsers')}',
                Icons.verified_user, AppColors.success),
          ]),

          // ── Subscriptions ───────────────────────────────────────────────
          _Section(title: 'Subscriptions', columns: 3, children: [
            _StatTile('Basic Plan', '${n('basicPlanUsers')}',
                Icons.card_membership, AppColors.basicPlan),
            _StatTile('Medium Plan', '${n('mediumPlanUsers')}',
                Icons.workspace_premium_outlined, AppColors.warning),
            _StatTile('Premium', '${n('premiumPlanUsers')}',
                Icons.workspace_premium, AppColors.premiumPlan),
          ]),

          // ── Astrologers ─────────────────────────────────────────────────
          _Section(title: 'Astrologers', columns: 3, children: [
            _StatTile('Total', '${a.totalAstrologers}', Icons.auto_awesome,
                const Color(0xFF7C5CFC)),
            _StatTile('Verified', '${a.verifiedAstrologers}', Icons.verified,
                AppColors.success),
            _StatTile('Pending', '${a.pendingAstrologers}',
                Icons.hourglass_top, AppColors.warning),
          ]),

          // ── Engagement ──────────────────────────────────────────────────
          _Section(title: 'Engagement', children: [
            _StatTile('Total Interests', '${n('totalInterests')}',
                Icons.favorite, const Color(0xFF9B51E0)),
            _StatTile('Total Matches', '${n('totalMatches')}',
                Icons.favorite_border, AppColors.primary),
          ]),

          // ── Revenue ─────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10, top: 2),
            child: Text('Revenue',
                style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
          ),
          Row(
            children: [
              Expanded(
                  child: _RevenueCard("Today's", inr(a.revenueToday),
                      Icons.today, AppColors.success)),
              const SizedBox(width: 10),
              Expanded(
                  child: _RevenueCard('Monthly', inr(a.revenueMonth),
                      Icons.calendar_month, const Color(0xFF2F80ED))),
            ],
          ),
          const SizedBox(height: 10),
          _RevenueCard('Total Revenue', inr(a.revenueTotal),
              Icons.account_balance_wallet, AppColors.premiumPlan,
              wide: true),
          const SizedBox(height: 24),

          // ── Quick actions ───────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text('Quick Actions',
                style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.4,
            children: [
              _QuickAction('Add Astrologer', Icons.person_add_alt_1,
                  const Color(0xFF7C5CFC), () => context.go('/admin/astrologers')),
              _QuickAction('Send Notification', Icons.campaign, AppColors.gold,
                  () => context.go('/admin/notifications')),
              _QuickAction('Manage Users', Icons.manage_accounts,
                  const Color(0xFF2F80ED), () => context.go('/admin/users')),
              _QuickAction('View Reports', Icons.insights, AppColors.primary,
                  () => context.go('/admin/analytics')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section: title + responsive grid of stat tiles ───────────────────────────
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final int columns;
  const _Section(
      {required this.title, required this.children, this.columns = 2});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10, top: 2),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 3 ? 0.90 : 1.45,
          children: children,
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

// ── Stat tile (icon chip · value · label) ────────────────────────────────────
class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatTile(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.bold, height: 1.1)),
          const SizedBox(height: 1),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

// ── Revenue card ─────────────────────────────────────────────────────────────
class _RevenueCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool wide;
  const _RevenueCard(this.label, this.value, this.icon, this.color,
      {this.wide = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: wide ? 22 : 17,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick action tile ────────────────────────────────────────────────────────
class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
