import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';

/// Workspace Overview: wedding countdown, preparation progress, the
/// Budget Tracker "Coming Soon" tile, and family-member invitations.
class WeddingOverviewTab extends ConsumerWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const WeddingOverviewTab(
      {super.key, required this.wedding, required this.identity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist =
        ref.watch(weddingChecklistProvider(wedding.id)).valueOrNull ??
            const <WeddingChecklistItem>[];
    final total = checklist.length;
    final done = checklist.where((c) => c.isCompleted).length;
    final percent = total == 0 ? 0 : ((done / total) * 100).round();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _coupleCard(),
        const SizedBox(height: 14),
        _countdownCard(context, ref),
        const SizedBox(height: 14),
        _progressCard(total: total, done: done, percent: percent),
        const SizedBox(height: 14),
        _budgetComingSoonCard(),
        const SizedBox(height: 14),
        _familyCard(context, ref),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Couple header ─────────────────────────────────────────────────────────

  Widget _coupleCard() {
    final bride = wedding.coupleIds
        .where((u) => wedding.sideOf(u) == 'bride')
        .map(wedding.nameOf)
        .join();
    final groom = wedding.coupleIds
        .where((u) => wedding.sideOf(u) == 'groom')
        .map(wedding.nameOf)
        .join();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text('💍', style: TextStyle(fontSize: 30)),
          const SizedBox(height: 8),
          Text(
            [
              if (groom.isNotEmpty) groom,
              if (bride.isNotEmpty) bride,
            ].join('  ❤  '),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            wedding.isCompleted ? 'Happily Married 🎉' : 'Marriage Fixed ✓',
            style: TextStyle(
                color: Colors.white.withOpacity(0.85), fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  // ── Wedding countdown ─────────────────────────────────────────────────────

  Widget _countdownCard(BuildContext context, WidgetRef ref) {
    final date = wedding.weddingDate;
    final remaining = wedding.daysRemaining;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_bottom, color: AppColors.goldDark),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Wedding Countdown',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              // Only the couple fixes / changes the wedding date.
              if (identity.isCouple)
                TextButton.icon(
                  onPressed: () => _pickWeddingDate(context, ref),
                  icon: const Icon(Icons.edit_calendar, size: 16),
                  label: Text(date == null ? 'Set Date' : 'Change'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (date == null)
            Text(
              identity.isCouple
                  ? 'Set your wedding date to start the countdown.'
                  : 'The couple has not set the wedding date yet.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _statBox(
                    label: 'Wedding Date',
                    value: '${date.day}/${date.month}/${date.year}',
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statBox(
                    label: 'Remaining Days',
                    value: remaining == null
                        ? '—'
                        : remaining > 0
                            ? '$remaining'
                            : remaining == 0
                                ? 'Today! 🎊'
                                : 'Completed 🎉',
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickWeddingDate(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: wedding.weddingDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Select Wedding Date',
    );
    if (picked == null) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .setWeddingDate(wedding.id, picked);
  }

  // ── Preparation progress ──────────────────────────────────────────────────

  Widget _progressCard(
      {required int total, required int done, required int percent}) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.checklist_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Wedding Preparation',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Text('No checklist tasks yet — add them on the Checklist tab.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13))
          else ...[
            Text('$done / $total Tasks Completed',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.success),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text('$percent%',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Budget Tracker — intentionally NOT implemented yet ───────────────────

  Widget _budgetComingSoonCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: Colors.grey[200], shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('💰', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Wedding Budget Tracker',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        fontFamily: 'Poppins',
                        color: Colors.grey)),
                SizedBox(height: 2),
                Text('Coming Soon',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Coming Soon',
                style: TextStyle(
                    color: AppColors.goldDark,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Family members & invitations ──────────────────────────────────────────

  Widget _familyCard(BuildContext context, WidgetRef ref) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.family_restroom, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Family Members',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              // Only the bride / groom invite family members.
              if (identity.isCouple)
                TextButton.icon(
                  onPressed: () => _showInviteSheet(context, ref),
                  icon: const Icon(Icons.person_add_alt, size: 16),
                  label: const Text('Invite'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (wedding.members.isEmpty)
            Text(
              identity.isCouple
                  ? 'Invite family members by Gmail — they log in as Family '
                      'Users and join this workspace directly.'
                  : 'No family members have been invited yet.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            )
          else
            ...wedding.members.map((m) => _memberTile(context, ref, m)),
        ],
      ),
    );
  }

  Widget _memberTile(BuildContext context, WidgetRef ref, WeddingMember m) {
    final joined = m.status == 'joined';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: (m.side == 'groom'
                    ? Colors.blue
                    : AppColors.primary)
                .withOpacity(0.12),
            child: Text(
              m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: m.side == 'groom' ? Colors.blue : AppColors.primary,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text('${m.sideLabel} · ${m.relationship} · ${m.email}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 11.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (joined ? AppColors.success : AppColors.warning)
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(joined ? 'Joined' : 'Invited',
                style: TextStyle(
                    color: joined ? AppColors.success : AppColors.warning,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold)),
          ),
          if (identity.isCouple)
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
              onPressed: () => _confirmRemoveMember(context, ref, m),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveMember(
      BuildContext context, WidgetRef ref, WeddingMember m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove family member?'),
        content: Text('${m.name} (${m.email}) will lose access to this '
            'Wedding Workspace.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .removeMember(wedding.id, m.email);
  }

  void _showInviteSheet(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String relationship = 'Father';
    String side = identity.isCouple ? wedding.sideOf(identity.key) : 'bride';
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Invite Family Member',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  'They log in with this Gmail as a Family User and directly '
                  'enter this Wedding Workspace.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  decoration: _input('Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: relationship,
                  decoration: _input('Relationship'),
                  items: const [
                    'Father', 'Mother', 'Brother', 'Sister', 'Uncle', 'Others'
                  ]
                      .map((r) =>
                          DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) =>
                      setSheetState(() => relationship = v ?? 'Others'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _input('Gmail'),
                  validator: (v) {
                    final email = (v ?? '').trim().toLowerCase();
                    if (email.isEmpty || !email.contains('@')) {
                      return 'Enter a valid Gmail address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SideToggleInline(
                    side: side,
                    onChanged: (v) => setSheetState(() => side = v)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Send Invitation'),
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx);
                      final ok = await ref
                          .read(weddingControllerProvider.notifier)
                          .inviteMember(
                            wedding.id,
                            WeddingMember(
                              name: nameCtrl.text.trim(),
                              relationship: relationship,
                              email: emailCtrl.text.trim().toLowerCase(),
                              side: side,
                              invitedBy: identity.key,
                            ),
                          );
                      navigator.pop();
                      messenger.showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Invitation sent — ${emailCtrl.text.trim()} '
                                  'can now log in as a Family User.'
                              : 'Could not send the invitation. The Gmail may '
                                  'already be invited.')));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared bits ───────────────────────────────────────────────────────────

  static InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _statBox(
      {required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 17,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: child,
      );
}

/// Bride/Groom side selector used inside form sheets.
class SideToggleInline extends StatelessWidget {
  final String side;
  final ValueChanged<String> onChanged;
  const SideToggleInline(
      {super.key, required this.side, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String value, String label) {
      final active = side == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: active ? AppColors.primary : Colors.grey.shade300),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: active ? AppColors.primary : Colors.grey[600])),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('bride', 'Bride Side'),
        const SizedBox(width: 10),
        chip('groom', 'Groom Side'),
      ],
    );
  }
}
