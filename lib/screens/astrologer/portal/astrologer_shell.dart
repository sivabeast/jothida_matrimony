import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../models/astrologer_team_member.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/astrology_team_provider.dart';
import '../../../providers/astrology_team_stats_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/service_providers.dart';
import '../../../widgets/common/async_state_view.dart';
import '../../../widgets/common/payroll_history_tile.dart';

/// The astrologer portal shell (spec §3/§4). A bottom navigation with five
/// destinations — Dashboard · Pending · Completed · Work Report · Profile —
/// each a separate page (no top tabs). Every page handles loading / error /
/// empty / data explicitly (via [AsyncStateView]) so no tab can ever sit on
/// an endless spinner.
class AstrologerShell extends ConsumerStatefulWidget {
  const AstrologerShell({super.key});

  @override
  ConsumerState<AstrologerShell> createState() => _AstrologerShellState();
}

class _AstrologerShellState extends ConsumerState<AstrologerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // Badge count only — the pages themselves watch the provider with full
    // loading/error handling.
    final requests =
        ref.watch(myAssignedRequestsProvider).valueOrNull ?? const [];
    final pendingCount = requests
        .where((r) => r.status != AstrologerRequestStatus.completed)
        .length;

    final titles = [
      'Dashboard',
      'Pending',
      'Completed',
      'Work Report',
      'Profile'
    ];

    // Employee bell badge: employee-audience broadcasts + own notifications.
    final unread = ref.watch(unreadEmployeeAnnouncementsCountProvider) +
        ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(titles[_index]),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/astrologer-notifications'),
            icon: unread == 0
                ? const Icon(Icons.notifications_outlined)
                : Badge(
                    label: Text('$unread'),
                    child: const Icon(Icons.notifications_outlined)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _DashboardPage(onNavigate: (i) => setState(() => _index = i)),
          const _RequestsTab(completed: false),
          const _RequestsTab(completed: true),
          const _WorkReportPage(),
          const _ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard'),
          NavigationDestination(
              icon: _badge(Icons.assignment_outlined, pendingCount),
              label: 'Pending'),
          const NavigationDestination(
              icon: Icon(Icons.check_circle_outline), label: 'Completed'),
          const NavigationDestination(
              icon: Icon(Icons.insights_outlined), label: 'Work Report'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, int count) => count == 0
      ? Icon(icon)
      : Badge(label: Text('$count'), child: Icon(icon));
}

// ── Dashboard (home) ─────────────────────────────────────────────────────────

/// The employee's landing page — a QUICK OVERVIEW only (per spec): greeting +
/// availability, today's assigned / completed / pending, a weekly summary,
/// quick actions and the most recent assigned reports. All detailed analytics
/// live on the Work Report page.
class _DashboardPage extends ConsumerWidget {
  /// Switches the shell's bottom-nav page (1 Pending · 2 Completed · 3 Work
  /// Report) — used by "See all" and the Quick Actions.
  final ValueChanged<int> onNavigate;
  const _DashboardPage({required this.onNavigate});

