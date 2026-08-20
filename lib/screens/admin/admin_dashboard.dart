import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/dashboard_analytics.dart';
import '../../models/profile_model.dart';
import '../../models/report_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/report_provider.dart';
import '../../widgets/common/data_states.dart';
import 'admin_export.dart' show inr;

/// The admin Dashboard — business analytics only (user counters live on the
/// All Users page; every admin area is reachable from the navigation drawer):
///
///   • QUICK ACTIONS — Pending Verification + Activity Log, shown only while
///     the verification queue is non-empty (operationally important).
///   • REVENUE — Today · This Week · This Month · Total
///     (from [dashboardAnalyticsProvider]) + the 7-day Revenue Trend chart.
///   • PAYMENT ANALYTICS — paid orders, average order value, orders this month
///     (live from the paid `astrologer_requests` stream).
///   • RECENT PAYMENTS / USER REPORTS / ACTIVITIES — last 5 of each with a
///     "View All" into the full page.
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(dashboardAnalyticsProvider);
    final a = analyticsAsync.valueOrNull ?? const DashboardAnalytics();
    final analyticsLoading =
        analyticsAsync.isLoading && analyticsAsync.valueOrNull == null;
    final analyticsFailed =
        analyticsAsync.hasError && analyticsAsync.valueOrNull == null;

    // ── Payment analytics (live paid-transactions stream) ───────────────────
    final paid = ref.watch(paidAstrologerRequestsProvider).valueOrNull ??
        const <AstrologerRequestModel>[];
    final paidCount = paid.length;
    final paidSum = paid.fold<int>(0, (s, r) => s + r.amount);
    final avgOrder = paidCount == 0 ? 0 : (paidSum / paidCount).round();
    final now = DateTime.now();
    final monthOrders = paid.where((r) {
      final d = r.paidAt ?? r.createdAt;
      return d.year == now.year && d.month == now.month;
    }).length;

    // ── Recent moderation + audit feeds (newest first from their providers) ─
    final recentReports =
        (ref.watch(allReportsProvider).valueOrNull ?? const <ReportModel>[])
            .take(5)
            .toList();
    final recentLogs = (ref.watch(adminLogsProvider).valueOrNull ??
            const <Map<String, dynamic>>[])
        .take(5)
        .toList();

    // Live verification queue count (dummies excluded, like every profile stat).
    final pendingApprovals =
        (ref.watch(pendingProfilesProvider).valueOrNull ??
                const <ProfileModel>[])
            .where((p) => !p.isDummy)
            .length;

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
          Text('Business overview — live',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 16),

          // ── Quick Actions (only while approvals are waiting) ────────────
          if (pendingApprovals > 0) ...[
            const _SectionTitle('Quick Actions'),
            _ActionCard(
              icon: Icons.fact_check_outlined,
              color: AppColors.warning,
              title: 'Pending Verification',
              count: pendingApprovals,
              highlighted: true,
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
          ],

          // ── Revenue ─────────────────────────────────────────────────────
          const _SectionTitle('Revenue'),
          if (analyticsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: LoadingState(message: 'Crunching the numbers...'),
            )
          else if (analyticsFailed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ErrorStateView(
                message: 'Connection Error — unable to load analytics.',
                onRetry: () => ref.invalidate(dashboardAnalyticsProvider),
              ),
            )
          else ...[
            _statRow(
              _RevenueStat(
                icon: Icons.today_outlined,
                color: AppColors.success,
                label: 'Today',
                value: inr(a.revenueToday),
              ),
              _RevenueStat(
                icon: Icons.date_range_outlined,
                color: AppColors.info,
                label: 'This Week',
                value: inr(a.revenueWeek),
              ),
            ),
            const SizedBox(height: 10),
            _statRow(
              _RevenueStat(
                icon: Icons.calendar_month_outlined,
                color: AppColors.primary,
                label: 'This Month',
                value: inr(a.revenueMonth),
              ),
              _RevenueStat(
                icon: Icons.account_balance_outlined,
                color: AppColors.gold,
                label: 'Total Revenue',
                value: inr(a.revenueTotal),
              ),
            ),
            const SizedBox(height: 14),
            _RevenueTrendCard(points: a.revenueDaily),
          ],
          const SizedBox(height: 24),

          // ── Payment analytics ───────────────────────────────────────────
          const _SectionTitle('Payment Analytics'),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.primary,
                  label: 'Paid\nOrders',
                  value: '$paidCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  icon: Icons.currency_rupee,
                  color: AppColors.gold,
                  label: 'Avg Order\nValue',
                  value: inr(avgOrder),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  icon: Icons.calendar_month_outlined,
                  color: AppColors.success,
                  label: 'Orders\nThis Month',
                  value: '$monthOrders',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Recent Payments ─────────────────────────────────────────────
          _RecentCard(
            title: 'Recent Payments',
            onViewAll: () => context.push('/admin/payments'),
            emptyText: 'No payments yet.',
            rows: [
              for (final r in paid.take(5))
                _RecentRow(
                  icon: Icons.payments_outlined,
                  color: AppColors.success,
                  title: r.userName,
                  subtitle: _fmtDate(r.paidAt ?? r.createdAt),
                  trailing: Text(inr(r.amount),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold)),
                  chip: _StatusChip.forRequest(r),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Recent User Reports ─────────────────────────────────────────
          _RecentCard(
            title: 'Recent User Reports',
            onViewAll: () => context.push('/admin/reports'),
            emptyText: 'No user reports yet.',
            rows: [
              for (final r in recentReports)
                _RecentRow(
                  icon: Icons.flag_outlined,
                  color: AppColors.error,
                  title: r.reporterName.isEmpty ? 'Member' : r.reporterName,
                  subtitle: r.reason,
                  trailing: Text(_fmtDate(r.createdAt),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500])),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Recent Activities ───────────────────────────────────────────
          _RecentCard(
            title: 'Recent Activities',
            onViewAll: () => context.push('/admin/activity-log'),
            emptyText: 'No admin activity recorded yet.',
            rows: [
              for (final log in recentLogs)
                _RecentRow(
                  icon: Icons.history_outlined,
                  color: AppColors.info,
                  title: _actionLabel((log['action'] ?? '').toString()),
                  subtitle: (log['details'] ?? '').toString().isNotEmpty
                      ? (log['details'] ?? '').toString()
                      : (log['targetUid'] ?? '').toString(),
                  trailing: Text(_fmtLogDate(log['createdAt']),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500])),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Two equal-width stats side by side, stretched to the same height.
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

  /// Humanises an `admin_logs` action key ('profile_approved' →
  /// 'Profile Verified' — the stored key keeps the legacy 'approved' wording).
  static String _actionLabel(String action) {
    if (action.isEmpty) return 'Action';
    if (action == 'profile_approved') return 'Profile Verified';
    return action
        .split('_')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // admin_logs rows are raw maps; createdAt is a Firestore Timestamp.
  static String _fmtLogDate(dynamic ts) =>
      ts is Timestamp ? _fmtDate(ts.toDate()) : '';
}

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// '2 Aug · 4:05 PM' (year appended when not the current year).
String _fmtDate(DateTime d) {
  final now = DateTime.now();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  final day = '${d.day} ${_kMonths[d.month - 1]}'
      '${d.year == now.year ? '' : ' ${d.year}'}';
  return '$day · $h:${d.minute.toString().padLeft(2, '0')} $ampm';
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

/// Compact revenue stat card — icon bubble, label, big INR value.
class _RevenueStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _RevenueStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 19,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  height: 1.1)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
        ],
      ),
    );
  }
}

