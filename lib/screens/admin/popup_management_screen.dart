import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../models/app_popup_model.dart';
import '../../providers/app_popup_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/network_photo.dart';

/// **App Opening Popup** management (spec §13).
///
/// Works exactly like Banner Management, but for the content shown when a
/// member opens the app. The admin can create MANY contents, enable/disable
/// them, reorder them and delete them; the app cycles through everything that
/// is enabled, one per app opening (§14).
///
/// Nothing is hardcoded in the app — with no enabled content, no popup shows.
class PopupManagementScreen extends ConsumerWidget {
  const PopupManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allPopupsProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New Popup'),
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, __) => _Message(
            icon: Icons.error_outline,
            text: 'Could not load popups.\n$e'),
        data: (popups) {
          if (popups.isEmpty) {
            return const _Message(
              icon: Icons.campaign_outlined,
              text: 'No app-opening popups yet.\n\n'
                  'Create one with the + button. Members see each enabled '
                  'popup in turn — one per app opening — and none at all while '
                  'every popup is disabled.',
            );
          }
          final activeCount = popups.where((p) => p.enabled).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              _RotationSummary(active: activeCount, total: popups.length),
              const SizedBox(height: 14),
              for (final p in popups) ...[
                _PopupCard(popup: p, all: popups),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  static void _openForm(BuildContext context, AppPopupModel? existing) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PopupFormScreen(existing: existing),
    ));
  }
}

/// Explains, in the admin's own terms, exactly what the members will see.
class _RotationSummary extends StatelessWidget {
  final int active;
  final int total;
  const _RotationSummary({required this.active, required this.total});

  @override
  Widget build(BuildContext context) {
    final color = active == 0 ? AppColors.warning : AppColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(active == 0 ? Icons.info_outline : Icons.loop, size: 20,
              color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              active == 0
                  ? 'No popup is active, so members see nothing on opening the '
                      'app. Enable at least one to start the rotation.'
                  : '$active of $total popups are active. Members see them in '
                      'this order — one per app opening — then it starts again '
                      'from the top.',
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopupCard extends ConsumerWidget {
  final AppPopupModel popup;
  final List<AppPopupModel> all;
  const _PopupCard({required this.popup, required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(popupControllerProvider.notifier);
    final i = all.indexWhere((p) => p.id == popup.id);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (popup.hasImage)
            AspectRatio(
              aspectRatio: 5 / 3,
              child: NetworkPhoto(
                  url: popup.imageUrl,
                  fallbackIcon: Icons.image_outlined,
                  fallbackIconSize: 34),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        popup.title.trim().isEmpty
                            ? '(untitled)'
                            : popup.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700),
                      ),
                      if (popup.content.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(popup.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: Colors.grey[700])),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: popup.enabled,
                  activeThumbColor: AppColors.success,
                  onChanged: (v) => ctrl.setEnabled(popup.id, v),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              _chip(popup.enabled ? 'Active' : 'Inactive',
                  popup.enabled ? AppColors.success : Colors.grey),
              const Spacer(),
              IconButton(
                tooltip: 'Move up',
                onPressed: i > 0 ? () => ctrl.move(all, popup, -1) : null,
                icon: const Icon(Icons.arrow_upward, size: 20),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed:
                    i < all.length - 1 ? () => ctrl.move(all, popup, 1) : null,
                icon: const Icon(Icons.arrow_downward, size: 20),
              ),
              IconButton(
                tooltip: 'Edit',
                onPressed: () => PopupManagementScreen._openForm(context, popup),
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, ref),
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppColors.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      );

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete this popup?',
      message: 'It will be removed permanently and will no longer appear in '
          'the rotation.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      icon: Icons.delete_outline,
      danger: true,
    );
    if (!ok) return;
    await ref.read(popupControllerProvider.notifier).delete(popup.id);
    if (context.mounted) showAppSnack(context, 'Popup deleted.');
  }
}

/// Create / edit form.
class _PopupFormScreen extends ConsumerStatefulWidget {
  final AppPopupModel? existing;
  const _PopupFormScreen({required this.existing});

  @override
  ConsumerState<_PopupFormScreen> createState() => _PopupFormScreenState();
}

class _PopupFormScreenState extends ConsumerState<_PopupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _content =
      TextEditingController(text: widget.existing?.content ?? '');
  late String _imageUrl = widget.existing?.imageUrl ?? '';
  late bool _enabled = widget.existing?.enabled ?? true;

  bool _uploading = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadChatAttachment(
            threadId: 'app_popups',
            file: File(picked.path),
            isImage: true,
          );
      if (!mounted) return;
      setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) showAppSnack(context, 'Upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final ctrl = ref.read(popupControllerProvider.notifier);
    if (_isEdit) {
      await ctrl.update(widget.existing!.id, {
        'title': _title.text.trim(),
        'content': _content.text.trim(),
        'imageUrl': _imageUrl,
        'enabled': _enabled,
      });
    } else {
      // New popups go to the END of the rotation.
      final all = ref.read(allPopupsProvider).valueOrNull ?? const [];
      final nextOrder = all.isEmpty
          ? 0
          : all.map((p) => p.order).reduce((a, b) => a > b ? a : b) + 1;
      await ctrl.create(AppPopupModel(
        id: 'new',
        title: _title.text.trim(),
        content: _content.text.trim(),
        imageUrl: _imageUrl,
        enabled: _enabled,
        order: nextOrder,
        createdAt: DateTime.now(),
      ));
    }
    if (!mounted) return;
    final failed = ref.read(popupControllerProvider).hasError;
    setState(() => _saving = false);
    if (failed) {
      showAppSnack(context, 'Could not save the popup.', error: true);
      return;
    }
    Navigator.of(context).pop();
    showAppSnack(context, _isEdit ? 'Popup updated.' : 'Popup created.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Popup' : 'New Popup'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: _dec('Title *'),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'A title is required'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _content,
              maxLines: 8,
              minLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: _dec('Content *'),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Some content is required'
                  : null,
            ),
            const SizedBox(height: 18),
            const Text('Image (optional)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 5 / 3,
                  child: NetworkPhoto(url: _imageUrl),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickImage,
                    icon: _uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_outlined, size: 18),
                    label: Text(_imageUrl.isEmpty
                        ? 'Add image'
                        : 'Replace image'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                if (_imageUrl.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Remove image',
                    onPressed: () => setState(() => _imageUrl = ''),
                    icon: const Icon(Icons.close, color: AppColors.error),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _enabled,
              activeThumbColor: AppColors.success,
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text(
                  'Only active popups take part in the rotation.'),
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_saving || _uploading) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(_saving
                    ? 'Saving…'
                    : (_isEdit ? 'Save Changes' : 'Create Popup')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 60, color: AppColors.primary.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, height: 1.5)),
            ],
          ),
        ),
      );
}
