import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_account_model.dart';
import '../../../models/astrologer_model.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../astrologer_edit_profile_screen.dart';
import 'astrologer_common.dart';

/// The astrologer's own profile: identity, aggregate rating, professional
/// details, and full management of the services they offer. Reviewer identities
/// are never shown here — only the aggregate rating and review count.
class AstrologerProfileTab extends ConsumerWidget {
  const AstrologerProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAstrologerAccountProvider);
    if (account == null) return const AstrologerLoading();

    final location = [account.city, account.state, account.country]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        // ── Identity + aggregate rating ─────────────────────────────────
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: account.photoUrl.isNotEmpty
                    ? NetworkImage(account.photoUrl)
                    : null,
                child: account.photoUrl.isEmpty
                    ? const Icon(Icons.person,
                        size: 46, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(account.fullName,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              _ratingPill(account),
              const SizedBox(height: 6),
              Text(account.status.label,
                  style: TextStyle(
                      color: account.isApproved
                          ? AppColors.success
                          : AppColors.warning,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // ── Professional details ────────────────────────────────────────
        AstrologerCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              _info('Experience', '${account.experienceYears} years'),
              _info('Languages', account.languages.join(', ')),
              _info('Location', location),
              _info('Consultation Fee',
                  '₹${account.consultationFee.toStringAsFixed(0)}'),
              _info('Consultation', account.consultationModes.join(', ')),
              _info('Specializations', account.expertise.join(', ')),
              _info('About Me', account.about, last: true),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AstrologerEditProfileScreen(),
            ),
          ),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit Profile'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
        // ── Services management ─────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const AstrologerSectionTitle('My Services'),
            TextButton.icon(
              onPressed: () => _addOrEditService(context, ref, account),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        if (account.services.isEmpty)
          const AstrologerCard(
            child: Text('No services yet. Tap “Add” to create one.',
                style: TextStyle(color: Colors.grey)),
          )
        else
          ...account.services.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ServiceCard(
                    service: e.value,
                    onEdit: () =>
                        _addOrEditService(context, ref, account, index: e.key),
                    onDelete: () =>
                        _deleteService(context, ref, account, e.key),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _ratingPill(AstrologerAccount account) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 16, color: AppColors.gold),
            const SizedBox(width: 4),
            Text(account.rating.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text('· ${account.reviewCount} Reviews',
                style: TextStyle(color: Colors.grey[700], fontSize: 12.5)),
          ],
        ),
      );

  Widget _info(String label, String value, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text(label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13))),
            Expanded(
                child: Text(value.isEmpty ? '—' : value,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );

  Future<void> _addOrEditService(
    BuildContext context,
    WidgetRef ref,
    AstrologerAccount account, {
    int? index,
  }) async {
    final result = await showModalBottomSheet<AstrologerService>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ServiceSheet(
        initial: index != null ? account.services[index] : null,
      ),
    );
    if (result == null) return;

    final services = [...account.services];
    if (index != null) {
      services[index] = result;
    } else {
      services.add(result);
    }
    await _persist(context, ref, services,
        message: index != null ? 'Service updated' : 'Service added');
  }

  Future<void> _deleteService(
    BuildContext context,
    WidgetRef ref,
    AstrologerAccount account,
    int index,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service'),
        content: Text(
            'Remove “${account.services[index].name}” from your services?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final services = [...account.services]..removeAt(index);
    await _persist(context, ref, services, message: 'Service removed');
  }

  Future<void> _persist(
    BuildContext context,
    WidgetRef ref,
    List<AstrologerService> services, {
    required String message,
  }) async {
    try {
      await ref
          .read(myAstrologerAccountProvider.notifier)
          .saveServices(services);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save — please try again.')),
        );
      }
    }
  }
}

class _ServiceCard extends StatelessWidget {
  final AstrologerService service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ServiceCard({
    required this.service,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => AstrologerCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(service.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      if (!service.available)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Unavailable',
                              style: TextStyle(
                                  fontSize: 10.5, color: Colors.grey[600])),
                        ),
                    ],
                  ),
                  if (service.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(service.description,
                        style:
                            TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                  ],
                  const SizedBox(height: 4),
                  Text('₹${service.price} · ${service.durationMinutes} min',
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 19),
              color: AppColors.textSecondary,
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 19),
              color: AppColors.error,
              onPressed: onDelete,
            ),
          ],
        ),
      );
}

/// Add / edit form for a single service. Returns the built [AstrologerService]
/// via `Navigator.pop`, or null if cancelled.
class _ServiceSheet extends StatefulWidget {
  final AstrologerService? initial;
  const _ServiceSheet({this.initial});

  @override
  State<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<_ServiceSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _desc =
      TextEditingController(text: widget.initial?.description ?? '');
  late final TextEditingController _fee =
      TextEditingController(text: widget.initial?.price.toString() ?? '');
  late final TextEditingController _duration = TextEditingController(
      text: (widget.initial?.durationMinutes ?? 30).toString());
  late bool _available = widget.initial?.available ?? true;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _fee.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      AstrologerService(
        name: _name.text.trim(),
        description: _desc.text.trim(),
        price: int.tryParse(_fee.text.trim()) ?? 0,
        durationMinutes: int.tryParse(_duration.text.trim()) ?? 30,
        available: _available,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.initial == null ? 'Add Service' : 'Edit Service',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _field(_name, 'Service Name',
                hint: 'e.g. Marriage Matching',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            _field(_desc, 'Description',
                hint: 'What this service includes', maxLines: 2),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(_fee, 'Fee (₹)',
                      keyboard: TextInputType.number,
                      digitsOnly: true,
                      validator: (v) =>
                          (int.tryParse(v?.trim() ?? '') == null)
                              ? 'Enter a number'
                              : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(_duration, 'Duration (min)',
                      keyboard: TextInputType.number,
                      digitsOnly: true,
                      validator: (v) =>
                          (int.tryParse(v?.trim() ?? '') == null)
                              ? 'Enter a number'
                              : null),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              title: const Text('Available',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(
                  _available
                      ? 'Users can book this service'
                      : 'Hidden from users',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              value: _available,
              onChanged: (v) => setState(() => _available = v),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(widget.initial == null ? 'Add Service' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboard,
    bool digitsOnly = false,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        inputFormatters:
            digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}
