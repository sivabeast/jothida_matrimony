import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_workspace_screen.dart' show weddingByLine;

/// Wedding Documents: upload and manage invitations, hall bookings, catering,
/// decoration, photographer papers and other wedding documents (images or
/// PDFs, stored on Cloudinary). [scope] narrows to 'shared' / 'bride' /
/// 'groom' documents (null = everything); uploads go to the current scope.
class WeddingDocumentsTab extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  final String? scope;
  const WeddingDocumentsTab(
      {super.key, required this.wedding, required this.identity, this.scope});

  @override
  ConsumerState<WeddingDocumentsTab> createState() =>
      _WeddingDocumentsTabState();
}

class _WeddingDocumentsTabState extends ConsumerState<WeddingDocumentsTab> {
  static const _categories = [
    'Invitation',
    'Hall Booking',
    'Catering',
    'Decoration',
    'Photographer',
    'Other Wedding Documents',
  ];

  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(weddingDocumentsProvider(widget.wedding.id));
    final allDocs = docsAsync.valueOrNull ?? const <WeddingDocument>[];
    final docs = widget.scope == null
        ? allDocs
        : allDocs.where((d) => d.scope == widget.scope).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'wedding_docs_fab',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file),
        label: Text(_uploading ? 'Uploading…' : 'Upload'),
        onPressed: _uploading ? null : _showUploadSheet,
      ),
      body: docsAsync.isLoading && docs.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : docs.isEmpty
              ? _empty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    for (final category in _categories)
                      ..._categorySection(
                          category,
                          docs
                              .where((d) => d.category == category)
                              .toList()),
                    // Documents whose stored category predates the current
                    // list (e.g. 'Invitation Card') still show up here.
                    for (final category in docs
                        .map((d) => d.category)
                        .where((c) => !_categories.contains(c))
                        .toSet())
                      ..._categorySection(
                          category,
                          docs
                              .where((d) => d.category == category)
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
            Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey[350]),
            const SizedBox(height: 14),
            const Text('No wedding documents yet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Upload invitation cards, hall booking receipts, catering '
              'receipts, agreements and more — everyone in the workspace '
              'can see them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _categorySection(String category, List<WeddingDocument> docs) {
    if (docs.isEmpty) return const [];
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
      ...docs.map(_docCard),
    ];
  }

  Widget _docCard(WeddingDocument doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: ListTile(
        leading: doc.isImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  doc.url,
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_outlined,
                      color: AppColors.primary),
                ),
              )
            : const Icon(Icons.picture_as_pdf_outlined,
                color: AppColors.primary, size: 34),
        title: Text(doc.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        subtitle: Text(
            'Uploaded by ${weddingByLine(doc.uploadedByName, doc.uploadedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5)),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[500]),
          onSelected: (v) {
            switch (v) {
              case 'open':
                _open(doc);
              case 'share':
                shareRemoteFile(context, doc.url, pdf: !doc.isImage);
              case 'delete':
                _confirmDelete(doc);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'open', child: Text('Open')),
            PopupMenuItem(value: 'share', child: Text('Share / Download')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => _open(doc),
      ),
    );
  }

  void _open(WeddingDocument doc) {
    if (doc.isImage) {
      showImageGallery(context, [doc.url]);
    } else {
      openRemoteFile(context, doc.url, pdf: true);
    }
  }

  Future<void> _confirmDelete(WeddingDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('"${doc.title}" will be removed for everyone.'),
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
        .deleteDocument(widget.wedding.id, doc.id);
  }

  // ── Upload flow ───────────────────────────────────────────────────────────

  void _showUploadSheet() {
    final titleCtrl = TextEditingController();
    String category = _categories.first;
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
                const Text('Upload Wedding Document',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: _input('Category'),
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) =>
                      setSheetState(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: titleCtrl,
                  decoration:
                      _input('Title (e.g. Hall advance receipt)'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Image'),
                        onPressed: () => _pickAndUpload(ctx, formKey,
                            titleCtrl, () => category, image: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF / File'),
                        onPressed: () => _pickAndUpload(ctx, formKey,
                            titleCtrl, () => category, image: false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(
    BuildContext sheetCtx,
    GlobalKey<FormState> formKey,
    TextEditingController titleCtrl,
    String Function() category, {
    required bool image,
  }) async {
    if (!formKey.currentState!.validate()) return;
    final title = titleCtrl.text.trim();
    final cat = category();

    File? file;
    if (image) {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (x != null) file = File(x.path);
    } else {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
      );
      final path = res?.files.single.path;
      if (path != null) file = File(path);
    }
    if (file == null) return;
    if (!mounted) return;
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      await ref.read(weddingControllerProvider.notifier).uploadDocument(
            widget.wedding.id,
            file: file,
            isImage: image,
            title: title,
            category: cat,
            scope: widget.scope ?? 'shared',
            me: widget.identity,
          );
      final failed = ref.read(weddingControllerProvider).hasError;
      messenger.showSnackBar(SnackBar(
          content: Text(failed
              ? 'Upload failed — please try again.'
              : '"$title" uploaded.')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
