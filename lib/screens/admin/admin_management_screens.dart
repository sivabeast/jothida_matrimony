import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/admin_provider.dart';

/// Admin management section screens, registered under the admin ShellRoute:
///   /admin/astrologers · /admin/ratings · /admin/banners
///   /admin/premium · /admin/analytics · /admin/settings
///
/// These provide the navigable Super Admin sections requested for the
/// dashboard. Sections backed by existing providers (Analytics) show live
/// data; the rest present their actions and are ready to be wired to backend
/// queries/mutations.

// ─────────────────────────────────────────────────────────────────────────────
// Shared building blocks
// ─────────────────────────────────────────────────────────────────────────────

Widget _adminScaffold({
  required String title,
  required IconData icon,
  required String subtitle,
  required List<Widget> children,
}) {
  return Scaffold(
    backgroundColor: AppColors.scaffoldBg,
    appBar: AppBar(
      title: Text(title),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminHeader(icon: icon, title: title, subtitle: subtitle),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

class _AdminHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _AdminHeader(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: c.withOpacity(0.12),
          child: Icon(icon, color: c),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}

void _soon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$feature — connect backend to enable')));
}

// ─────────────────────────────────────────────────────────────────────────────
// 🔮 Astrologer Management
// ─────────────────────────────────────────────────────────────────────────────

class AstrologerManagementScreen extends StatelessWidget {
  const AstrologerManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] AstrologerManagement build — /admin/astrologers');
    return _adminScaffold(
      title: 'Astrologer Management',
      icon: Icons.auto_awesome,
      subtitle: 'View, approve and suspend astrologers',
      children: [
        _ActionTile(
          icon: Icons.list_alt,
          title: 'View Astrologers',
          subtitle: 'Browse all registered astrologers',
          onTap: () => _soon(context, 'View Astrologers'),
        ),
        _ActionTile(
          icon: Icons.verified_outlined,
          title: 'Approve Astrologers',
          subtitle: 'Review and approve pending applications',
          color: AppColors.success,
          onTap: () => _soon(context, 'Approve Astrologers'),
        ),
        _ActionTile(
          icon: Icons.pause_circle_outline,
          title: 'Suspend Astrologers',
          subtitle: 'Temporarily disable an astrologer account',
          color: AppColors.warning,
          onTap: () => _soon(context, 'Suspend Astrologers'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ⭐ Rating Management
// ─────────────────────────────────────────────────────────────────────────────

class RatingManagementScreen extends StatelessWidget {
  const RatingManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] RatingManagement build — /admin/ratings');
    return _adminScaffold(
      title: 'Rating Management',
      icon: Icons.star_rate_rounded,
      subtitle: 'View and moderate user ratings',
      children: [
        _ActionTile(
          icon: Icons.reviews_outlined,
          title: 'View All Ratings',
          subtitle: 'See every rating left on the platform',
          onTap: () => _soon(context, 'View All Ratings'),
        ),
        _ActionTile(
          icon: Icons.gavel_outlined,
          title: 'Moderate Ratings',
          subtitle: 'Hide or remove inappropriate ratings',
          color: AppColors.error,
          onTap: () => _soon(context, 'Moderate Ratings'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 📢 Banner Management (working in-memory demo)
// ─────────────────────────────────────────────────────────────────────────────

class BannerManagementScreen extends StatefulWidget {
  const BannerManagementScreen({super.key});

  @override
  State<BannerManagementScreen> createState() => _BannerManagementScreenState();
}

class _BannerManagementScreenState extends State<BannerManagementScreen> {
  // In-memory list (demo). Wire to Firestore `banners` collection to persist.
  final List<String> _banners = [
    'Perfect Match · Written in the Stars',
    'Find Your Life Partner',
  ];

  Future<void> _edit({int? index}) async {
    final controller =
        TextEditingController(text: index == null ? '' : _banners[index]);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'Add Banner' : 'Edit Banner'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Banner title / image label',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    setState(() {
      if (index == null) {
        _banners.add(result);
      } else {
        _banners[index] = result;
      }
    });
  }

  void _delete(int index) {
    setState(() => _banners.removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Banner deleted')));
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] BannerManagement build — /admin/banners');
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Banner Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add Banner'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _AdminHeader(
            icon: Icons.view_carousel,
            title: 'Banner Management',
            subtitle: 'Add, edit and delete home banners',
          ),
          const SizedBox(height: 16),
          if (_banners.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No banners. Tap “Add Banner”.')),
            ),
          ..._banners.asMap().entries.map((e) {
            final i = e.key;
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x22800020),
                  child: Icon(Icons.image_outlined, color: AppColors.primary),
                ),
                title: Text(e.value,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: AppColors.primary),
                      onPressed: () => _edit(index: i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.error),
                      onPressed: () => _delete(i),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 💎 Premium Management
// ─────────────────────────────────────────────────────────────────────────────

class PremiumManagementScreen extends StatelessWidget {
  const PremiumManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] PremiumManagement build — /admin/premium');
    return _adminScaffold(
      title: 'Premium Management',
      icon: Icons.workspace_premium,
      subtitle: 'Premium users and subscriptions',
      children: [
        _ActionTile(
          icon: Icons.people_alt_outlined,
          title: 'View Premium Users',
          subtitle: 'List members on a paid plan',
          color: AppColors.gold,
          onTap: () => _soon(context, 'View Premium Users'),
        ),
        _ActionTile(
          icon: Icons.card_membership_outlined,
          title: 'Manage Subscriptions',
          subtitle: 'Extend, refund or cancel subscriptions',
          onTap: () => _soon(context, 'Manage Subscriptions'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 📈 Analytics (live stats from adminStatsProvider)
// ─────────────────────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[Admin] Analytics build — /admin/analytics');
    final statsAsync = ref.watch(adminStatsProvider);
    return _adminScaffold(
      title: 'Analytics',
      icon: Icons.insights,
      subtitle: 'Users, growth and revenue',
      children: [
        statsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error: $e'),
          data: (s) => Column(
            children: [
              Row(children: [
                Expanded(
                    child: _MiniStat('Total Users', '${s['totalUsers'] ?? 0}',
                        Icons.people, Colors.blue)),
                const SizedBox(width: 12),
                Expanded(
                    child: _MiniStat('New Registrations',
                        '${s['newToday'] ?? s['totalUsers'] ?? 0}',
                        Icons.person_add, AppColors.success)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _MiniStat('Profiles', '${s['totalProfiles'] ?? 0}',
                        Icons.badge_outlined, AppColors.primary)),
                const SizedBox(width: 12),
                Expanded(
                    child: _MiniStat('Revenue (₹)', '${s['revenue'] ?? 0}',
                        Icons.payments_outlined, AppColors.gold)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: Icons.trending_up,
          title: 'Daily Active Users',
          subtitle: 'Track engagement over time',
          onTap: () => _soon(context, 'Daily Active Users chart'),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
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
}

// ─────────────────────────────────────────────────────────────────────────────
// ⚙️ Admin Settings
// ─────────────────────────────────────────────────────────────────────────────

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] AdminSettings build — /admin/settings');
    return _adminScaffold(
      title: 'Admin Settings',
      icon: Icons.settings,
      subtitle: 'App and content configuration',
      children: [
        _ActionTile(
          icon: Icons.app_settings_alt_outlined,
          title: 'App Settings',
          subtitle: 'Maintenance mode, versions, feature flags',
          onTap: () => _soon(context, 'App Settings'),
        ),
        _ActionTile(
          icon: Icons.article_outlined,
          title: 'Content Settings',
          subtitle: 'Manage FAQs, policies and static content',
          onTap: () => _soon(context, 'Content Settings'),
        ),
      ],
    );
  }
}