  static String _today() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final n = DateTime.now();
    return '${days[n.weekday - 1]}, ${n.day} ${months[n.month - 1]} ${n.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(myAstrologerTeamMemberProvider);
    return AsyncStateView<AstrologerTeamMember?>(
      value: memberAsync,
      errorTitle: 'Couldn\'t load your dashboard',
      onRetry: () {
        ref.invalidate(myAstrologerTeamMemberProvider);
        ref.invalidate(myAssignedRequestsProvider);
      },
      builder: (m) {
        if (m == null) {
          return const EmptyStateView(
            icon: Icons.badge_outlined,
            title: 'Your employee account was not found',
            subtitle:
                'Ask the admin to register your Gmail in the astrology team.',
          );
        }
        final s = ref.watch(myAstrologerStatsProvider);
        final requests =
            ref.watch(myAssignedRequestsProvider).valueOrNull ?? const [];
        // Most recently ASSIGNED reports, any status (per spec).
        final recentAssigned = [...requests]..sort((a, b) =>
            (b.assignedAt ?? b.createdAt).compareTo(a.assignedAt ?? a.createdAt));

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(myAstrologerTeamMemberProvider);
            ref.invalidate(myAssignedRequestsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // ── Greeting + availability ────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white24,
                      backgroundImage: m.photoUrl.isNotEmpty
                          ? NetworkImage(m.photoUrl)
                          : null,
                      child: m.photoUrl.isEmpty
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.displayName.isEmpty ? m.email : m.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(_today(),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              size: 9,
                              color: m.available
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent),
                          const SizedBox(width: 5),
                          Text(m.available ? 'Available' : 'Unavailable',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Today's overview ───────────────────────────────────────
              const _SectionTitle('Today\'s Overview'),
              if (s != null)
                Row(
                  children: [
                    _todayStat('Assigned', s.todayAssigned,
                        Icons.assignment_outlined, AppColors.info),
                    const SizedBox(width: 10),
                    _todayStat('Completed', s.todayCompleted,
                        Icons.verified_outlined, AppColors.success),
                    const SizedBox(width: 10),
                    _todayStat('Pending', s.todayPending,
                        Icons.pending_actions_outlined, AppColors.warning),
                  ],
                ),
              const SizedBox(height: 16),

              // ── Weekly summary ─────────────────────────────────────────
              const _SectionTitle('Weekly Summary'),
              if (s != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _wkStat('Assigned', s.thisWeek.assigned),
                          _wkStat('Completed', s.thisWeek.completed),
                          _wkStat('Pending', s.thisWeek.pending),
                          _wkStat('Rate', s.thisWeek.completionRate,
                              suffix: '%'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: s.thisWeek.completionRate / 100,
                          minHeight: 7,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation(
                              AppColors.success),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${s.thisWeek.completed} of ${s.thisWeek.assigned} '
                        'reports completed this week',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // ── Quick actions ──────────────────────────────────────────
              const _SectionTitle('Quick Actions'),
              Row(
                children: [
                  _action(context, Icons.assignment_outlined,
                      'Pending Reports', AppColors.warning,
                      () => onNavigate(1)),
                  const SizedBox(width: 10),
                  _action(context, Icons.check_circle_outline,
                      'Completed Reports', AppColors.success,
                      () => onNavigate(2)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _action(context, Icons.insights_outlined, 'Work Report',
                      AppColors.info, () => onNavigate(3)),
                  const SizedBox(width: 10),
                  _action(context, Icons.notifications_outlined,
                      'Notifications', AppColors.primary,
                      () => context.push('/astrologer-notifications')),
                ],
              ),
              const SizedBox(height: 16),

              // ── Recent assigned reports ────────────────────────────────
              Row(
                children: [
                  const Expanded(child: _SectionTitle('Recent Assigned Reports')),
                  TextButton(
                      onPressed: () => onNavigate(1),
                      child: const Text('See all')),
                ],
              ),
              if (recentAssigned.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: EmptyStateView(
                    icon: Icons.inbox_outlined,
                    title: 'No reports assigned yet',
                    subtitle:
                        'Newly assigned horoscope reports will appear here.',
                  ),
                )
              else
                for (final r in recentAssigned.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RequestCard(
                        request: r,
                        trailing:
                            r.status == AstrologerRequestStatus.completed
                                ? 'View'
                                : 'Open'),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _todayStat(String label, int value, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(height: 8),
              Text('$value',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              Text(label,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
            ],
          ),
        ),
      );

  Widget _wkStat(String label, int value, {String suffix = ''}) => Column(
        children: [
          Text('$value$suffix',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      );

  Widget _action(BuildContext context, IconData icon, String label,
          Color color, VoidCallback onTap) =>
      Expanded(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Small bold section heading used across the portal pages.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      );
}

// ── Requests tabs (Pending / Completed) ──────────────────────────────────────

/// Pending or Completed reports, with explicit loading / error / empty states.
class _RequestsTab extends ConsumerWidget {
  final bool completed;
  const _RequestsTab({required this.completed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myAssignedRequestsProvider);
    return AsyncStateView<List<AstrologerRequestModel>>(
      value: async,
      errorTitle:
          'Couldn\'t load your ${completed ? 'completed' : 'pending'} reports',
      onRetry: () => ref.invalidate(myAssignedRequestsProvider),
      builder: (all) {
        final requests = all
            .where((r) => completed
                ? r.status == AstrologerRequestStatus.completed
                : r.status != AstrologerRequestStatus.completed)
            .toList();
        if (requests.isEmpty) {
          return EmptyStateView(
            icon: completed ? Icons.verified_outlined : Icons.inbox_outlined,
            title: completed
                ? 'No completed reports yet'
                : 'No pending reports',
            subtitle: completed
                ? 'Reports you submit will be listed here.'
                : 'Newly assigned horoscope reports will appear here.',
          );
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(myAssignedRequestsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _RequestCard(
                request: requests[i],
                trailing: completed ? 'View' : 'Open'),
          ),
        );
      },
    );
  }
}

/// One assigned-request card (shared by the Dashboard + Pending/Completed).
class _RequestCard extends StatelessWidget {
  final AstrologerRequestModel request;
  final String trailing;
  const _RequestCard({required this.request, this.trailing = 'Open'});

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/astrologer-request/${r.id}', extra: r),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Request ${r.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                const SizedBox(height: 6),
                Text(r.userName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                if ((r.groomName ?? '').isNotEmpty ||
                    (r.brideName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                      'Partners: ${r.groomName ?? '—'}  &  ${r.brideName ?? '—'}',
                      style:
                          TextStyle(fontSize: 12.5, color: Colors.grey[700])),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Requested: ${_date(r.createdAt)}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text(trailing,
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Work Report page — the COMPLETE analytics page (per spec) ───────────────
//
// Daily / weekly / monthly summaries, all-time totals with completion %,
// income analysis, performance analysis, daily/weekly/monthly charts and a
// searchable, filterable report history. The Dashboard stays a quick overview;
// everything detailed lives here.

enum _ChartPeriod { daily, weekly, monthly }

enum _HistoryFilter { all, pending, completed }

/// One bar-chart bucket: assigned vs completed counts for a time slice.
class _ChartBucket {
  final String label;
  final int assigned;
  final int completed;
  const _ChartBucket(this.label, this.assigned, this.completed);
}

class _WorkReportPage extends ConsumerStatefulWidget {
  const _WorkReportPage();

  @override
  ConsumerState<_WorkReportPage> createState() => _WorkReportPageState();
}

class _WorkReportPageState extends ConsumerState<_WorkReportPage> {
  _ChartPeriod _period = _ChartPeriod.daily;
  _HistoryFilter _filter = _HistoryFilter.all;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final memberAsync = ref.watch(myAstrologerTeamMemberProvider);
    return AsyncStateView<AstrologerTeamMember?>(
      value: memberAsync,
      errorTitle: 'Couldn\'t load your work report',
      onRetry: () {
        ref.invalidate(myAstrologerTeamMemberProvider);
        ref.invalidate(myAssignedRequestsProvider);
      },
      builder: (m) {
        if (m == null) {
          return const EmptyStateView(
            icon: Icons.insights_outlined,
            title: 'No work report yet',
            subtitle:
                'Your employee account was not found — contact the admin.',
          );
        }
        final s = ref.watch(myAstrologerStatsProvider);
        if (s == null) {
          // Member exists but stats haven't computed this frame — momentary.
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final requests =
            ref.watch(myAssignedRequestsProvider).valueOrNull ?? const [];

        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _totalsCard(s),
            const SizedBox(height: 16),
            const _SectionTitle('Report Summary'),
            _summaryCard(s),
            const SizedBox(height: 16),
            const _SectionTitle('Work Charts'),
            _chartsCard(requests),
            const SizedBox(height: 16),
            const _SectionTitle('Income Analysis'),
            _incomeCard(s),
            const SizedBox(height: 8),
            _payrollStatusCard(s),
            const SizedBox(height: 12),
            const _MyPaymentHistory(),
            const SizedBox(height: 16),
            const _SectionTitle('Performance Analysis'),
            _performanceCard(s, requests),
            const SizedBox(height: 16),
            const _SectionTitle('Report History'),
            _historyCard(requests),
          ],
        );
      },
    );
  }

  // ── All-time totals ────────────────────────────────────────────────────────

  Widget _totalsCard(AstrologerStats s) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Overall Totals',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _wk('Assigned', s.totalAssigned),
                _wk('Completed', s.completed),
                _wk('Pending', s.pending + s.inProgress),
                _wk('Rate', s.completionRate, suffix: '%'),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: s.completionRate / 100,
                minHeight: 7,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(AppColors.gold),
              ),
            ),
            const SizedBox(height: 8),
            Text(
                'Completion percentage: ${s.completionRate}% '
                '(${s.completed} of ${s.totalAssigned} reports)',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );

  // ── Daily / weekly / monthly summary table ────────────────────────────────

  Widget _summaryCard(AstrologerStats s) {
    Widget row(String label, int assigned, int completed, int pending,
        {int? rate, bool header = false}) {
      final style = TextStyle(
        fontSize: header ? 11.5 : 13,
        fontWeight: header ? FontWeight.w600 : FontWeight.w700,
        color: header ? Colors.grey[600] : Colors.black87,
      );
      final labelStyle = TextStyle(
        fontSize: header ? 11.5 : 13,
        fontWeight: FontWeight.w600,
        color: header ? Colors.grey[600] : Colors.grey[800],
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(label, style: labelStyle)),
            Expanded(
                child: Text(header ? 'Asgn' : '$assigned',
                    textAlign: TextAlign.center, style: style)),
            Expanded(
                child: Text(header ? 'Done' : '$completed',
                    textAlign: TextAlign.center, style: style)),
            Expanded(
                child: Text(header ? 'Pend' : '$pending',
                    textAlign: TextAlign.center, style: style)),
            Expanded(
                child: Text(header ? 'Rate' : '${rate ?? 0}%',
                    textAlign: TextAlign.end, style: style)),
          ],
        ),
      );
    }

    int rateOf(int assigned, int completed) =>
        assigned == 0 ? 0 : ((completed / assigned) * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          row('', 0, 0, 0, header: true),
          const Divider(height: 8),
          row('Today', s.todayAssigned, s.todayCompleted, s.todayPending,
              rate: rateOf(s.todayAssigned, s.todayCompleted)),
          row('This Week', s.thisWeek.assigned, s.thisWeek.completed,
              s.thisWeek.pending,
              rate: s.thisWeek.completionRate),
          row('Last Week', s.lastWeek.assigned, s.lastWeek.completed,
              s.lastWeek.pending,
              rate: s.lastWeek.completionRate),
          row('This Month', s.monthAssigned, s.monthCompleted, s.monthPending,
              rate: rateOf(s.monthAssigned, s.monthCompleted)),
        ],
      ),
    );
  }

  // ── Charts ─────────────────────────────────────────────────────────────────

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Buckets the employee's requests into the chart's time slices —
  /// last 7 days, last 6 weeks or last 6 months.
  List<_ChartBucket> _buckets(
      List<AstrologerRequestModel> mine, _ChartPeriod p) {
    final now = DateTime.now();
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

    final ranges = <({String label, DateTime start, DateTime end})>[];
    switch (p) {
      case _ChartPeriod.daily:
        for (var i = 6; i >= 0; i--) {
          final start = day(now).subtract(Duration(days: i));
          ranges.add((
            label: _dayNames[start.weekday - 1],
            start: start,
            end: start.add(const Duration(days: 1)),
          ));
        }
      case _ChartPeriod.weekly:
        final thisMonday =
            day(now).subtract(Duration(days: now.weekday - 1));
        for (var i = 5; i >= 0; i--) {
          final start = thisMonday.subtract(Duration(days: 7 * i));
          ranges.add((
            label: '${start.day}/${start.month}',
            start: start,
            end: start.add(const Duration(days: 7)),
          ));
        }
      case _ChartPeriod.monthly:
        for (var i = 5; i >= 0; i--) {
          final start = DateTime(now.year, now.month - i, 1);
          ranges.add((
            label: _monthNames[start.month - 1],
            start: start,
            end: DateTime(start.year, start.month + 1, 1),
          ));
        }
    }

    bool within(DateTime? d, DateTime start, DateTime end) =>
        d != null && !d.isBefore(start) && d.isBefore(end);

    return [
      for (final r in ranges)
        _ChartBucket(
          r.label,
          mine.where((q) => within(q.assignedAt, r.start, r.end)).length,
          mine.where((q) => within(q.completedAt, r.start, r.end)).length,
        ),
    ];
  }

  Widget _chartsCard(List<AstrologerRequestModel> requests) {
    final buckets = _buckets(requests, _period);
    final rawMax = buckets.fold<int>(
        0,
        (acc, b) =>
            [acc, b.assigned, b.completed].reduce((a, v) => a > v ? a : v));
    final maxY = (rawMax < 4 ? 4 : rawMax + 1).toDouble();
    final interval = (maxY / 4).ceilToDouble();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_ChartPeriod>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              selectedBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.1),
              selectedForegroundColor: AppColors.primary,
            ),
            segments: const [
              ButtonSegment(
                  value: _ChartPeriod.daily, label: Text('Daily')),
              ButtonSegment(
                  value: _ChartPeriod.weekly, label: Text('Weekly')),
              ButtonSegment(
                  value: _ChartPeriod.monthly, label: Text('Monthly')),
            ],
            selected: {_period},
            onSelectionChanged: (sel) =>
                setState(() => _period = sel.first),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(enabled: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
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
                      reservedSize: 28,
                      interval: interval,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[600])),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= buckets.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(buckets[i].label,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[600])),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < buckets.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 3,
                      barRods: [
                        BarChartRodData(
                          toY: buckets[i].assigned.toDouble(),
                          width: 7,
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        BarChartRodData(
                          toY: buckets[i].completed.toDouble(),
                          width: 7,
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(AppColors.gold, 'Assigned'),
              const SizedBox(width: 16),
              _legendDot(AppColors.primary, 'Completed'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[700])),
        ],
      );

  // ── Income analysis ────────────────────────────────────────────────────────

  Widget _incomeCard(AstrologerStats s) => _reportCard('My Earnings', [
        _r('Commission Per Report', '₹${s.commissionPerReport}'),
        _r('This Week', '₹${s.weeklyCommission}'),
        _r('This Month', '₹${s.monthlyCommission}'),
        _r('Current Cycle (unpaid)', '₹${s.cycleCommission}'),
        _r('Total Earned (all-time)', '₹${s.totalCommission}'),
        _r('Total Paid', '₹${s.paidCommission}'),
      ]);

  // ── Performance analysis ───────────────────────────────────────────────────

  Widget _performanceCard(
      AstrologerStats s, List<AstrologerRequestModel> requests) {
    // Average turnaround: assigned → completed, across completed reports that
    // carry both timestamps.
    var totalHours = 0.0;
    var counted = 0;
    for (final r in requests) {
      if (r.completedAt != null && r.assignedAt != null) {
        totalHours +=
            r.completedAt!.difference(r.assignedAt!).inMinutes / 60.0;
        counted++;
      }
    }
    final avgHours = counted == 0 ? 0.0 : totalHours / counted;
    final turnaround = counted == 0
        ? '—'
        : avgHours < 24
            ? '${avgHours.toStringAsFixed(1)} hours'
            : '${(avgHours / 24).toStringAsFixed(1)} days';

    final delta = s.thisWeek.completed - s.lastWeek.completed;
    final trendUp = delta >= 0;

    return _reportCard('Performance', [
      _r('Overall Completion Rate', '${s.completionRate}%'),
      _r('This Week\'s Rate', '${s.thisWeek.completionRate}%'),
      _r('Average Turnaround', turnaround),
      _r('In Progress Right Now', '${s.inProgress}'),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Week-over-Week',
                style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            Row(
              children: [
                Icon(trendUp ? Icons.trending_up : Icons.trending_down,
                    size: 16,
                    color:
                        trendUp ? AppColors.success : AppColors.error),
                const SizedBox(width: 4),
                Text(
                    '${delta >= 0 ? '+' : ''}$delta completed vs last week',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: trendUp
                            ? AppColors.success
                            : AppColors.error)),
              ],
            ),
          ],
        ),
      ),
    ]);
  }

  // ── Report history (search + filters) ─────────────────────────────────────

  Widget _historyCard(List<AstrologerRequestModel> requests) {
    final sorted = [...requests]..sort((a, b) =>
        (b.completedAt ?? b.assignedAt ?? b.createdAt)
            .compareTo(a.completedAt ?? a.assignedAt ?? a.createdAt));

    final q = _query.trim().toLowerCase();
    final visible = sorted.where((r) {
      final matchesFilter = switch (_filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.completed =>
          r.status == AstrologerRequestStatus.completed,
        _HistoryFilter.pending =>
          r.status != AstrologerRequestStatus.completed,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return r.userName.toLowerCase().contains(q) ||
          r.id.toLowerCase().contains(q) ||
          (r.groomName ?? '').toLowerCase().contains(q) ||
          (r.brideName ?? '').toLowerCase().contains(q);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search by member, partner or request id…',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final f in _HistoryFilter.values)
                ChoiceChip(
                  label: Text(switch (f) {
                    _HistoryFilter.all => 'All',
                    _HistoryFilter.pending => 'Pending',
                    _HistoryFilter.completed => 'Completed',
                  }),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  selectedColor: AppColors.primary.withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _filter == f
                          ? AppColors.primary
                          : Colors.grey[700]),
                ),
            ],
          ),
          const Divider(height: 20),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                    q.isEmpty
                        ? 'No reports in this filter yet.'
                        : 'No reports match "$_query".',
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 13)),
              ),
            )
          else ...[
            for (final r in visible.take(25)) _historyRow(r),
            if (visible.length > 25)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                      'Showing 25 of ${visible.length} reports — refine the '
                      'search to narrow down.',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey[500])),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _historyRow(AstrologerRequestModel r) {
    final completed = r.status == AstrologerRequestStatus.completed;
    final color = completed ? AppColors.success : AppColors.warning;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/astrologer-request/${r.id}', extra: r),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
                completed
                    ? Icons.check_circle_outline
                    : Icons.pending_outlined,
                size: 18,
                color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  Text(
                      completed
                          ? 'Completed ${_date(r.completedAt)}'
                          : 'Assigned ${_date(r.assignedAt ?? r.createdAt)}',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey[600])),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(completed ? 'Completed' : 'Pending',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared bits ────────────────────────────────────────────────────────────

  Widget _wk(String label, int value, {String suffix = ''}) => Column(
        children: [
          Text('$value$suffix',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );

  Widget _reportCard(String title, List<Widget> rows) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      );

  Widget _r(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            Text(v,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  /// Current payroll-cycle status banner: Pending (money owed this week) or
  /// Paid (the admin has settled everything earned so far).
  Widget _payrollStatusCard(AstrologerStats s) {
    final pending = s.cycleCommission > 0;
    final color = pending ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(pending ? Icons.hourglass_top : Icons.verified,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pending
                  ? 'Payment Status: PENDING — ₹${s.cycleCommission} will be '
                      'paid in this week\'s payroll.'
                  : 'Payment Status: PAID — your commission restarts from ₹0 '
                      'for the new week.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }
}

/// The employee's own weekly payment history (read-only).
class _MyPaymentHistory extends ConsumerWidget {
  const _MyPaymentHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(myPayrollHistoryProvider).valueOrNull ?? const [];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment History',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text('No payments received yet.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13))
          else
            for (final p in items.take(10)) PayrollHistoryTile(payment: p),
        ],
      ),
    );
  }
}

