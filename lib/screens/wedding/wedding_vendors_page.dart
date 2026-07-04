import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';
import 'wedding_workspace_screen.dart' show weddingByLine;

/// Vendor Management — ONLY the couple (bride & groom) can add, edit or
/// delete vendors; family members never manage them. While creating a
/// vendor the couple selects EXACTLY who can view it (per-participant
/// visibility) — everyone else simply doesn't see that vendor.
class WeddingVendorsPage extends StatelessWidget {
  const WeddingVendorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Vendors',
      builder: (_, __, wedding, identity) =>
          _VendorsBody(wedding: wedding, identity: identity),
    );
  }
}

class _VendorsBody extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const _VendorsBody({required this.wedding, required this.identity});

  @override
  ConsumerState<_VendorsBody> createState() => _VendorsBodyState();
}

class _VendorsBodyState extends ConsumerState<_VendorsBody> {
  WeddingModel get wedding => widget.wedding;
  WeddingIdentity get me => widget.identity;

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(weddingVendorsProvider(wedding.id));
    final all = vendorsAsync.valueOrNull ?? const <WeddingVendor>[];
    // The couple manages vendors, so they see every vendor. A family member
    // sees ONLY the vendors whose visibility list includes them.
    final vendors =
        me.isCouple ? all : all.where((v) => v.visibleToKey(me.key)).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: me.isCouple
          ? FloatingActionButton.extended(
              heroTag: 'wedding_vendors_fab',
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add Vendor'),
              onPressed: () => _showVendorSheet(),
            )
          : null,
      body: vendorsAsync.isLoading && all.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : vendors.isEmpty
              ? _empty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    for (final category in WeddingVendor.categories)
                      ..._categorySection(
                          category,
                          vendors
                              .where((v) => v.category == category)
                              .toList()),
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
            Icon(Icons.storefront_outlined, size: 64, color: Colors.grey[350]),
            const SizedBox(height: 14),
            Text(me.isCouple ? 'No vendors yet' : 'No vendors shared with you',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              me.isCouple
                  ? 'Keep every wedding vendor in one place — hall, '
                      'photographer, decorator, catering and more. You choose '
                      'exactly who can see each vendor.'
                  : 'The Bride or Groom hasn\'t shared any vendors with you '
                      'yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _categorySection(String category, List<WeddingVendor> list) {
    if (list.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
        child: Text(category,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                color: AppColors.primary)),
      ),
      ...list.map(_vendorCard),
    ];
  }

  Widget _vendorCard(WeddingVendor vendor) {
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
            children: [
              Expanded(
                child: Text(vendor.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              if (me.isCouple)
                PopupMenuButton<String>(
                  icon:
                      Icon(Icons.more_vert, size: 20, color: Colors.grey[500]),
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        _showVendorSheet(existing: vendor);
                      case 'delete':
                        _confirmDelete(vendor);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          if (vendor.contactPerson.isNotEmpty)
            _detailRow(Icons.person_outline, vendor.contactPerson),
          if (vendor.mobile.isNotEmpty)
            _detailRow(Icons.call_outlined, vendor.mobile,
                onTap: () => _dial(vendor.mobile)),
          if (vendor.altMobile.isNotEmpty)
            _detailRow(Icons.call_outlined, '${vendor.altMobile} (alt)',
                onTap: () => _dial(vendor.altMobile)),
          if (vendor.address.isNotEmpty)
            _detailRow(Icons.location_on_outlined, vendor.address),
          if (vendor.notes.isNotEmpty)
            _detailRow(Icons.sticky_note_2_outlined, vendor.notes),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                    'Added by ${weddingByLine(vendor.createdByName, vendor.createdAt)}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 10.5)),
              ),
              if (me.isCouple)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '👁 ${_visibilitySummary(vendor)}',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _visibilitySummary(WeddingVendor vendor) {
    final participants = weddingParticipants(wedding);
    final visible = participants
        .where((p) => vendor.visibleToKey(p.key))
        .map((p) => p.name)
        .toList();
    if (visible.isEmpty) return 'Only Bride & Groom';
    if (visible.length <= 2) return visible.join(', ');
    return '${visible.take(2).join(', ')} +${visible.length - 2}';
  }

  Widget _detailRow(IconData icon, String text, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: Colors.grey[500]),
            const SizedBox(width: 7),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: onTap != null
                          ? AppColors.primary
                          : Colors.grey[700],
                      decoration:
                          onTap != null ? TextDecoration.underline : null,
                      decorationColor: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _confirmDelete(WeddingVendor vendor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vendor?'),
        content: Text('"${vendor.name}" will be removed.'),
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
        .deleteVendor(wedding.id, vendor.id);
  }

  // ── Add / edit sheet (couple only) ────────────────────────────────────────

  void _showVendorSheet({WeddingVendor? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final contactCtrl =
        TextEditingController(text: existing?.contactPerson ?? '');
    final mobileCtrl = TextEditingController(text: existing?.mobile ?? '');
    final altMobileCtrl =
        TextEditingController(text: existing?.altMobile ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String category = existing?.category ?? WeddingVendor.categories.first;
    final formKey = GlobalKey<FormState>();

    // Visibility selection — participant keys. New vendors default to the
    // couple only; edits start from the stored list.
    final participants = weddingParticipants(wedding);
    final selected = <String>{
      if (existing != null)
        ...existing.visibleTo
      else
        ...wedding.coupleIds,
    };

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
                  Text(existing == null ? 'Add Vendor' : 'Edit Vendor',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: _input('Category'),
                    items: WeddingVendor.categories
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => category = v ?? category),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: _input('Vendor Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter the vendor name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: contactCtrl,
                      decoration: _input('Contact Person (optional)')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                            controller: mobileCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _input('Mobile')),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                            controller: altMobileCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _input('Alternate Mobile')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: addressCtrl,
                      maxLines: 2,
                      decoration: _input('Address (optional)')),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: _input('Notes (optional)')),
                  const SizedBox(height: 16),

                  // ── Who can view this vendor? ──
                  const Text('Who can view this vendor?',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text(
                    'Only the selected people see this vendor. Family '
                    'members can never add or edit vendors.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                  ),
                  const SizedBox(height: 8),
                  ...participants.map((p) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.primary,
                        value: selected.contains(p.key),
                        title: Text(p.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(p.roleLabel,
                            style: const TextStyle(fontSize: 11)),
                        onChanged: (v) => setSheetState(() {
                          if (v == true) {
                            selected.add(p.key);
                          } else {
                            selected.remove(p.key);
                          }
                        }),
                      )),
                  const SizedBox(height: 14),
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
                            .saveVendor(
                              wedding.id,
                              vendorId: existing?.id,
                              category: category,
                              name: nameCtrl.text.trim(),
                              contactPerson: contactCtrl.text.trim(),
                              mobile: mobileCtrl.text.trim(),
                              altMobile: altMobileCtrl.text.trim(),
                              address: addressCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                              visibleTo: selected.toList(),
                              me: me,
                            );
                        navigator.pop();
                      },
                      child: Text(
                          existing == null ? 'Add Vendor' : 'Save Changes'),
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
