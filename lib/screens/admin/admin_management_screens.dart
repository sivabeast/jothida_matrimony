import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/dev_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/data_states.dart';

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

/// Neutral "coming soon" notice for sections that are navigable but not yet
/// built out. Deliberately worded so it never reads like a backend/connection
/// error to the admin.
void _soon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$feature is coming soon.')));
}

// ─────────────────────────────────────────────────────────────────────────────
// 🔮 Astrologer Management
// ─────────────────────────────────────────────────────────────────────────────

/// Live astrologer verification + management. Reads the `astrologers`
/// collection in realtime, groups by verification status, and lets an admin
/// Approve / Reject / Suspend — each action writes `status` back to Firestore
/// and the list re-buckets automatically.
class AstrologerManagementScreen extends ConsumerWidget {
  const AstrologerManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[Admin] AstrologerManagement build — /admin/astrologers');

    // Role guard (defence in depth — the router already blocks non-admins).
    final isAdmin = kBypassAuth ||
        (ref.watch(currentUserProvider).valueOrNull?.isAdmin ?? false);
    if (!isAdmin) {
      debugPrint('[Admin] ⛔ non-admin blocked from Astrologer Management');
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Astrologer Management'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const EmptyState(
          icon: Icons.lock_outline,
          message: 'Permission Denied\nOnly an admin can manage astrologers.',
        ),
      );
    }

    final astrologersAsync = ref.watch(allAstrologersProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Astrologer Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: astrologersAsync.when(
        loading: () => const LoadingState(message: 'Loading astrologers...'),
        error: (e, st) {
          debugPrint('[Admin] ❌ astrologers load failed: $e');
          return ErrorStateView(
            message: 'Connection Error — unable to load astrologers.',
            onRetry: () => ref.invalidate(allAstrologersProvider),
          );
        },
        data: (list) {
          debugPrint('[Admin] loaded ${list.length} astrologers');
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.auto_awesome_outlined,
              message: 'No astrologers registered yet',
            );
          }
          final pending = list
              .where((a) => a.status == VerificationStatus.pending)
              .toList();
          final approved = list
              .where((a) => a.status == VerificationStatus.approved)
              .toList();
          final rejected = list
              .where((a) => a.status == VerificationStatus.rejected)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _AdminHeader(
                icon: Icons.auto_awesome,
                title: 'Astrologer Management',
                subtitle: 'Approve, reject and suspend astrologers',
              ),
              const SizedBox(height: 16),
              _SectionLabel('Pending Verification', pending.length,
                  AppColors.warning),
              if (pending.isEmpty)
                _muted('No applications awaiting review.')
              else
                ...pending.map((a) => _AstrologerCard(account: a)),
              const SizedBox(height: 14),
              _SectionLabel('Approved', approved.length, AppColors.success),
              if (approved.isEmpty)
                _muted('No approved astrologers yet.')
              else
                ...approved.map((a) => _AstrologerCard(account: a)),
              if (rejected.isNotEmpty) ...[
                const SizedBox(height: 14),
                _SectionLabel('Rejected', rejected.length, AppColors.error),
                ...rejected.map((a) => _AstrologerCard(account: a)),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

Widget _muted(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(text, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
    );

class _SectionLabel extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SectionLabel(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
}

class _AstrologerCard extends ConsumerWidget {
  final AstrologerAccount account;
  const _AstrologerCard({required this.account});

  /// Maps a raw error to a short, user-facing label per the requested set:
  /// Permission Denied · Connection Error · generic retry.
  String _friendlyError(Object? e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return 'Permission Denied — you cannot perform this action.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Connection Error — please check your network and try again.';
        case 'not-found':
          return 'This astrologer record no longer exists.';
      }
    }
    return 'Could not complete the action. Please try again.';
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String successMsg,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await action();
    final result = ref.read(adminActionsProvider);
    messenger.hideCurrentSnackBar();
    if (result.hasError) {
      messenger.showSnackBar(SnackBar(
        content: Text(_friendlyError(result.error)),
        backgroundColor: AppColors.error,
      ));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(successMsg)));
    }
  }

  Future<void> _confirmReject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Astrologer'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Reason (shown to the astrologer)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    if (!context.mounted) return;
    await _run(
      context,
      ref,
      () => ref
          .read(adminActionsProvider.notifier)
          .rejectAstrologer(account.id, reason: reason),
      'Astrologer rejected.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(adminActionsProvider).isLoading;
    final status = account.status;
    final statusColor = status == VerificationStatus.approved
        ? AppColors.success
        : status == VerificationStatus.rejected
            ? AppColors.error
            : AppColors.warning;
    final location = [account.city, account.state]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: account.photoUrl.isNotEmpty
                    ? NetworkImage(account.photoUrl)
                    : null,
                child: account.photoUrl.isEmpty
                    ? Text(
                        account.fullName.isNotEmpty
                            ? account.fullName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        account.fullName.isEmpty
                            ? '(no name)'
                            : account.fullName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    if (account.expertise.isNotEmpty)
                      Text(account.expertise.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12.5, color: Colors.grey[700])),
                    if (location.isNotEmpty)
                      Text(location,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status.label,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: statusColor,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _detail('Experience', '${account.experienceYears} years'),
          _detail('Languages',
              account.languages.isEmpty ? '—' : account.languages.join(', ')),
          _detail('Fee', '₹${account.consultationFee.toStringAsFixed(0)}'),
          _detail(
              'Certificate',
              account.certName.isEmpty
                  ? '—'
                  : '${account.certName}'
                      '${account.certOrg.isNotEmpty ? ' · ${account.certOrg}' : ''}'),
          const SizedBox(height: 10),
          _actions(context, ref, busy),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref, bool busy) {
    final approve = ElevatedButton.icon(
      onPressed: busy
          ? null
          : () => _run(
                context,
                ref,
                () => ref
                    .read(adminActionsProvider.notifier)
                    .approveAstrologer(account.id),
                'Astrologer approved.',
              ),
      icon: const Icon(Icons.check, size: 18),
      label: const Text('Approve'),
      style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success, foregroundColor: Colors.white),
    );
    final reject = OutlinedButton.icon(
      onPressed: busy ? null : () => _confirmReject(context, ref),
      icon: const Icon(Icons.close, size: 18),
      label: const Text('Reject'),
      style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error)),
    );
    final suspend = OutlinedButton.icon(
      onPressed: busy
          ? null
          : () => _run(
                context,
                ref,
                () => ref
                    .read(adminActionsProvider.notifier)
                    .suspendAstrologer(account.id),
                'Astrologer suspended (moved back to pending).',
              ),
      icon: const Icon(Icons.pause_circle_outline, size: 18),
      label: const Text('Suspend'),
      style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.warning,
          side: const BorderSide(color: AppColors.warning)),
    );

    List<Widget> buttons;
    switch (account.status) {
      case VerificationStatus.pending:
        buttons = [Expanded(child: reject), const SizedBox(width: 10), Expanded(child: approve)];
        break;
      case VerificationStatus.approved:
        buttons = [Expanded(child: suspend)];
        break;
      case VerificationStatus.rejected:
        buttons = [Expanded(child: approve)];
        break;
    }
    return Row(children: buttons);
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 92,
                child: Text(label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12.5))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w500))),
          ],
        ),
      );
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
            child: LoadingState(),
          ),
          error: (e, _) {
            debugPrint('[Admin] analytics stats load failed: $e');
            return const Padding(
              padding: EdgeInsets.all(24),
              child: ErrorStateView(message: 'No analytics data available.'),
            );
          },
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

// ─────────────────────────────────────────────────────────────────────────────
// 🎫 Support Tickets
// ─────────────────────────────────────────────────────────────────────────────

class SupportTicketsScreen extends StatelessWidget {
  const SupportTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] SupportTickets build — /admin/support');
    return _adminScaffold(
      title: 'Support Tickets',
      icon: Icons.support_agent,
      subtitle: 'User help requests and complaints',
      children: [
        _ActionTile(
          icon: Icons.inbox_outlined,
          title: 'Open Tickets',
          subtitle: 'Review and respond to user issues',
          onTap: () => _soon(context, 'Open Tickets'),
        ),
        _ActionTile(
          icon: Icons.done_all,
          title: 'Resolved Tickets',
          subtitle: 'History of closed support requests',
          color: AppColors.success,
          onTap: () => _soon(context, 'Resolved Tickets'),
        ),
      ],
    );
  }
}