// ── Profile page (spec §5/§6) ────────────────────────────────────────────────

class _ProfilePage extends ConsumerStatefulWidget {
  const _ProfilePage();
  @override
  ConsumerState<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<_ProfilePage> {
  bool _busy = false;

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _changePhoto(AstrologerTeamMember m) async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final url =
          await ref.read(astrologyTeamServiceProvider).uploadPhoto(File(picked.path));
      await ref
          .read(astrologyTeamServiceProvider)
          .updateMember(m.id, {'photoUrl': url});
      if (mounted) _snack('Profile photo updated.');
    } catch (_) {
      if (mounted) _snack('Could not update photo. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editProfile(AstrologerTeamMember m) async {
    final name = TextEditingController(text: m.displayName);
    final about = TextEditingController(text: m.about);
    final exp = TextEditingController(text: m.experience);
    final qual = TextEditingController(text: m.qualification);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Edit Profile',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _tf(name, 'Display name'),
            _tf(about, 'About', maxLines: 3),
            _tf(exp, 'Experience (e.g. 10+ years)'),
            _tf(qual, 'Qualification'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await ref.read(astrologyTeamServiceProvider).updateMember(m.id, {
          'displayName': name.text.trim(),
          'about': about.text.trim(),
          'experience': exp.text.trim(),
          'qualification': qual.text.trim(),
        });
        if (mounted) _snack('Profile updated.');
      } catch (_) {
        if (mounted) _snack('Could not save. Please try again.');
      }
    }
  }

