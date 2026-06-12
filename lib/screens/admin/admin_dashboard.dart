import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/admin_provider.dart';

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dashboard', style: AppTextStyles.heading2),
          const SizedBox(height: 16),
          statsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (stats) => Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Total Users',
                        value: '${stats['totalUsers'] ?? 0}',
                        icon: Icons.people,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'Total Profiles',
                        value: '${stats['totalProfiles'] ?? 0}',
                        icon: Icons.person,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Pending Approvals',
                        value: '${stats['pendingProfiles'] ?? 0}',
                        icon: Icons.hourglass_empty,
                        color: Colors.orange,
                        onTap: () => context.go('/admin/approvals'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'Reports',
                        value: '${stats['totalReports'] ?? 0}',
                        icon: Icons.report,
                        color: Colors.red,
                        onTap: () => context.go('/admin/reports'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Astrologers',
                        value: '${stats['totalAstrologers'] ?? 0}',
                        icon: Icons.auto_awesome,
                        color: AppColors.gold,
                        onTap: () => context.go('/admin/astrologers'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'Consultations',
                        value: '${stats['totalConsultations'] ?? 0}',
                        icon: Icons.event_available,
                        color: Colors.teal,
                        onTap: () => context.go('/admin/analytics'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Management', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.5,
            children: [
              _QuickAction('User Management', Icons.manage_accounts, () => context.go('/admin/users')),
              _QuickAction('Profile Approvals', Icons.approval, () => context.go('/admin/approvals')),
              _QuickAction('Astrologer Mgmt', Icons.auto_awesome, () => context.go('/admin/astrologers')),
              _QuickAction('Rating Mgmt', Icons.star_rate, () => context.go('/admin/ratings')),
              _QuickAction('Banner Mgmt', Icons.view_carousel, () => context.go('/admin/banners')),
              _QuickAction('Premium Mgmt', Icons.workspace_premium, () => context.go('/admin/premium')),
              _QuickAction('Analytics', Icons.insights, () => context.go('/admin/analytics')),
              _QuickAction('Reports', Icons.report_problem, () => context.go('/admin/reports')),
              _QuickAction('Settings', Icons.settings, () => context.go('/admin/settings')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold, color: color)),
                  Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAction(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