/// 7-day daily revenue bar chart (same fl_chart idiom as the Revenue &
/// Analytics page).
class _RevenueTrendCard extends StatelessWidget {
  final List<RevenuePoint> points;
  const _RevenueTrendCard({required this.points});

  @override
  Widget build(BuildContext context) {
    final maxVal = points.fold<int>(0, (m, p) => p.amount > m ? p.amount : m);
    final maxY = (maxVal <= 0 ? 100 : maxVal * 1.25).toDouble();
    final weekTotal = points.fold<int>(0, (s, p) => s + p.amount);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Revenue Trend',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              Text(inr(weekTotal),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 13)),
            ],
          ),
          Text('Last 7 days',
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: maxVal <= 0
                ? Center(
                    child: Text('No revenue in the last 7 days.',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 12.5)))
                : BarChart(
                    BarChartData(
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceAround,
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= points.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(points[i].label,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600])),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < points.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: points[i].amount.toDouble(),
                              color: AppColors.primary,
                              width: 16,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5)),
                            ),
                          ]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Tappable navigation card — icon, title, optional count pill and a chevron.
/// When [highlighted] the card takes on the [color]'s tint (used for the
/// amber Pending Verification state).
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

/// Compact analytics tile (icon · value · two-line label).
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 17,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  height: 1.1)),
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

/// White card listing the last few items of a feed with a "View All" header.
class _RecentCard extends StatelessWidget {
  final String title;
  final VoidCallback onViewAll;
  final String emptyText;
  final List<Widget> rows;
  const _RecentCard({
    required this.title,
    required this.onViewAll,
    required this.emptyText,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('View All',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(emptyText,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12.5)),
            )
          else
            ...rows,
        ],
      ),
    );
  }
}

/// One row inside a [_RecentCard]: icon bubble · title/subtitle · trailing.
class _RecentRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget? chip;
  const _RecentRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.chip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              trailing,
              if (chip != null) ...[const SizedBox(height: 3), chip!],
            ],
          ),
        ],
      ),
    );
  }
}

/// Small status pill (used for payment rows).
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  /// Chip for a request's display bucket (Pending / Accepted / In Progress /
  /// Completed / Rejected / Expired).
  factory _StatusChip.forRequest(AstrologerRequestModel r) {
    switch (r.displayBucket) {
      case 'completed':
        return const _StatusChip(label: 'Completed', color: AppColors.success);
      case 'inProgress':
        return const _StatusChip(label: 'In Progress', color: AppColors.info);
      case 'accepted':
        return const _StatusChip(label: 'Accepted', color: AppColors.info);
      case 'rejected':
        return const _StatusChip(label: 'Rejected', color: AppColors.error);
      case 'expired':
        return _StatusChip(label: 'Expired', color: Colors.grey[600]!);
      default:
        return const _StatusChip(label: 'Pending', color: AppColors.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
