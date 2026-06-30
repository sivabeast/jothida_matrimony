import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../providers/astrology_team_provider.dart';
import '../../../providers/astrology_team_stats_provider.dart';
import '../../../providers/auth_provider.dart';

/// The astrologer portal home (Google-only, admin-provisioned accounts).
///
/// Shows the full workload + earnings statistics (spec §7/§8) and three tabs —
/// Pending · In Progress · Completed (spec §5). Every list is scoped to the
/// signed-in astrologer's OWN requests (by Gmail), so one astrologer never sees
/// another's. Opening a request navigates to the details + report screen.
class AstrologerDashboardPage extends ConsumerWidget {
  const AstrologerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests =
        ref.watch(myAssignedRequestsProvider).valueOrNull ?? const [];
    final member = ref.watch(myAstrologerTeamMemberProvider).valueOrNull;
    final stats = ref.watch(myAstrologerStatsProvider);

    final pending = requests
        .where((r) =>
            r.status == AstrologerRequestStatus.pending && !r.inProgress)
        .toList();
    final inProgress = requests
        .where(
            (r) => r.status == AstrologerRequestStatus.pending && r.inProgress)
        .toList();
    final completed = requests
        .where((r) => r.status == AstrologerRequestStatus.completed)
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text(member?.displayName.isNotEmpty == true
              ? 'Welcome, ${member!.displayName}'
              : 'Astrologer Dashboard'),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).signOut();
                if (context.mounted) context.go('/account-type');
              },
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Pending (${pending.length})'),
              Tab(text: 'In Progress (${inProgress.length})'),
              Tab(text: 'Completed (${completed.length})'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (member != null && !member.active) _disabledBanner(),
            if (stats != null) _metrics(stats),
            Expanded(
              child: TabBarView(
                children: [
                  _RequestList(
                    requests: pending,
                    emptyIcon: Icons.inbox_outlined,
                    emptyText: 'No pending requests',
                    trailing: 'Open Details',
                  ),
                  _RequestList(
                    requests: inProgress,
                    emptyIcon: Icons.timelapse_outlined,
                    emptyText: 'Nothing in progress',
                    trailing: 'Continue',
                  ),
                  _RequestList(
                    requests: completed,
                    emptyIcon: Icons.verified_outlined,
                    emptyText: 'No completed reports yet',
                    trailing: 'View',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disabledBanner() => Container(
        width: double.infinity,
        color: Colors.red.shade50,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.pause_circle_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your account is disabled by the admin. You will not receive '
                'new requests until it is re-enabled.',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );

  Widget _metrics(AstrologerStats s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricCard(
                  label: 'Total Assigned',
                  value: '${s.totalAssigned}',
                  icon: Icons.assignment),
              _MetricCard(
                  label: 'Pending',
                  value: '${s.pending}',
                  icon: Icons.hourglass_bottom,
                  color: Colors.orange),
              _MetricCard(
                  label: 'In Progress',
                  value: '${s.inProgress}',
                  icon: Icons.timelapse,
                  color: Colors.blue),
              _MetricCard(
                  label: 'Completed',
                  value: '${s.completed}',
                  icon: Icons.check_circle,
                  color: Colors.green),
              _MetricCard(
                  label: "Today's Completed",
                  value: '${s.todayCompleted}',
                  icon: Icons.today,
                  color: Colors.teal),
              _MetricCard(
                  label: 'This Month',
                  value: '${s.monthCompleted}',
                  icon: Icons.calendar_month,
                  color: Colors.indigo),
              _MetricCard(
                  label: 'Revenue',
                  value: '₹${s.revenue}',
                  icon: Icons.payments,
                  color: AppColors.primary),
              _MetricCard(
                  label: 'Commission',
                  value: '₹${s.commission}',
                  icon: Icons.savings,
                  color: Colors.purple),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text('Commission per report: ₹${s.commissionPerReport}',
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.of(context).size.width - 24 - 20) / 3;
    return Container(
      width: w.clamp(96, 160),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  final List<AstrologerRequestModel> requests;
  final IconData emptyIcon;
  final String emptyText;
  final String trailing;
  const _RequestList({
    required this.requests,
    required this.emptyIcon,
    required this.emptyText,
    required this.trailing,
  });

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 56, color: AppColors.primary.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(emptyText, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = requests[i];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () =>
                context.push('/astrologer-request/${r.id}', extra: r),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Request ${r.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                  const SizedBox(height: 6),
                  Text(r.userName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  if ((r.groomName ?? '').isNotEmpty ||
                      (r.brideName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Partners: ${r.groomName ?? '—'}  &  ${r.brideName ?? '—'}',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
                    ),
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
        );
      },
    );
  }
}
