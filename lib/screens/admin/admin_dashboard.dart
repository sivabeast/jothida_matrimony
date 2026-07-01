import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeline_tile/timeline_tile.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_activity.dart';
import '../../models/astrologer_account_model.dart';
import '../../models/dashboard_analytics.dart';
import '../../providers/admin_provider.dart';
import 'admin_astrologer_verification.dart' show PendingAstrologerCard;
import 'admin_export.dart' show inr;

/// Revenue-first admin Dashboard.
///
/// Leads with revenue (combined + user/astrologer split), charts (breakdown
/// doughnut + trend line), then the actionable widgets: pending astrologer
/// verification, top performers, subscription-expiry alerts and a recent
/// activity timeline. All numbers come from [dashboardAnalyticsProvider];
/// pending verifications stream from [allAstrologersProvider].
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(dashboardAnalyticsProvider);
    final a = analyticsAsync.valueOrNull ?? const DashboardAnalytics();
    final loading = analyticsAsync.isLoading && analyticsAsync.valueOrNull == null;

    final pending = (ref.watch(allAstrologersProvider).valueOrNull ??
            const <AstrologerAccount>[])
        .where((x) => x.status == VerificationStatus.pending)
        .toList()
      ..sort((x, y) =>
          (y.createdAt ?? DateTime(0)).compareTo(x.createdAt ?? DateTime(0)));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(dashboardAnalyticsProvider);
        ref.invalidate(recentActivityProvider);
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
          Text('Operations overview',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 16),

          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            ),

          // ── Revenue trend line ──────────────────────────────────────────
          const _SectionTitle('Subscription Revenue Trend'),
          _Card(child: _RevenueTrendChart(a: a)),
          const SizedBox(height: 22),

          // 7 ── Pending astrologer verification ──────────────────────────────
          Row(
            children: [
              const Expanded(child: _SectionTitle('Pending Verification')),
              if (pending.isNotEmpty)
                TextButton(
                  onPressed: () => context.go('/admin/astrologers'),
                  child: const Text('View All'),
                ),
            ],
          ),
          if (pending.isEmpty)
            const _EmptyHint(
                icon: Icons.verified_user_outlined,
                text: 'No astrologers awaiting verification')
          else
            for (final astro in pending.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PendingAstrologerCard(astrologer: astro, dense: true),
              ),
          const SizedBox(height: 12),

          // 6 ── Top performing astrologers ───────────────────────────────────
          const _SectionTitle('Top Performing Employees'),
          _TopPerformers(rows: a.topPerformers),
          const SizedBox(height: 22),

          // 7 ── Subscription expiry alerts ───────────────────────────────────
          const _SectionTitle('Subscription Expiry Alerts'),
          Row(
            children: [
              Expanded(
                  child: _ExpiryTile('Users Today', a.usersExpiringToday,
                      Icons.person_off_outlined, AppColors.warning)),
              const SizedBox(width: 10),
              Expanded(
                  child: _ExpiryTile('Astrologers Today',
                      a.astrologersExpiringToday, Icons.event_busy,
                      const Color(0xFFEB5757))),
              const SizedBox(width: 10),
              Expanded(
                  child: _ExpiryTile('Next 7 Days', a.expiringNext7Days,
                      Icons.hourglass_bottom, const Color(0xFF2F80ED))),
            ],
          ),
          const SizedBox(height: 22),

          // 8 ── Recent activity timeline ─────────────────────────────────────
          const _SectionTitle('Recent Activities'),
          const _RecentActivities(),
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

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: child,
      );
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.grey[400], size: 30),
            const SizedBox(height: 6),
            Text(text, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      );
}

// ── Revenue card (icon · label · value) ──────────────────────────────────────

// ── Revenue summary card (today / month / total) ─────────────────────────────

// ── Settlement entry card (tap → Settlements & Payouts) ──────────────────────

// ── Settlement summary card (earned / settled for a period) ──────────────────

// ── Revenue breakdown doughnut ───────────────────────────────────────────────

// ── Revenue trend line (Daily / Monthly toggle) ──────────────────────────────
class _RevenueTrendChart extends StatefulWidget {
  final DashboardAnalytics a;
  const _RevenueTrendChart({required this.a});
  @override
  State<_RevenueTrendChart> createState() => _RevenueTrendChartState();
}

class _RevenueTrendChartState extends State<_RevenueTrendChart> {
  bool _monthly = false;

