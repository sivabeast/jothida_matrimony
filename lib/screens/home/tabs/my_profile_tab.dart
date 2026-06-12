import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/subscription_provider.dart';

class MyProfileTab extends ConsumerWidget {
  const MyProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authNotifierProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final subAsync = ref.watch(activeSubscriptionProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile header card
          profileAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (profile) => Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      backgroundImage: (profile?.photos.isNotEmpty ?? false)
                          ? NetworkImage(profile!.photos.first)
                          : null,
                      child: (profile?.photos.isEmpty ?? true)
                          ? const Icon(Icons.person, size: 52, color: AppColors.primary)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile?.name ?? 'Complete your profile',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (profile != null) ...[
                      Text(
                        '${profile.age} yrs • ${profile.city}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      _buildStatusChip(profile.status),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStat('Views', profile?.viewCount.toString() ?? '0'),
                        _buildStat('Interests', '0'),
                        _buildStat('Matches', '0'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    profile == null
                        ? ElevatedButton.icon(
                            onPressed: () => context.push('/profile/create'),
                            icon: const Icon(Icons.add),
                            label: const Text('Create Profile'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => context.push('/profile/${profile.id}/edit'),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit Profile'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Subscription card
          subAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (sub) => sub == null
                ? _buildUpgradeCard(context)
                : _buildSubCard(sub.plan, sub.daysRemaining),
          ),
          const SizedBox(height: 16),
          // Menu items
          _buildMenuItem(context, Icons.language, 'Language / மொழி', '/language'),
          _buildMenuItem(context, Icons.lock_outline, 'Privacy Settings', '/privacy'),
          _buildMenuItem(context, Icons.star_border, 'Horoscope Details', '/horoscope'),
          // "Porutham Analysis" self-serve removed — astrologer consultation
          // (Match → Compatibility → Connect Astrologer) is the only analysis flow.
          _buildMenuItem(context, Icons.workspace_premium, 'Subscription Plans', '/subscription'),
          _buildMenuItem(context, Icons.help_outline, 'Help & Support', '/help'),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              debugPrint('[MyProfileTab] Sign Out tapped — showing confirmation');
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) {
                debugPrint('[MyProfileTab] Sign Out cancelled by user.');
                return;
              }
              debugPrint('[MyProfileTab] Sign Out confirmed — calling signOut()');
              await ref.read(authNotifierProvider.notifier).signOut();
              debugPrint('[MyProfileTab] signOut() complete — '
                  'router redirect will handle navigation');
              // Safety-net: if the GoRouterRefreshStream fires after this
              // widget's context is gone, the explicit go() ensures navigation.
              if (context.mounted) context.go('/account-type');
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Colors.red[50],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'approved':
        color = Colors.green;
        break;
      case 'pending':
        color = Colors.orange;
        break;
      case 'rejected':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStat(String label, String value) => Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      );

  Widget _buildUpgradeCard(BuildContext context) => Card(
        color: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: const Icon(Icons.workspace_premium, color: AppColors.gold),
          title: const Text('Upgrade to Premium',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: const Text('Get unlimited access & free astrologer consultations',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          onTap: () => context.push('/subscription'),
        ),
      );

  Widget _buildSubCard(String plan, int daysLeft) => Card(
        color: AppColors.gold.withOpacity(0.1),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.gold.withOpacity(0.3))),
        child: ListTile(
          leading: const Icon(Icons.workspace_premium, color: AppColors.gold),
          title: Text(
            '${plan[0].toUpperCase()}${plan.substring(1)} Plan',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('$daysLeft days remaining'),
        ),
      );

  Widget _buildMenuItem(BuildContext context, IconData icon, String title, String route) =>
      ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => context.push(route),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}
