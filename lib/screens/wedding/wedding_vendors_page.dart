import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';
import 'wedding_workspace_screen.dart' show weddingByLine;

/// VENDOR MANAGEMENT — ONLY the couple (Super Admins) adds, edits or deletes
/// vendors; family members see the vendors shared with them. Supports
/// multiple vendors per category with side-by-side COMPARISON (price,
/// advance, capacity, distance, rating, notes) and a ⭐ Selected (final)
/// vendor per category, recorded in the Decision History.
class WeddingVendorsPage extends StatelessWidget {
  const WeddingVendorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Vendor Management',
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
                  ? 'Add multiple vendors per category (Hall A, Hall B…), '
                      'compare them side by side and select the final one.'
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
    // ⭐ Selected vendor first.
    list.sort((a, b) => (b.isSelected ? 1 : 0) - (a.isSelected ? 1 : 0));
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(category,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppColors.primary)),
            ),
            if (list.length >= 2)
              TextButton.icon(
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.compare_arrows, size: 16),
                label: const Text('Compare'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _VendorComparisonScreen(
                        wedding: wedding,
                        identity: me,
                        category: category))),
              ),
          ],
        ),
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
        border: vendor.isSelected
            ? Border.all(color: AppColors.gold.withOpacity(0.7), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (vendor.isSelected)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('⭐', style: TextStyle(fontSize: 16)),
                ),
              Expanded(
                child: Text(vendor.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              if (vendor.rating > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('★ ${vendor.rating.toStringAsFixed(1)}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.goldDark)),
                ),
              if (me.isCouple)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 20, color: Colors.grey[500]),
                  onSelected: (v) {
                    switch (v) {
                      case 'select':
                        _confirmSelectFinal(vendor);
                      case 'edit':
                        _showVendorSheet(existing: vendor);
                      case 'delete':
                        _confirmDelete(vendor);
                    }
                  },
                  itemBuilder: (_) => [
                    if (!vendor.isSelected)
                      const PopupMenuItem(
                          value: 'select',
                          child: Text('⭐ Select Final Vendor')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                        value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          if (vendor.isSelected)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                'Selected Vendor'
                '${vendor.selectedBy.isNotEmpty ? ' · by ${vendor.selectedBy}' : ''}'
                '${vendor.selectedAt != null ? ' · ${vendor.selectedAt!.day}/${vendor.selectedAt!.month}/${vendor.selectedAt!.year}' : ''}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.goldDark),
              ),
            ),
          if (vendor.contactPerson.isNotEmpty)
            _detailRow(Icons.person_outline, vendor.contactPerson),
          if (vendor.mobile.isNotEmpty)
            _detailRow(Icons.call_outlined, vendor.mobile,
                onTap: () => _dial(vendor.mobile)),
          if (vendor.whatsapp.isNotEmpty)
            _detailRow(Icons.chat_outlined, 'WhatsApp: ${vendor.whatsapp}',
                onTap: () => _whatsapp(vendor.whatsapp)),
          if (vendor.address.isNotEmpty)
            _detailRow(Icons.location_on_outlined, vendor.address),
          // ── Money summary ──
          if (vendor.price != null ||
              vendor.advancePaid > 0 ||
              vendor.balanceAmount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (vendor.price != null)
                  Expanded(child: _money('Price', '₹${vendor.price}')),
                if (vendor.advancePaid > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: _money('Advance', '₹${vendor.advancePaid}')),
                ],
                if (vendor.balanceAmount > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: _money('Balance', '₹${vendor.balanceAmount}')),
                ],
              ],
            ),
          ],
          if (vendor.capacity.isNotEmpty || vendor.distance.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              children: [
                if (vendor.capacity.isNotEmpty)
                  Text('Capacity: ${vendor.capacity}',
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[700])),
                if (vendor.distance.isNotEmpty)
                  Text('Distance: ${vendor.distance}',
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[700])),
              ],
            ),
          ],
          if (vendor.notes.isNotEmpty)
            _detailRow(Icons.sticky_note_2_outlined, vendor.notes),
          // ── Vendor gallery ──
          if (vendor.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 62,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: vendor.photos
                    .map((url) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => showImageGallery(
                                context, vendor.photos,
                                initialIndex: vendor.photos.indexOf(url)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(url,
                                  width: 62, height: 62, fit: BoxFit.cover),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
              'Added by ${weddingByLine(vendor.createdByName, vendor.createdAt)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _money(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        ],
      ),
    );
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

  Future<void> _whatsapp(String number) async {
    final clean = number.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmSelectFinal(WeddingVendor vendor) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select "${vendor.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('This becomes the final ${vendor.category} vendor. Any '
                'previous selection is replaced and recorded in the '
                'Decision History.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder()),
            ),
          ],
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
            child: const Text('⭐ Select'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(weddingControllerProvider.notifier).selectFinalVendor(
        wedding.id, vendor, me,
        reason: reasonCtrl.text.trim());
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
    final whatsappCtrl =
        TextEditingController(text: existing?.whatsapp ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final priceCtrl = TextEditingController(
        text: existing?.price != null ? '${existing!.price}' : '');
    final advanceCtrl = TextEditingController(
        text: (existing?.advancePaid ?? 0) > 0
            ? '${existing!.advancePaid}'
            : '');
    final balanceCtrl = TextEditingController(
        text: (existing?.balanceAmount ?? 0) > 0
            ? '${existing!.balanceAmount}'
            : '');
    final capacityCtrl =
        TextEditingController(text: existing?.capacity ?? '');
    final distanceCtrl =
        TextEditingController(text: existing?.distance ?? '');
    String category = existing?.category ?? WeddingVendor.categories.first;
    double rating = existing?.rating ?? 0;
    final photos = List<String>.of(existing?.photos ?? const []);
    var uploadingPhoto = false;

    final participants = weddingParticipants(wedding);
    final selected = <String>{
      if (existing != null) ...existing.visibleTo else ...wedding.coupleIds,
    };
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
                  Text(existing == null ? 'Add Vendor' : 'Edit Vendor',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Vendor name and phone number are required.',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 11.5)),
                  const SizedBox(height: 14),
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
                    decoration: _input('Vendor Name *'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter the vendor name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: mobileCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: _input('Phone Number *'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter the phone number'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                            controller: whatsappCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _input('WhatsApp (optional)')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: contactCtrl,
                      decoration: _input('Contact Person (optional)')),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: addressCtrl,
                      maxLines: 2,
                      decoration: _input('Address (optional)')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                            controller: priceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _input('Price ₹')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                            controller: advanceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _input('Advance ₹')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                            controller: balanceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _input('Balance ₹')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                            controller: capacityCtrl,
                            decoration:
                                _input('Capacity (e.g. 500 seats)')),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                            controller: distanceCtrl,
                            decoration: _input('Distance (e.g. 4 km)')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: _input('Notes (optional)')),
                  const SizedBox(height: 14),
                  // ── Rating ──
                  Row(
                    children: [
                      Text('Rating',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700])),
                      const SizedBox(width: 12),
                      ...List.generate(5, (i) {
                        final filled = rating >= i + 1;
                        return IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          icon: Icon(
                              filled ? Icons.star : Icons.star_border,
                              color: AppColors.goldDark,
                              size: 24),
                          onPressed: () => setSheetState(() =>
                              rating = rating == i + 1 ? 0 : (i + 1).toDouble()),
                        );
                      }),
                    ],
                  ),
                  // ── Vendor gallery ──
                  Row(
                    children: [
                      Text('Vendor Photos',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700])),
                      const SizedBox(width: 8),
                      if (photos.isNotEmpty)
                        Text('${photos.length}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                      const Spacer(),
                      TextButton.icon(
                        icon: uploadingPhoto
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.add_photo_alternate_outlined,
                                size: 16),
                        label: Text(uploadingPhoto ? 'Uploading…' : 'Add'),
                        onPressed: uploadingPhoto
                            ? null
                            : () async {
                                final x = await ImagePicker().pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 80);
                                if (x == null) return;
                                setSheetState(() => uploadingPhoto = true);
                                final url = await ref
                                    .read(
                                        weddingControllerProvider.notifier)
                                    .uploadVendorPhoto(
                                        wedding.id, File(x.path));
                                setSheetState(() {
                                  uploadingPhoto = false;
                                  if (url != null) photos.add(url);
                                });
                              },
                      ),
                    ],
                  ),
                  if (photos.isNotEmpty)
                    SizedBox(
                      height: 56,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: photos
                            .map((url) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        child: Image.network(url,
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover),
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: GestureDetector(
                                          onTap: () => setSheetState(
                                              () => photos.remove(url)),
                                          child: Container(
                                            decoration: const BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle),
                                            child: const Icon(Icons.close,
                                                size: 14,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  // ── Visibility ──
                  const Text('Who can view this vendor?',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text(
                    'Only the selected people see this vendor. Family '
                    'members can never add or edit vendors.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                  ),
                  const SizedBox(height: 6),
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
                  const SizedBox(height: 12),
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
                              whatsapp: whatsappCtrl.text.trim(),
                              address: addressCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                              price:
                                  num.tryParse(priceCtrl.text.trim()),
                              advancePaid: num.tryParse(
                                      advanceCtrl.text.trim()) ??
                                  0,
                              balanceAmount: num.tryParse(
                                      balanceCtrl.text.trim()) ??
                                  0,
                              capacity: capacityCtrl.text.trim(),
                              distance: distanceCtrl.text.trim(),
                              rating: rating,
                              photos: photos,
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

// ── Vendor comparison ─────────────────────────────────────────────────────────

/// Side-by-side comparison of every vendor in one category (price, advance,
/// capacity, distance, rating, notes) with "Select Final Vendor".
class _VendorComparisonScreen extends ConsumerWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  final String category;
  const _VendorComparisonScreen(
      {required this.wedding,
      required this.identity,
      required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(weddingVendorsProvider(wedding.id)).valueOrNull ??
        const <WeddingVendor>[];
    final vendors = (identity.isCouple
            ? all
            : all.where((v) => v.visibleToKey(identity.key)))
        .where((v) => v.category == category)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text('Compare — $category'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: vendors.length < 2
          ? Center(
              child: Text('Add at least two $category vendors to compare.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      vendors.map((v) => _column(context, ref, v)).toList(),
                ),
              ),
            ),
    );
  }

  Widget _column(BuildContext context, WidgetRef ref, WeddingVendor v) {
    return Container(
      width: 190,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: v.isSelected
            ? Border.all(color: AppColors.gold, width: 1.5)
            : Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${v.isSelected ? '⭐ ' : ''}${v.name}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 10),
          _row('Price', v.price != null ? '₹${v.price}' : '—'),
          _row('Advance', v.advancePaid > 0 ? '₹${v.advancePaid}' : '—'),
          _row('Balance', v.balanceAmount > 0 ? '₹${v.balanceAmount}' : '—'),
          _row('Capacity', v.capacity.isEmpty ? '—' : v.capacity),
          _row('Distance', v.distance.isEmpty ? '—' : v.distance),
          _row('Rating',
              v.rating > 0 ? '★ ${v.rating.toStringAsFixed(1)}' : '—'),
          _row('Phone', v.mobile.isEmpty ? '—' : v.mobile),
          const SizedBox(height: 6),
          Text('Notes',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[500])),
          Text(v.notes.isEmpty ? '—' : v.notes,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5)),
          const SizedBox(height: 12),
          if (identity.isCouple)
            SizedBox(
              width: double.infinity,
              child: v.isSelected
                  ? Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('⭐ Selected Vendor',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.goldDark)),
                    )
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact),
                      onPressed: () async {
                        await ref
                            .read(weddingControllerProvider.notifier)
                            .selectFinalVendor(wedding.id, v, identity);
                      },
                      child: const Text('Select Final',
                          style: TextStyle(fontSize: 12)),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
