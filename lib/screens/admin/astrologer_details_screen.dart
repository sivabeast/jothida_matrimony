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
        title: const Text('Employee Details'),
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
                _commissionCard(context, ref, stats),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => _deleteAstrologer(context, ref, stats),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete Employee'),
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
        title: const Text('Delete employee?'),
        content: Text(unfinished > 0
            ? 'This removes the employee. Their $unfinished unfinished '
                'report(s) will be automatically reassigned to another active '
                'employee. This cannot be undone.'
            : 'This removes the employee. This cannot be undone.'),
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

  Widget _commissionCard(
          BuildContext context, WidgetRef ref, AstrologerStats stats) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: _boxDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Weekly Payroll'),
            const SizedBox(height: 10),
            _row('Commission Per Report', '₹${stats.commissionPerReport}'),
            _row('Reports This Cycle', '${stats.cycleCompleted}'),
            _row('This Week Commission', '₹${stats.cycleCommission}'),
            _row('Total Earned (all-time)', '₹${stats.totalCommission}'),
            _row('Total Paid', '₹${stats.paidCommission}'),
            _row('Last Payment', _date(stats.member.lastPaidDate)),
            _row('Payment Status', stats.paymentStatusLabel),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: stats.cycleCommission <= 0
                    ? null
                    : () => _markPaid(context, ref, stats),
                icon: const Icon(Icons.task_alt, size: 16),
                label: Text(stats.cycleCommission <= 0
                    ? 'Nothing Due This Week'
                    : 'Mark As Paid · ₹${stats.cycleCommission}'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44)),
              ),
            ),
          ],
        ),
      );

  /// Closes the employee's current payroll cycle (records the payout in
  /// `payroll_payments`) — the next week restarts from ₹0.
  Future<void> _markPaid(
      BuildContext context, WidgetRef ref, AstrologerStats stats) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark As Paid'),
        content: Text('Pay ₹${stats.cycleCommission} for '
            '${stats.cycleCompleted} completed report(s)? The next week '
            'starts again from ₹0.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark As Paid'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(astrologyTeamServiceProvider).markPayrollPaid(
          stats.member,
          amount: stats.cycleCommission,
          reportsCount: stats.cycleCompleted,
          ratePerReport: stats.commissionPerReport,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weekly payroll closed and recorded.')));
    }
  }

  Future<void> _editDialog(
      BuildContext context, WidgetRef ref, AstrologerStats stats) async {
    final nameCtrl = TextEditingController(text: stats.member.displayName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Employee'),
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
