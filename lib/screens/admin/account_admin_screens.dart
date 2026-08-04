import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/account_provider.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';
import '../../widgets/common/skeletons.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Married Users + marriage statistics
// ─────────────────────────────────────────────────────────────────────────────

class MarriedUsersScreen extends ConsumerWidget {
  const MarriedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[Admin] MarriedUsers build — /admin/married');
    final marriedAsync = ref.watch(marriedProfilesProvider);
    final stats = ref.watch(adminStatsProvider).valueOrNull ?? const {};
    final totalMarried = stats['marriedUsers'] ?? 0;
    final totalProfiles = (stats['totalProfiles'] ?? 0) as int;
    final successRate = (totalProfiles > 0 && totalMarried is int)
        ? ((totalMarried / totalProfiles) * 100).toStringAsFixed(1)
        : '0.0';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Married Users'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                  child: _statTile('Total Married', '$totalMarried',
                      Icons.celebration, AppColors.gold)),
              const SizedBox(width: 12),
              Expanded(
                  child: _statTile('Success Rate', '$successRate%',
                      Icons.favorite, AppColors.primary)),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Recently Married',
              style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 10),
          marriedAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SkeletonList(items: 5),
            ),
            error: (e, _) {
              debugPrint('[Admin] married users load failed: $e');
              return Padding(
                padding: const EdgeInsets.all(24),
                child: ErrorStateView(
                  message: 'Unable to load married users. Please try again.',
                  onRetry: () => ref.invalidate(marriedProfilesProvider),
                ),
              );
            },
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.favorite_border,
                  message: 'No married users yet',
                  subtitle: 'Members marked as married will appear here.',
                );
              }
              return Column(
                children: list
                    .map((p) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8),
                            ],
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0x22D4AF37),
                              child: Text('🎉', style: TextStyle(fontSize: 18)),
                            ),
                            title: Text(p.name),
                            subtitle: Text(
                                '${p.age} yrs • ${p.city.isEmpty ? '—' : p.city}'),
                            trailing: const Icon(Icons.verified,
                                color: AppColors.gold, size: 18),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
}

