import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/astrology_team_stats_provider.dart';

/// Shared Astrologer **Performance** list — replaces the old subscription
/// (Free/Monthly/Yearly) view. Each card shows the astrologer's photo, name,
/// Gmail, active status and live workload + earnings, with a View Details
/// action. Reused by the admin "Astrologers" page and the Users → Astrologers
/// tab.
class AstrologerPerformanceList extends ConsumerWidget {
  /// Extra bottom padding so a floating "Add" button never covers the last card.
  final double bottomPadding;
  const AstrologerPerformanceList({super.key, this.bottomPadding = 24});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(astrologerStatsProvider);
    if (stats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insights_outlined, size: 56, color: AppColors.primary),
              SizedBox(height: 12),
              Text('No astrologer accounts yet.\n'
                  'Add one by Gmail to see performance here.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(14, 14, 14, bottomPadding),
      itemCount: stats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => AstrologerPerformanceCard(stats: stats[i]),
    );
  }
}

class AstrologerPerformanceCard extends StatelessWidget {
  final AstrologerStats stats;
  const AstrologerPerformanceCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final m = stats.member;
    final statusColor = !m.active
        ? Colors.red
        : (m.isLinked ? Colors.green : Colors.orange);
    return Container(
      padding: const EdgeInsets.all(14),
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
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage:
                    m.photoUrl.isNotEmpty ? NetworkImage(m.photoUrl) : null,
                child: m.photoUrl.isEmpty
                    ? const Icon(Icons.person, color: AppColors.primary)
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
                          fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                    Text(m.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(m.statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('Assigned', '${stats.totalAssigned}', Icons.assignment),
              _stat('Pending', '${stats.pending}', Icons.hourglass_bottom,
                  Colors.orange),
              _stat('Completed', '${stats.completed}', Icons.check_circle,
                  Colors.green),
              _stat('Revenue', '₹${stats.revenue}', Icons.payments,
                  AppColors.primary),
              _stat('Commission', '₹${stats.commission}', Icons.savings,
                  Colors.purple),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push(
                  '/admin/astrologer-account/${Uri.encodeComponent(m.id)}'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('View Details'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(40),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon,
          [Color color = AppColors.primary]) =>
      Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(label,
                style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
          ],
        ),
      );
}