  Widget _tf(TextEditingController c, String label, {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Future<void> _logout() async {
    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) context.go('/login');
  }

  Future<void> _deleteAccount(AstrologerTeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This removes your employee account. You will be signed out and '
            'can no longer receive requests. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(astrologyTeamServiceProvider).deleteSelf(m.id);
      await ref.read(authNotifierProvider.notifier).signOut();
      if (mounted) context.go('/login');
    } catch (_) {
      if (mounted) _snack('Could not delete the account. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberAsync = ref.watch(myAstrologerTeamMemberProvider);
    // The Profile page must NEVER be a bare endless spinner: loading shows a
    // spinner only while genuinely loading; error and "not registered" both
    // fall back to a page that still shows the signed-in account + Logout.
    return memberAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) {
        debugPrint('[AstrologerProfile] member stream error: $e');
        return _fallbackPage(
          icon: Icons.cloud_off_rounded,
          message: 'Couldn\'t load your employee profile. '
              'Please check your connection and retry.',
          showRetry: true,
        );
      },
      data: (m) => m == null
          ? _fallbackPage(
              icon: Icons.badge_outlined,
              message: 'Your employee account was not found. '
                  'Ask the admin to register your Gmail in the astrology team.',
              showRetry: false,
            )
          : _profileBody(m),
    );
  }

