import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/admin_activity.dart';
import '../../models/dashboard_analytics.dart';
import '../../providers/account_provider.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';
import 'admin_export.dart';

/// A clean, lightweight admin home: a few summary cards, quick actions and a
/// short recent-activity feed. All detailed analytics & charts live on the
/// Reports tab — the Dashboard intentionally stays uncluttered.
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(dashboardAnalyticsProvider);
    final pendingDeletions = ref.watch(pendingDeletionCountProvider);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(dashboardAnalyticsProvider);
        ref.invalidate(recentActivityProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Dashboard', style: AppTextStyles.heading2),
          const SizedBox(height: 16),
          if (pendingDeletions > 0) ...[
            _DeletionBanner(count: pendingDeletions),
            const SizedBox(height: 16),
          ],

          // ── Summary cards ─────────────────────────────────────────────────
          analyticsAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: LoadingState(message: 'Loading summary...')),
            error: (e, _) {
              debugPrint('[AdminDashboard] summary load failed: $e');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: ErrorStateView(
                  message: 'Connection Error — unable to load summary.',
                  onRetry: () => ref.invalidate(dashboardAnalyticsProvider),
                ),
              );
            },
            data: (a) => _summaryGrid(a, pendingDeletions),
          ),
          const SizedBox(height: 24),

          // ── Quick actions ─────────────────────────────────────────────────
          Text('Quick Actions', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          _quickActions(context),
          const SizedBox(height: 24),

          // ── Recent activity ───────────────────────────────────────────────
          Text('Recent Activity', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          _RecentActivity(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _summaryGrid(DashboardAnalytics a, int pendingDeletions) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        _SummaryCard('Total Users', '${a.totalUsers}', Icons.people, Colors.blue),
        _SummaryCard('Astrologers', '${a.totalAstrologers}', Icons.auto_awesome,
            AppColors.gold),
        _SummaryCard('Premium Users', '${a.premiumSubscribers}',
            Icons.workspace_premium, AppColors.premiumPlan),
        _SummaryCard("Today's Revenue", inr(a.revenueToday), Icons.today,
            AppColors.success),
        _SummaryCard('Monthly Revenue', inr(a.revenueMonth),
            Icons.calendar_month, AppColors.primary),
        _SummaryCard('Pending Verifications', '${a.pendingAstrologers}',
            Icons.hourglass_top, AppColors.warning),
        _SummaryCard('Deletion Requests', '$pendingDeletions',
            Icons.delete_outline, AppColors.error),
      ],
    );
  }

  Widget _quickActions(BuildContext context) {
    return Column(
      children: [
        _ActionTile('Manage Users', Icons.manage_accounts, Colors.blue,
            () => context.go('/admin/users')),
        _ActionTile('Manage Astrologers', Icons.auto_awesome, AppColors.gold,
            () => context.go('/admin/astrologers')),
        _ActionTile('View Revenue Reports', Icons.insights, AppColors.primary,
            () => context.go('/admin/analytics')),
        _ActionTile('Support Requests', Icons.support_agent, Colors.teal,
            () => context.go('/admin/support')),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent activity feed (max 5)
// ─────────────────────────────────────────────────────────────────────────────

class _RecentActivity extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentActivityProvider);
    return async.when(
      loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) {
        debugPrint('[AdminDashboard] recent activity failed: $e');
        return _card(Text('Activity unavailable right now.',
            style: TextStyle(color: Colors.grey[600], fontSize: 13)));
      },
      data: (items) {
        if (items.isEmpty) {
          return _card(Text('No recent activity yet.',
              style: TextStyle(color: Colors.grey[500], fontSize: 13)));
        }
        return _card(Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 18),
              _ActivityRow(item: items[i]),
            ],
          ],
        ));
      },
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: child,
      );
}

class _ActivityRow extends StatelessWidget {
  final AdminActivity item;
  const _ActivityRow({required this.item});

  (IconData, Color) get _style {
    switch (item.type) {
      case AdminActivityType.user:
        return (Icons.person_add_outlined, Colors.blue);
      case AdminActivityType.astrologer:
        return (Icons.auto_awesome, AppColors.gold);
      case AdminActivityType.subscription:
        return (Icons.workspace_premium_outlined, AppColors.premiumPlan);
      case AdminActivityType.deletion:
        return (Icons.delete_outline, AppColors.error);
    }
  }

  String get _ago {
    final d = DateTime.now().difference(item.time);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.subtitle,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        Text(_ago, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCard(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}

class _DeletionBanner extends StatelessWidget {
  final int count;
  const _DeletionBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/admin/deletion-requests'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Text('🔔', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count pending account deletion request${count == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
      ),
    );
  }
}
