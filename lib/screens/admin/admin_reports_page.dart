import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_analytics.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';
import 'admin_export.dart';

/// The admin "Reports" tab — all business analytics and charts live here so the
/// Dashboard can stay light. Revenue, subscriptions, user growth, astrologer
/// and marriage analytics, plus CSV exports.
class AdminReportsPage extends ConsumerWidget {
  const AdminReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(dashboardAnalyticsProvider);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(dashboardAnalyticsProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Reports & Analytics', style: AppTextStyles.heading2),
          const SizedBox(height: 16),
          analyticsAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: LoadingState(message: 'Crunching the numbers...')),
            error: (e, _) {
              debugPrint('[AdminReports] analytics load failed: $e');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: ErrorStateView(
                  message: 'Connection Error — unable to load analytics.',
                  onRetry: () => ref.invalidate(dashboardAnalyticsProvider),
                ),
              );
            },
            data: (a) => _content(context, a),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, DashboardAnalytics a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Revenue ───────────────────────────────────────────────────────
        Row(children: [
          Expanded(child: _SectionTitle('Revenue')),
          _ExportChip(onTap: () => exportRevenueCsv(context, a)),
        ]),
        const SizedBox(height: 12),
        _grid([
          _MetricCard("Today", inr(a.revenueToday), Icons.today, AppColors.success),
          _MetricCard('This Week', inr(a.revenueWeek), Icons.date_range, AppColors.info),
          _MetricCard('This Month', inr(a.revenueMonth), Icons.calendar_month, AppColors.primary),
          _MetricCard('This Year', inr(a.revenueYear), Icons.calendar_today, AppColors.gold),
        ]),
        const SizedBox(height: 14),
        _RevenueChartCard(analytics: a),
        const SizedBox(height: 24),

        // (The Subscriptions section was removed with the subscription system.)

        // ── User growth ───────────────────────────────────────────────────
        Row(children: [
          Expanded(child: _SectionTitle('User Growth')),
          _ExportChip(onTap: () => exportUsersCsv(context, a)),
        ]),
        const SizedBox(height: 12),
        _statTiles([
          ('Total Users', '${a.totalUsers}', AppColors.primary),
          ('New Today', '${a.newUsersToday}', AppColors.success),
          ('New This Week', '${a.newUsersWeek}', AppColors.info),
          ('New This Month', '${a.newUsersMonth}', Colors.teal),
          ('Daily Active', '${a.dailyActiveUsers}', Colors.blue),
          ('Monthly Active', '${a.monthlyActiveUsers}', Colors.indigo),
        ]),
        const SizedBox(height: 24),

        // ── Astrologers ───────────────────────────────────────────────────
        Row(children: [
          Expanded(child: _SectionTitle('Astrologers')),
          _ExportChip(onTap: () => exportAstrologersCsv(context, a)),
        ]),
        const SizedBox(height: 12),
        _statTiles([
          ('Total', '${a.totalAstrologers}', AppColors.gold),
          ('Pending', '${a.pendingAstrologers}', AppColors.warning),
          ('Verified', '${a.verifiedAstrologers}', AppColors.success),
        ]),
        const SizedBox(height: 12),
        _leaderboard('⭐ Top Rated', a.topRatedAstrologers,
            (r) => '${r.rating.toStringAsFixed(1)} ★ (${r.reviewCount})'),
        const SizedBox(height: 10),
        _leaderboard('🔮 Most Consulted', a.mostConsultedAstrologers,
            (r) => '${r.consultations} consults'),
        const SizedBox(height: 24),

        // ── Consultations ─────────────────────────────────────────────────
        _SectionTitle('Consultations'),
        const SizedBox(height: 12),
        _statTiles([
          ('Today', '${a.consultationsToday}', AppColors.info),
          ('This Week', '${a.consultationsWeek}', AppColors.primary),
          ('This Month', '${a.consultationsMonth}', Colors.teal),
          ('Completed', '${a.consultationsCompleted}', AppColors.success),
          ('Cancelled', '${a.consultationsCancelled}', AppColors.error),
        ]),
        const SizedBox(height: 24),

        // ── Marriage success ──────────────────────────────────────────────
        _SectionTitle('Marriage Success'),
        const SizedBox(height: 12),
        _grid([
          _MetricCard('Married', '${a.marriedUsers}', Icons.celebration, Colors.pink),
          _MetricCard('Matches', '${a.successfulMatches}', Icons.favorite, AppColors.primary),
          _MetricCard('Success Rate', '${a.marriageSuccessRate.toStringAsFixed(1)}%',
              Icons.trending_up, AppColors.success),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _grid(List<Widget> children) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.7,
        children: children,
      );

  Widget _statTiles(List<(String, String, Color)> rows) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final r in rows) _MiniStat(label: r.$1, value: r.$2, color: r.$3)],
      );

  Widget _leaderboard(String title, List<AstrologerStatRow> rows,
      String Function(AstrologerStatRow) trailing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text('No data yet.', style: TextStyle(color: Colors.grey[500], fontSize: 12.5))
          else
            ...rows.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text('${e.key + 1}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.value.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text(trailing(e.value),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600)),
                  ]),
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Revenue chart (Daily / Weekly / Monthly / Yearly)
// ─────────────────────────────────────────────────────────────────────────────

class _RevenueChartCard extends StatefulWidget {
  final DashboardAnalytics analytics;
  const _RevenueChartCard({required this.analytics});

  @override
  State<_RevenueChartCard> createState() => _RevenueChartCardState();
}

class _RevenueChartCardState extends State<_RevenueChartCard> {
  int _range = 0;

  List<RevenuePoint> get _points {
    switch (_range) {
      case 1:
        return widget.analytics.revenueWeekly;
      case 2:
        return widget.analytics.revenueMonthly;
      case 3:
        return widget.analytics.revenueYearly;
      default:
        return widget.analytics.revenueDaily;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    final maxVal = pts.fold<int>(0, (m, p) => p.amount > m ? p.amount : m);
    final maxY = (maxVal <= 0 ? 100 : maxVal * 1.25).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Revenue Trend',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(inr(pts.fold<int>(0, (s, p) => s + p.amount)),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          _rangeToggle(),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            child: maxVal <= 0
                ? Center(
                    child: Text('No revenue in this period.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12.5)))
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
                              if (i < 0 || i >= pts.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(pts[i].label,
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.grey[600])),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < pts.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: pts[i].amount.toDouble(),
                              color: AppColors.primary,
                              width: 16,
                              borderRadius:
                                  const BorderRadius.vertical(top: Radius.circular(5)),
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

  Widget _rangeToggle() {
    const labels = ['Daily', 'Weekly', 'Monthly', 'Yearly'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[i], style: const TextStyle(fontSize: 12)),
              selected: _range == i,
              showCheckmark: false,
              selectedColor: AppColors.primary.withOpacity(0.14),
              backgroundColor: Colors.grey[100],
              labelStyle: TextStyle(
                color: _range == i ? AppColors.primary : Colors.black87,
                fontWeight: _range == i ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide(
                  color: _range == i ? AppColors.primary : Colors.grey[300]!),
              onSelected: (_) => setState(() => _range = i),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: AppTextStyles.heading3);
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricCard(this.title, this.value, this.icon, this.color);

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
                color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ExportChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ExportChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.file_download_outlined, size: 16),
      label: const Text('Export'),
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    );
  }
}
