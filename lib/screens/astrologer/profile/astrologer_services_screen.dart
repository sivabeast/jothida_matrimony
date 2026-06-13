import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_account_model.dart';
import '../../../models/astrologer_model.dart';
import '../../../providers/astrologer_session_provider.dart';
import 'astrologer_profile_common.dart';

/// Manage the services an astrologer offers (name, description, fee, duration,
/// availability). Add / edit / remove — all persisted to the account doc.
class AstrologerServicesScreen extends ConsumerWidget {
  const AstrologerServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAstrologerAccountProvider);
    final services = account?.services ?? const [];

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: astrologerSectionAppBar('My Services'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: account == null
            ? null
            : () => _addOrEdit(context, ref, account),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Service'),
      ),
      body: services.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No services yet. Tap “Add Service” to create one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600])),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: services.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ServiceCard(
                service: services[i],
                onEdit: () => _addOrEdit(context, ref, account!, index: i),
                onDelete: () => _delete(context, ref, account!, i),
              ),
            ),
    );
  }

  Future<void> _addOrEdit(
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
      builder: (_) =>
          _ServiceSheet(initial: index != null ? account.services[index] : null),
    );
    if (result == null) return;
    final services = [...account.services];
    index != null ? services[index] = result : services.add(result);
    await _persist(context, ref, services,
        message: index != null ? 'Service updated' : 'Service added');
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AstrologerAccount account,
    int index,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service'),
        content:
            Text('Remove “${account.services[index].name}” from your services?'),
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
      await ref.read(myAstrologerAccountProvider.notifier).saveServices(services);
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
          ],
        ),
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

/// Add / edit form for a single service.
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
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      validator: (v) => int.tryParse(v?.trim() ?? '') == null
                          ? 'Enter a number'
                          : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(_duration, 'Duration (min)',
                      keyboard: TextInputType.number,
                      digitsOnly: true,
                      validator: (v) => int.tryParse(v?.trim() ?? '') == null
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}
