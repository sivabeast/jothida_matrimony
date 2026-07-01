import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/astrology_team_stats_provider.dart';
import '../../providers/service_providers.dart';

/// Admin → Astrologer Details (spec §5). Shows the astrologer's profile +
/// live performance (assigned / pending / completed / revenue / commission /
/// joined date / active status) and lets the admin enable/disable + edit them.
class AstrologerDetailsScreen extends ConsumerWidget {
  /// Registry id (the lowercased Gmail / emailKey).
  final String emailKey;
  const AstrologerDetailsScreen({super.key, required this.emailKey});

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(astrologerStatsByIdProvider(emailKey));
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Astrologer Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (stats != null)
            IconButton(
              tooltip: 'Edit details',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editDialog(context, ref, stats),
            ),
        ],
      ),
      body: stats == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _profileCard(context, ref, stats),
                const SizedBox(height: 14),
                _performanceCard(stats),
                const SizedBox(height: 14),
                _salaryCard(context, ref, stats),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => _deleteAstrologer(context, ref, stats),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete Astrologer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _deleteAstrologer(
      BuildContext context, WidgetRef ref, AstrologerStats stats) async {
    final unfinished = stats.pending + stats.inProgress;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete astrologer?'),
        content: Text(unfinished > 0
            ? 'This removes the astrologer. Their $unfinished unfinished '
                'request(s) will be automatically reassigned to another active '
                'astrologer. This cannot be undone.'
            : 'This removes the astrologer. This cannot be undone.'),
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
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ref
          .read(astrologyTeamServiceProvider)
          .deleteMemberAndReassign(stats.member);
      messenger.showSnackBar(const SnackBar(
          content: Text('Astrologer deleted and requests reassigned.')));
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  Widget _profileCard(
      BuildContext context, WidgetRef ref, AstrologerStats stats) {
    final m = stats.member;
    final statusColor = !m.active
        ? Colors.red
        : (m.isLinked ? Colors.green : Colors.orange);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration,
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            backgroundImage:
                m.photoUrl.isNotEmpty ? NetworkImage(m.photoUrl) : null,
            child: m.photoUrl.isEmpty
                ? const Icon(Icons.person, color: AppColors.primary, size: 40)
                : null,
          ),
          const SizedBox(height: 10),
          Text(m.displayName.isEmpty ? m.email : m.displayName,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(m.email, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(m.statusLabel,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: statusColor)),
          ),
          const Divider(height: 24),
          _row('Joined', _date(m.createdAt)),
          _row('Last sign-in', _date(m.lastLoginAt)),
          _row('Availability', m.available ? 'Available' : 'Unavailable'),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: m.active,
            activeColor: AppColors.primary,
            title: Text(m.active ? 'Account enabled' : 'Account disabled'),
            subtitle: Text(m.active
                ? 'Receives new auto-assigned requests.'
                : 'Excluded from login and new assignments.'),
            onChanged: (v) =>
                ref.read(astrologyTeamServiceProvider).setActive(m.id, v),
          ),
        ],
      ),
    );
  }

  Widget _performanceCard(AstrologerStats stats) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _boxDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Performance'),
            const SizedBox(height: 10),
            _row('Assigned Requests', '${stats.totalAssigned}'),
            _row('New / Pending', '${stats.pending}'),
            _row('In Progress', '${stats.inProgress}'),
            _row('Completed Reports', '${stats.completed}'),
            const Divider(height: 20),
            _row('This Week — Assigned', '${stats.thisWeek.assigned}'),
            _row('This Week — Completed', '${stats.thisWeek.completed}'),
            _row('This Week — Pending', '${stats.thisWeek.pending}'),
            const Divider(height: 20),
            _row('Last Week — Assigned', '${stats.lastWeek.assigned}'),
            _row('Last Week — Completed', '${stats.lastWeek.completed}'),
            _row('Last Week — Pending', '${stats.lastWeek.pending}'),
            const Divider(height: 20),
            _row('Last Login', _date(stats.member.lastLoginAt)),
            _row('Last Submitted Report', _date(stats.member.lastSubmittedAt)),
          ],
        ),
      );

  Widget _salaryCard(
          BuildContext context, WidgetRef ref, AstrologerStats stats) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: _boxDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Weekly Salary'),
            const SizedBox(height: 10),
            _row('Weekly Salary', '₹${stats.member.weeklySalary}'),
            _row('Salary Status',
                stats.member.salaryStatus == 'paid' ? 'Paid' : 'Pending'),
            _row('Last Paid', _date(stats.member.lastPaidDate)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editSalary(context, ref, stats),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Set Salary'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => ref
                        .read(astrologyTeamServiceProvider)
                        .setSalary(stats.member.id, markPaid: true),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Mark Paid'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> _editSalary(
      BuildContext context, WidgetRef ref, AstrologerStats stats) async {
    final ctrl =
        TextEditingController(text: '${stats.member.weeklySalary}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Weekly Salary'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Weekly salary (₹)', prefixText: '₹ '),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final amount = int.tryParse(ctrl.text.trim()) ?? 0;
      await ref
          .read(astrologyTeamServiceProvider)
          .setSalary(stats.member.id, weeklySalary: amount, salaryStatus: 'pending');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Weekly salary updated.')));
      }
    }
  }

  Future<void> _editDialog(
      BuildContext context, WidgetRef ref, AstrologerStats stats) async {
    final nameCtrl = TextEditingController(text: stats.member.displayName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Astrologer'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref
            .read(astrologyTeamServiceProvider)
            .updateMember(stats.member.id, {'displayName': nameCtrl.text.trim()});
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Astrologer details updated.')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not update: $e')));
        }
      }
    }
  }

  static final _boxDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
  );

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 15,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.bold,
          color: AppColors.primary));

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(fontSize: 13.5, color: Colors.grey[700])),
            Text(v,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
