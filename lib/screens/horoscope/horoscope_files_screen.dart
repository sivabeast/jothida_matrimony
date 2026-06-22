import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../providers/horoscope_files_provider.dart';
import '../../providers/profile_provider.dart';

/// Horoscope / Jathagam document manager for the signed-in user.
///
/// Upload MULTIPLE horoscope images and PDFs, preview, replace, delete and
/// download each. Backs the spec's "Horoscope / Jathagam Upload System".
class HoroscopeFilesScreen extends ConsumerWidget {
  const HoroscopeFilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final busy = ref.watch(horoscopeFilesControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Documents'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          profileAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
            error: (_, __) =>
                const Center(child: Text('Could not load your profile.')),
            data: (profile) {
              if (profile == null) {
                return _emptyProfile(context);
              }
              final images = profile.horoscope.horoscopeImages;
              final pdfs = profile.horoscope.allPdfUrls;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _intro(),
                  const SizedBox(height: 16),
                  _imagesSection(context, ref, images),
                  const SizedBox(height: 24),
                  _pdfsSection(context, ref, pdfs),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
          if (busy)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            ),
        ],
      ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Upload your jathagam as images (JPG / PNG / WEBP) or PDFs. '
                'These are shared with astrologers you book for match analysis.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
              ),
            ),
          ],
        ),
      );

  // ── Images ──────────────────────────────────────────────────────────────
  Widget _imagesSection(
      BuildContext context, WidgetRef ref, List<String> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '🖼️ Horoscope Images',
          count: images.length,
          onAdd: () => _addImages(context, ref),
        ),
        const SizedBox(height: 10),
        if (images.isEmpty)
          _emptyTile('No horoscope images yet. Tap “Add” to upload.')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: images.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (_, i) => _imageTile(context, ref, images, i),
          ),
      ],
    );
  }

  Widget _imageTile(
      BuildContext context, WidgetRef ref, List<String> images, int i) {
    final url = images[i];
    return GestureDetector(
      onTap: () => showImageGallery(context, images, initialIndex: i),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.primary.withOpacity(0.08),
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.primary),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: _fileMenu(
              onDownload: () => shareRemoteFile(context, url, pdf: false, index: i),
              onReplace: () => _replaceImage(context, ref, url),
              onDelete: () => _confirmDelete(
                context,
                'Delete this image?',
                () => _act(context, ref,
                    () => ref
                        .read(horoscopeFilesControllerProvider.notifier)
                        .deleteImage(url),
                    'Image deleted'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PDFs ────────────────────────────────────────────────────────────────
  Widget _pdfsSection(
      BuildContext context, WidgetRef ref, List<String> pdfs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '📄 Horoscope PDFs',
          count: pdfs.length,
          onAdd: () => _addPdfs(context, ref),
        ),
        const SizedBox(height: 10),
        if (pdfs.isEmpty)
          _emptyTile('No horoscope PDFs yet. Tap “Add” to upload.')
        else
          for (var i = 0; i < pdfs.length; i++)
            _pdfTile(context, ref, pdfs[i], i),
      ],
    );
  }

  Widget _pdfTile(BuildContext context, WidgetRef ref, String url, int i) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.25)),
        ),
        child: ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined,
              color: AppColors.primary),
          title: Text('Horoscope PDF ${i + 1}',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: const Text('Tap to open', style: TextStyle(fontSize: 11)),
          onTap: () => openRemoteFile(context, url, pdf: true, index: i),
          trailing: _fileMenu(
            onDownload: () => shareRemoteFile(context, url, pdf: true, index: i),
            onReplace: () => _replacePdf(context, ref, url),
            onDelete: () => _confirmDelete(
              context,
              'Delete this PDF?',
              () => _act(context, ref,
                  () => ref
                      .read(horoscopeFilesControllerProvider.notifier)
                      .deletePdf(url),
                  'PDF deleted'),
            ),
          ),
        ),
      );

  // ── Shared bits ───────────────────────────────────────────────────────────
  Widget _sectionHeader(String title,
          {required int count, required VoidCallback onAdd}) =>
      Row(
        children: [
          Expanded(
            child: Text('$title${count > 0 ? '  ($count)' : ''}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins')),
          ),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      );

  Widget _fileMenu({
    required VoidCallback onDownload,
    required VoidCallback onReplace,
    required VoidCallback onDelete,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
        ),
        child: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          padding: EdgeInsets.zero,
          onSelected: (v) {
            switch (v) {
              case 'download':
                onDownload();
                break;
              case 'replace':
                onReplace();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'download',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.download_outlined),
                    title: Text('Download'))),
            PopupMenuItem(
                value: 'replace',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.swap_horiz),
                    title: Text('Replace'))),
            PopupMenuItem(
                value: 'delete',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete',
                        style: TextStyle(color: Colors.red)))),
          ],
        ),
      );

  Widget _emptyTile(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Text(text,
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      );

  Widget _emptyProfile(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 56, color: AppColors.primary.withOpacity(0.4)),
              const SizedBox(height: 12),
              const Text('Create your profile first',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('You can upload horoscope documents once your profile exists.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _addImages(BuildContext context, WidgetRef ref) async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref
          .read(horoscopeFilesControllerProvider.notifier)
          .addImages(picked.map((x) => File(x.path)).toList()),
      '${picked.length} image(s) added',
    );
  }

  Future<void> _replaceImage(
      BuildContext context, WidgetRef ref, String url) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref
          .read(horoscopeFilesControllerProvider.notifier)
          .replaceImage(url, File(x.path)),
      'Image replaced',
    );
  }

  Future<void> _addPdfs(BuildContext context, WidgetRef ref) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (res == null) return;
    final files =
        res.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
    if (files.isEmpty || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref
          .read(horoscopeFilesControllerProvider.notifier)
          .addPdfs(files),
      '${files.length} PDF(s) added',
    );
  }

  Future<void> _replacePdf(
      BuildContext context, WidgetRef ref, String url) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = res?.files.single.path;
    if (path == null || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref
          .read(horoscopeFilesControllerProvider.notifier)
          .replacePdf(url, File(path)),
      'PDF replaced',
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, String message, VoidCallback onConfirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) onConfirm();
  }

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() action, String successMsg) async {
    try {
      await action();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.')));
    }
  }
}
