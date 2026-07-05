import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_contacts_tab.dart';
import 'wedding_guests_tab.dart';

/// Resolves the LIVE wedding + the signed-in participant's identity and
/// hosts a workspace sub-page under its own AppBar. Every page pushed from
/// the workspace shell goes through this, so content stays live (e.g. a
/// member invited while the page is open) and a cancelled wedding safely
/// collapses into a message instead of a crash.
class WeddingPageScaffold extends ConsumerWidget {
  final String title;
  final Widget Function(BuildContext context, WidgetRef ref,
      WeddingModel wedding, WeddingIdentity identity) builder;

  const WeddingPageScaffold(
      {super.key, required this.title, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weddingAsync = ref.watch(activeWeddingProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: weddingAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _message('Could not load this page.\n$e'),
        data: (wedding) {
          if (wedding == null || !wedding.isFixed) {
            return _message('This Wedding Workspace is no longer available.');
          }
          final identity = ref.watch(weddingIdentityProvider(wedding));
          if (identity == null) {
            return _message("You don't have access.");
          }
          return builder(context, ref, wedding, identity);
        },
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13.5)),
        ),
      );
}

// ── Simple wrapped pages ──────────────────────────────────────────────────────

/// Family Contacts page. [sideFilter] narrows to one side; [sharedOnly]
/// shows ONLY contacts that were moved to Shared (menu → Shared Contacts).
class WeddingContactsPage extends StatelessWidget {
  final String? sideFilter;
  final bool sharedOnly;
  const WeddingContactsPage(
      {super.key, required this.sideFilter, this.sharedOnly = false});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: sharedOnly
          ? 'Shared Contacts'
          : switch (sideFilter) {
              'bride' => 'Bride Contacts',
              'groom' => 'Groom Contacts',
              _ => 'Family Contacts',
            },
      builder: (_, __, wedding, identity) => WeddingContactsTab(
          wedding: wedding,
          identity: identity,
          sideFilter: sideFilter,
          sharedOnly: sharedOnly),
    );
  }
}

class WeddingGuestsPage extends StatelessWidget {
  const WeddingGuestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Guest List',
      builder: (_, __, wedding, identity) =>
          WeddingGuestsTab(wedding: wedding, identity: identity),
    );
  }
}

// ── Settings (wedding date · postpone · cancel) ───────────────────────────────

/// Workspace Settings. The couple manages the wedding date and the two
/// separate lifecycle actions:
///   • POSTPONE — the wedding is delayed: status becomes Postponed, ONLY the
///     date changes, every workspace module stays active;
///   • CANCEL — the wedding is permanently cancelled: after an explicit
///     warning, the whole workspace and ALL its data are deleted.
class WeddingSettingsPage extends ConsumerWidget {
  const WeddingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WeddingPageScaffold(
      title: 'Workspace Settings',
      builder: (context, ref, wedding, identity) {
        final date = wedding.weddingDate;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(wedding),
            const SizedBox(height: 14),
            if (identity.isCouple) ...[
              _actionCard(
                icon: Icons.edit_calendar,
                color: AppColors.primary,
                title: date == null ? 'Set Wedding Date' : 'Change Wedding Date',
                subtitle: date == null
                    ? 'Fix the wedding date to start the countdown.'
                    : 'Current date: ${date.day}/${date.month}/${date.year}',
                onTap: () => _pickDate(context, ref, wedding),
              ),
              const SizedBox(height: 14),
              _actionCard(
                icon: Icons.update,
                color: AppColors.warning,
                title: 'Postpone Wedding',
                subtitle: 'The wedding is delayed. Everything stays active — '
                    'tasks, galleries, vendors, chat, guests and contacts. '
                    'Only the wedding date changes.',
                onTap: () => _postpone(context, ref, wedding),
              ),
              const SizedBox(height: 14),
              _actionCard(
                icon: Icons.cancel_outlined,
                color: AppColors.error,
                title: 'Cancel Marriage',
                subtitle: 'The wedding is permanently cancelled. The whole '
                    'Wedding Workspace and all its data are deleted.',
                onTap: () => _cancel(context, ref, wedding),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Only the Bride and Groom can change the wedding date, '
                  'postpone the wedding or cancel the marriage.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _statusCard(WeddingModel wedding) {
    final (label, color) = wedding.isCompleted
        ? ('Completed 🎉', AppColors.success)
        : wedding.isPostponed
            ? ('Postponed', AppColors.warning)
            : ('Marriage Fixed ✓', AppColors.success);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Text('💍', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Wedding Status',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: color)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(
      BuildContext context, WidgetRef ref, WeddingModel wedding) async {
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

  // ── Postpone (everything stays, only the date changes) ────────────────────

  Future<void> _postpone(
      BuildContext context, WidgetRef ref, WeddingModel wedding) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Postpone Wedding'),
        content: const Text(
            'The wedding status becomes "Postponed". Your tasks, galleries, '
            'vendors, family chat, guest list and family contacts all remain '
            'active — only the wedding date changes.\n\n'
            'Pick the new date now, or decide it later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Back')),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: const Text('Decide Date Later'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, 'pick'),
            child: const Text('Pick New Date'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    DateTime? newDate;
    if (choice == 'pick') {
      final now = DateTime.now();
      newDate = await showDatePicker(
        context: context,
        initialDate:
            wedding.weddingDate ?? now.add(const Duration(days: 60)),
        firstDate: now,
        lastDate: DateTime(now.year + 3),
        helpText: 'Select the new Wedding Date',
      );
      if (newDate == null) return; // picker dismissed → no change
    }
    if (!context.mounted) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .postponeWedding(wedding.id, newDate);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newDate == null
            ? 'Wedding postponed — set the new date when it is decided.'
            : 'Wedding postponed to '
                '${newDate.day}/${newDate.month}/${newDate.year}.')));
  }

  // ── Cancel (permanent, deletes everything) ────────────────────────────────

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, WeddingModel wedding) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Marriage?'),
        content: const Text(
            'This action will permanently remove all Wedding Workspace '
            'data.\n\nThe workspace, tasks, galleries, vendors, expenses, '
            'calendar, notes, guest list, family contacts and family chat '
            'will ALL be deleted for everyone. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Wedding')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Marriage'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(weddingControllerProvider.notifier)
        .cancelWedding(wedding.id);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not cancel the marriage — please try again.')));
      return;
    }
    // Back to the matrimony experience — the workspace no longer exists.
    ref.read(entryModeProvider.notifier).state = WeddingEntryMode.matrimony;
    await WeddingEntryMode.save(WeddingEntryMode.matrimony);
    messenger.showSnackBar(const SnackBar(
        content:
            Text('Marriage cancelled — all Wedding Workspace data removed.')));
    router.go('/home');
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

/// Bride/Groom side selector used inside form sheets (contacts, guests,
/// family invitations).
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
