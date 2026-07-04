import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_overview_tab.dart' show SideToggleInline;

/// Family Contacts: separate bride-side and groom-side contact books
/// (name, relationship, mobile, gmail) shared with the whole workspace.
/// [sideFilter] shows a single side only ('bride' / 'groom'); null = both.
class WeddingContactsTab extends ConsumerWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  final String? sideFilter;
  const WeddingContactsTab(
      {super.key,
      required this.wedding,
      required this.identity,
      this.sideFilter});

  static const _relationships = [
    'Father', 'Mother', 'Brother', 'Sister', 'Uncle', 'Others',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(weddingContactsProvider(wedding.id));
    final allContacts = contactsAsync.valueOrNull ?? const <WeddingContact>[];
    final contacts = sideFilter == null
        ? allContacts
        : allContacts.where((c) => c.side == sideFilter).toList();
    final brideSide = contacts.where((c) => c.side == 'bride').toList();
    final groomSide = contacts.where((c) => c.side == 'groom').toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'wedding_contacts_fab',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add Contact'),
        onPressed: () => _showContactSheet(context, ref),
      ),
      body: contactsAsync.isLoading && contacts.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : contacts.isEmpty
              ? _empty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    if (sideFilter != 'groom') ...[
                      _sideSection(context, ref, '👰 Bride Side', brideSide),
                      const SizedBox(height: 16),
                    ],
                    if (sideFilter != 'bride')
                      _sideSection(context, ref, '🤵 Groom Side', groomSide),
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
            Icon(Icons.contacts_outlined, size: 64, color: Colors.grey[350]),
            const SizedBox(height: 14),
            const Text('No family contacts yet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Keep both families\' important contacts (father, mother, '
              'siblings, uncle…) in one shared place.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideSection(BuildContext context, WidgetRef ref, String title,
      List<WeddingContact> contacts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 14.5)),
        const SizedBox(height: 8),
        if (contacts.isEmpty)
          Text('No contacts added.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12.5))
        else
          ...contacts.map((c) => _contactCard(context, ref, c)),
      ],
    );
  }

  Widget _contactCard(BuildContext context, WidgetRef ref, WeddingContact c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c.name} · ${c.relationship}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 3),
                if (c.mobile.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.phone_outlined,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(c.mobile,
                          style: TextStyle(
                              color: Colors.grey[700], fontSize: 12)),
                    ],
                  ),
                if (c.gmail.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.email_outlined,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(c.gmail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 12)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[500]),
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  _showContactSheet(context, ref, existing: c);
                case 'delete':
                  _confirmDelete(context, ref, c);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, WeddingContact c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('"${c.name}" will be removed for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .deleteContact(wedding.id, c.id);
  }

  void _showContactSheet(BuildContext context, WidgetRef ref,
      {WeddingContact? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final mobileCtrl = TextEditingController(text: existing?.mobile ?? '');
    final gmailCtrl = TextEditingController(text: existing?.gmail ?? '');
    String relationship = existing?.relationship ?? 'Father';
    if (!_relationships.contains(relationship)) relationship = 'Others';
    String side = existing?.side ??
        sideFilter ??
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing == null ? 'Add Family Contact' : 'Edit Contact',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 16),
                  SideToggleInline(
                      side: side,
                      onChanged: (v) => setSheetState(() => side = v)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: _input('Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: relationship,
                    decoration: _input('Relationship'),
                    items: _relationships
                        .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => relationship = v ?? 'Others'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: mobileCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: _input('Mobile Number'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a mobile number'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: gmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _input('Gmail (optional)'),
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
                            .saveContact(
                              wedding.id,
                              contactId: existing?.id,
                              side: side,
                              name: nameCtrl.text.trim(),
                              relationship: relationship,
                              mobile: mobileCtrl.text.trim(),
                              gmail: gmailCtrl.text.trim().toLowerCase(),
                              me: identity,
                            );
                        navigator.pop();
                      },
                      child: Text(existing == null ? 'Add Contact' : 'Save'),
                    ),
                  ),
                ],
              ),
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