  /// Error / not-registered fallback — still shows the signed-in identity and
  /// ALWAYS offers Logout (never a dead end).
  Widget _fallbackPage({
    required IconData icon,
    required String message,
    required bool showRetry,
  }) {
    final authUser = ref.watch(firebaseAuthStreamProvider).valueOrNull;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 24),
        Icon(icon, size: 52, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: Colors.grey[700])),
        const SizedBox(height: 20),
        _card([
          _info('Signed in as', authUser?.displayName ?? '—'),
          _info('Email', authUser?.email ?? '—'),
        ]),
        const SizedBox(height: 12),
        if (showRetry)
          _actionTile(Icons.refresh, 'Retry',
              () => ref.invalidate(myAstrologerTeamMemberProvider)),
        _actionTile(Icons.logout, 'Logout', _logout),
      ],
    );
  }

  Widget _profileBody(AstrologerTeamMember m) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Stack(
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage:
                    m.photoUrl.isNotEmpty ? NetworkImage(m.photoUrl) : null,
                child: m.photoUrl.isEmpty
                    ? const Icon(Icons.person,
                        color: AppColors.primary, size: 46)
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: InkWell(
                  onTap: _busy ? null : () => _changePhoto(m),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.camera_alt,
                            size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(m.displayName.isEmpty ? m.email : m.displayName,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        Center(
          child: Text(m.email,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ),
        const SizedBox(height: 16),

        // Account details (spec: name / email / mobile / role / employee id).
        _card([
          const Text('Account Details',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 6),
          _info('Employee Name', m.displayName.isEmpty ? m.email : m.displayName),
          _info('Email', m.email),
          _info('Mobile Number', m.mobile),
          _info('Assigned Role', 'Astrologer — Employee'),
          _info('Employee ID', m.id),
          _info('Account Status', m.statusLabel),
        ]),
        const SizedBox(height: 12),

        // Availability (spec §6).
        _card([
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: m.available,
            activeColor: Colors.green,
            title: Text(m.available ? 'Available' : 'Unavailable',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(m.available
                ? 'You are receiving new horoscope analysis requests.'
                : 'New requests are paused — you will not be assigned any.'),
            onChanged: m.active
                ? (v) =>
                    ref.read(astrologyTeamServiceProvider).setAvailable(m.id, v)
                : null,
          ),
          if (!m.active)
            Text('Your account is disabled by the admin.',
                style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
        ]),
        const SizedBox(height: 12),

        // About / experience / qualification.
        _card([
          _info('About', m.about),
          _info('Experience', m.experience),
          _info('Qualification', m.qualification),
        ]),
        const SizedBox(height: 12),

        _actionTile(Icons.edit_outlined, 'Edit Profile', () => _editProfile(m)),
        _actionTile(Icons.logout, 'Logout', _logout),
        _actionTile(Icons.delete_outline, 'Delete Account',
            () => _deleteAccount(m),
            color: AppColors.error),
      ],
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            Text(value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 13.5)),
          ],
        ),
      );

  Widget _actionTile(IconData icon, String label, VoidCallback onTap,
          {Color color = AppColors.primary}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: onTap,
        ),
      );
}
