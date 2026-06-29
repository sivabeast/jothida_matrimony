import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../providers/astrology_team_provider.dart';
import '../../../providers/auth_provider.dart';

/// The astrologer portal home (Google-only, admin-provisioned accounts).
///
/// Shows the 5 workload metrics (spec §7) and two tabs — Pending Requests
/// (spec §8) and Completed Reports (spec §12). Every list is scoped to the
/// signed-in astrologer's own requests; opening one navigates to the request
/// details + report-submission page.
class AstrologerDashboardPage extends ConsumerWidget {
  const AstrologerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests =
        ref.watch(myAssignedRequestsProvider).valueOrNull ?? const [];
    final member = ref.watch(myAstrologerTeamMemberProvider).valueOrNull;

    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final pending = requests
        .where((r) => r.status == AstrologerRequestStatus.pending)
        .toList();
    final completed = requests
        .where((r) => r.status == AstrologerRequestStatus.completed)
        .toList();
    final todays =
        requests.where((r) => sameDay(r.createdAt, now)).length;
    final monthlyCompleted = completed
        .where((r) =>
            r.completedAt != null &&
            r.completedAt!.year == now.year &&
            r.completedAt!.month == now.month)
        .length;

    return DefaultTabController(
      length: 2,
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
          bottom: const TabBar(
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (member != null && !member.active)
              _disabledBanner(),
            _metrics(
              total: requests.length,
              pending: pending.length,
              completed: completed.length,
              todays: todays,
              monthlyCompleted: monthlyCompleted,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _RequestList(
                    requests: pending,
                    emptyIcon: Icons.inbox_outlined,
                    emptyText: 'No pending requests',
                    showSubmitted: false,
                  ),
                  _RequestList(
                    requests: completed,
                    emptyIcon: Icons.verified_outlined,
                    emptyText: 'No completed reports yet',
                    showSubmitted: true,
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

  Widget _metrics({
    required int total,
    required int pending,
    required int completed,
    required int todays,
    required int monthlyCompleted,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MetricCard(
              label: 'Total Assigned', value: total, icon: Icons.assignment),
          _MetricCard(
              label: 'Pending',
              value: pending,
              icon: Icons.hourglass_bottom,
              color: Colors.orange),
          _MetricCard(
              label: 'Completed',
              value: completed,
              icon: Icons.check_circle,
              color: Colors.green),
          _MetricCard(
              label: "Today's Requests",
              value: todays,
              icon: Icons.today,
              color: Colors.blue),
          _MetricCard(
              label: 'Monthly Completed',
              value: monthlyCompleted,
              icon: Icons.calendar_month,
              color: Colors.purple),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final int value;
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
          Text('$value',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800)),
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
  final bool showSubmitted;
  const _RequestList({
    required this.requests,
    required this.emptyIcon,
    required this.emptyText,
    required this.showSubmitted,
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
                  Row(
                    children: [
                      const Icon(Icons.tag, size: 14, color: Colors.grey),
                      Expanded(
                        child: Text('Request ${r.id}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey[600])),
                      ),
                    ],
                  ),
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
                      Text(
                        showSubmitted && r.completedAt != null
                            ? 'Submitted: ${_date(r.completedAt!)}'
                            : 'Requested: ${_date(r.createdAt)}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        showSubmitted ? 'View Report' : 'Open Details',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5),
                      ),
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
