import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart' show SideToggleInline;
import 'wedding_workspace_screen.dart' show weddingByLine;

/// Guest List: bride-side and groom-side guest entries that any workspace
/// member can add, edit or delete.
class WeddingGuestsTab extends ConsumerWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const WeddingGuestsTab(
      {super.key, required this.wedding, required this.identity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guestsAsync = ref.watch(weddingGuestsProvider(wedding.id));
    final guests = guestsAsync.valueOrNull ?? const <WeddingGuest>[];
    final brideSide = guests.where((g) => g.side == 'bride').toList();
    final groomSide = guests.where((g) => g.side == 'groom').toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'wedding_guests_fab',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('Add Guest'),
        onPressed: () => _showGuestSheet(context, ref),
      ),
      body: guestsAsync.isLoading && guests.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : guests.isEmpty
              ? _empty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    _countsCard(brideSide.length, groomSide.length),
                    const SizedBox(height: 16),
                    _sideSection(
                        context, ref, '👰 Bride Side Guests', brideSide),
                    const SizedBox(height: 16),
                    _sideSection(
                        context, ref, '🤵 Groom Side Guests', groomSide),
                  ],
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 64, color: Colors.grey[350]),
            const SizedBox(height: 14),
            const Text('No guests added yet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Build the bride-side and groom-side guest lists together — '
              'everyone in the workspace can add, edit and delete entries.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countsCard(int bride, int groom) {
    Widget stat(String label, int count, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: Column(
              children: [
                Text('$count',
                    style: TextStyle(
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        color: color)),
                const SizedBox(height: 2),
                Text(label,
                    style:
                        TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ],
            ),
          ),
        );

    return Row(
      children: [
        stat('Bride Side', bride, AppColors.primary),
        const SizedBox(width: 12),
        stat('Groom Side', groom, Colors.blue),
        const SizedBox(width: 12),
        stat('Total Guests', bride + groom, AppColors.success),
      ],
    );
  }

  Widget _sideSection(BuildContext context, WidgetRef ref, String title,
      List<WeddingGuest> guests) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 14.5)),
        const SizedBox(height: 8),
        if (guests.isEmpty)
          Text('No guests added.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12.5))
        else
          ...guests.map((g) => _guestCard(context, ref, g)),
      ],
    );
  }

  Widget _guestCard(BuildContext context, WidgetRef ref, WeddingGuest g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 20, color: Colors.grey[500]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text(
                  [
                    if (g.phone.isNotEmpty) g.phone,
                    if (g.notes.isNotEmpty) g.notes,
                    'Added by ${weddingByLine(g.addedByName, g.createdAt)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey[600]),
            onPressed: () => _showGuestSheet(context, ref, existing: g),
          ),
          IconButton(
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppColors.error),
            onPressed: () => _confirmDelete(context, ref, g),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, WeddingGuest g) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove guest?'),
        content: Text('"${g.name}" will be removed from the guest list.'),
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
        .deleteGuest(wedding.id, g.id);
  }

  void _showGuestSheet(BuildContext context, WidgetRef ref,
      {WeddingGuest? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String side = existing?.side ??
        (identity.isCouple ? wedding.sideOf(identity.key) : 'bride');
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
                Text(existing == null ? 'Add Guest' : 'Edit Guest',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 16),
                SideToggleInline(
                    side: side, onChanged: (v) => setSheetState(() => side = v)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameCtrl,
                  decoration: _input('Guest Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: _input('Phone (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration: _input('Notes (optional, e.g. family of 4)'),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final navigator = Navigator.of(ctx);
                      await ref
                          .read(weddingControllerProvider.notifier)
                          .saveGuest(
                            wedding.id,
                            guestId: existing?.id,
                            side: side,
                            name: nameCtrl.text.trim(),
                            phone: phoneCtrl.text.trim(),
                            notes: notesCtrl.text.trim(),
                            me: identity,
                          );
                      navigator.pop();
                    },
                    child: Text(existing == null ? 'Add Guest' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