  String _short(num v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final points =
        _monthly ? widget.a.revenueMonthly : widget.a.revenueDaily;
    final maxY = points.fold<double>(
        0, (m, p) => p.amount.toDouble() > m ? p.amount.toDouble() : m);
    final hasData = maxY > 0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ChoiceChip(
              label: const Text('Daily'),
              selected: !_monthly,
              showCheckmark: false,
              onSelected: (_) => setState(() => _monthly = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Monthly'),
              selected: _monthly,
              showCheckmark: false,
              onSelected: (_) => setState(() => _monthly = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: !hasData
              ? const Center(
                  child: Text('No revenue in this period',
                      style: TextStyle(color: Colors.grey)))
              : LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY * 1.2,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) =>
                          FlLine(color: Colors.grey[200]!, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 38,
                          getTitlesWidget: (value, meta) {
                            if (value == meta.max) return const SizedBox.shrink();
                            return Text(_short(value),
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[500]));
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= points.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(points[i].label,
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey[600])),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < points.length; i++)
                            FlSpot(i.toDouble(), points[i].amount.toDouble()),
                        ],
                        isCurved: true,
                        color: AppColors.primary,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppColors.primary.withOpacity(0.12),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Top performers leaderboard ───────────────────────────────────────────────
class _TopPerformers extends StatelessWidget {
  final List<TopAstrologerRow> rows;
  const _TopPerformers({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyHint(
          icon: Icons.emoji_events_outlined,
          text: 'No completed reports yet');
    }
    return _Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 18, color: Colors.grey[200]),
            _row(i + 1, rows[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(int rank, TopAstrologerRow r) {
    final rankColor = switch (rank) {
      1 => const Color(0xFFFFB300),
      2 => const Color(0xFF90A4AE),
      3 => const Color(0xFFA1674A),
      _ => Colors.grey,
    };
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: rankColor.withOpacity(0.15), shape: BoxShape.circle),
          child: Text('$rank',
              style: TextStyle(
                  color: rankColor, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primary.withOpacity(0.12),
          backgroundImage:
              r.photoUrl.isNotEmpty ? NetworkImage(r.photoUrl) : null,
          child: r.photoUrl.isEmpty
              ? Text(r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text('${r.completedReports} reports · ${inr(r.revenueGenerated)}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Row(
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 16),
            const SizedBox(width: 2),
            Text(r.rating.toStringAsFixed(1),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
          ],
        ),
      ],
    );
  }
}

// ── Expiry alert tile ────────────────────────────────────────────────────────
class _ExpiryTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _ExpiryTile(this.label, this.value, this.icon, this.color);

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
          Text('$value',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, height: 1.1)),
          const SizedBox(height: 1),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

// ── Recent activities timeline ───────────────────────────────────────────────
class _RecentActivities extends ConsumerWidget {
  const _RecentActivities();

  ({IconData icon, Color color}) _style(AdminActivityType t) => switch (t) {
        AdminActivityType.user => (
            icon: Icons.person_add_alt_1,
            color: const Color(0xFF2F80ED)
          ),
        AdminActivityType.astrologer => (
            icon: Icons.auto_awesome,
            color: const Color(0xFF7C5CFC)
          ),
        AdminActivityType.subscription => (
            icon: Icons.payments,
            color: AppColors.success
          ),
        AdminActivityType.deletion => (
            icon: Icons.delete_outline,
            color: AppColors.error
          ),
        AdminActivityType.verification => (
            icon: Icons.verified,
            color: const Color(0xFF00A389)
          ),
        AdminActivityType.horoscope => (
            icon: Icons.menu_book,
            color: AppColors.gold
          ),
      };

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${(d.inDays / 30).floor()}mo ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentActivityProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => const _EmptyHint(
          icon: Icons.history, text: 'Could not load recent activity'),
      data: (items) {
        if (items.isEmpty) {
          return const _EmptyHint(
              icon: Icons.history, text: 'No recent activity');
        }
        return _Card(
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _tile(items[i], isFirst: i == 0, isLast: i == items.length - 1),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(AdminActivity a, {required bool isFirst, required bool isLast}) {
    final s = _style(a.type);
    return TimelineTile(
      alignment: TimelineAlign.start,
      isFirst: isFirst,
      isLast: isLast,
      indicatorStyle: IndicatorStyle(
        width: 30,
        color: s.color,
        iconStyle: IconStyle(iconData: s.icon, color: Colors.white, fontSize: 16),
      ),
      beforeLineStyle: LineStyle(color: Colors.grey[200]!, thickness: 2),
      afterLineStyle: LineStyle(color: Colors.grey[200]!, thickness: 2),
      endChild: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.subtitle,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 1),
            Text('${a.title} · ${_ago(a.time)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
