import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../models/astrologer_team_member.dart';
import '../../../providers/astrology_team_provider.dart';
import '../../../providers/astrology_team_stats_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/service_providers.dart';

/// The astrologer portal shell (spec §3/§4). A bottom navigation with five
/// destinations — Dashboard · Pending · In Progress · Completed · Profile —
/// each a separate page (no top tabs). The Dashboard is the landing page.
class AstrologerShell extends ConsumerStatefulWidget {
  const AstrologerShell({super.key});

  @override
  ConsumerState<AstrologerShell> createState() => _AstrologerShellState();
}

class _AstrologerShellState extends ConsumerState<AstrologerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final requests =
        ref.watch(myAssignedRequestsProvider).valueOrNull ?? const [];
    // Only two states now (spec §4): Pending = every assigned report not yet
    // completed; Completed = submitted reports. No "Start" / In-Progress step.
    final pending = requests
        .where((r) => r.status != AstrologerRequestStatus.completed)
        .toList();
    final completed = requests
        .where((r) => r.status == AstrologerRequestStatus.completed)
        .toList();

    final titles = [
      'Dashboard',
      'Pending',
      'Completed',
      'Work Report',
      'Profile'
    ];

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(titles[_index]),
        automaticallyImplyLeading: false,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const _DashboardPage(),
          _RequestsPage(
              requests: pending,
              emptyIcon: Icons.inbox_outlined,
              emptyText: 'No pending reports',
              trailing: 'Open'),
          _RequestsPage(
              requests: completed,
              emptyIcon: Icons.verified_outlined,
              emptyText: 'No completed reports yet',
              trailing: 'View'),
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
              icon: _badge(Icons.assignment_outlined, pending.length),
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

class _DashboardPage extends StatelessWidget {
  const _DashboardPage();

  // Intentionally an empty placeholder for now (spec §4) — the Employee
  // Dashboard will be built later. Employees use the Pending / Completed tabs.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize_outlined,
                size: 64, color: AppColors.primary.withOpacity(0.3)),
            const SizedBox(height: 14),
            const Text('Dashboard coming soon',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Your reports are in the Pending and Completed tabs below.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Requests list page (Pending / In Progress / Completed) ───────────────────

class _RequestsPage extends StatelessWidget {
  final List<AstrologerRequestModel> requests;
  final IconData emptyIcon;
  final String emptyText;
  final String trailing;
  const _RequestsPage({
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
            onTap: () => context.push('/astrologer-request/${r.id}', extra: r),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
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
        );
      },
    );
  }
}

// ── Work Report page (spec §14/§15) ─────────────────────────────────────────

class _WorkReportPage extends ConsumerWidget {
  const _WorkReportPage();

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(myAstrologerStatsProvider);
    final requests =
        ref.watch(myAssignedRequestsProvider).valueOrNull ?? const [];
    if (s == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    final recentCompleted = requests
        .where((r) => r.status == AstrologerRequestStatus.completed)
        .toList()
      ..sort((a, b) =>
          (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Weekly summary (spec §15).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This Week',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _wk('Assigned', s.thisWeek.assigned),
                  _wk('Completed', s.thisWeek.completed),
                  _wk('Pending', s.thisWeek.pending),
                  _wk('Rate', s.thisWeek.completionRate, suffix: '%'),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                  'Weekly commission: ₹${s.weeklyCommission}  '
                  '(${s.thisWeek.completed} × ₹${s.commissionPerReport})',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Commission earnings (spec §Employee Statistics).
        _reportCard('Commission', [
          _r('Commission Per Report', s.commissionPerReport),
          _r('Weekly Commission', s.weeklyCommission),
          _r('Monthly Commission', s.monthlyCommission),
          _r('Total Earned', s.totalCommission),
          _r('Paid', s.paidCommission),
          _r('Pending Payment', s.pendingCommission),
        ]),
        const SizedBox(height: 12),
        _reportCard('Today', [
          _r('New Requests', s.todayAssigned),
          _r('In Progress', s.inProgress),
          _r('Completed Today', s.todayCompleted),
        ]),
        const SizedBox(height: 12),
        _reportCard('Last Week', [
          _r('Assigned', s.lastWeek.assigned),
          _r('Completed', s.lastWeek.completed),
          _r('Pending', s.lastWeek.pending),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Recent Completed Reports',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 8),
              if (recentCompleted.isEmpty)
                Text('No completed reports yet.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13))
              else
                for (final r in recentCompleted.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(r.userName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Text(_date(r.completedAt),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

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

  Widget _r(String k, int v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            Text('$v',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      );
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
    final m = ref.watch(myAstrologerTeamMemberProvider).valueOrNull;
    if (m == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
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
