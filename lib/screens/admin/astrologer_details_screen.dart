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
                _earningsCard(stats),
              ],
            ),
    );
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
            _row('Pending Requests', '${stats.pending}'),
            _row('Completed Reports', '${stats.completed}'),
          ],
        ),
      );

  Widget _earningsCard(AstrologerStats stats) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _boxDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Earnings (completed only)'),
            const SizedBox(height: 10),
            _row('Total Revenue Generated', '₹${stats.revenue}'),
            _row('Total Commission', '₹${stats.commission}'),
          ],
        ),
      );

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
