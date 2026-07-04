import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';
import 'wedding_workspace_screen.dart' show weddingByLine;

/// Shared Wedding Gallery — album-organised photos (hall, invitation designs,
/// dress, decoration references, jewellery, makeup, catering, other) that
/// every workspace member can upload, view and download. [scope] narrows to
/// a side gallery ('bride' / 'groom'); 'shared' is the common gallery; null
/// shows everything (menu entry).
class WeddingGalleryPage extends StatelessWidget {
  final String? scope;
  const WeddingGalleryPage({super.key, required this.scope});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: switch (scope) {
        'bride' => 'Bride Gallery',
        'groom' => 'Groom Gallery',
        'shared' => 'Shared Gallery',
        _ => 'Wedding Gallery',
      },
      builder: (_, __, wedding, identity) =>
          _GalleryBody(wedding: wedding, identity: identity, scope: scope),
    );
  }
}

class _GalleryBody extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  final String? scope;
  const _GalleryBody(
      {required this.wedding, required this.identity, required this.scope});

  @override
  ConsumerState<_GalleryBody> createState() => _GalleryBodyState();
}

class _GalleryBodyState extends ConsumerState<_GalleryBody> {
  String _album = 'All';
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(weddingGalleryProvider(widget.wedding.id));
    final all = photosAsync.valueOrNull ?? const <WeddingPhoto>[];
    final scoped = widget.scope == null
        ? all
        : all.where((p) => p.scope == widget.scope).toList();
    final photos = _album == 'All'
        ? scoped
        : scoped.where((p) => p.album == _album).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'wedding_gallery_fab',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_uploading ? 'Uploading…' : 'Upload Photo'),
        onPressed: _uploading ? null : _showUploadSheet,
      ),
      body: Column(
        children: [
          // ── Album chips ──
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              children: [
                for (final album in ['All', ...WeddingPhoto.albums])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(album,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _album == album
                                  ? Colors.white
                                  : Colors.grey[700])),
                      selected: _album == album,
                      selectedColor: AppColors.primary,
                      backgroundColor: Colors.white,
                      onSelected: (_) => setState(() => _album = album),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: photosAsync.isLoading && all.isEmpty
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
                : photos.isEmpty
                    ? _empty()
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: photos.length,
                        itemBuilder: (_, i) =>
                            _photoTile(photos, photos[i]),
                      ),
          ),
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
            Icon(Icons.photo_library_outlined,
                size: 64, color: Colors.grey[350]),
            const SizedBox(height: 14),
            const Text('No photos yet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Upload hall photos, invitation designs, dress photos, '
              'decoration references, jewellery, makeup and catering photos '
              '— organised into albums for everyone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoTile(List<WeddingPhoto> visible, WeddingPhoto photo) {
    return GestureDetector(
      onTap: () => showImageGallery(
        context,
        visible.map((p) => p.url).toList(),
        initialIndex: visible.indexOf(photo),
      ),
      onLongPress: () => _showPhotoActions(photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              photo.url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image_outlined,
                    color: Colors.grey),
              ),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: Material(
                color: Colors.black38,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showPhotoActions(photo),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.more_horiz,
                        size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoActions(WeddingPhoto photo) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(photo.album,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(
                '${photo.caption.isNotEmpty ? '${photo.caption}\n' : ''}'
                'Uploaded by ${weddingByLine(photo.uploadedByName, photo.uploadedAt)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.fullscreen, color: AppColors.primary),
              title: const Text('View'),
              onTap: () {
                Navigator.pop(ctx);
                showImageGallery(context, [photo.url]);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.download_outlined, color: AppColors.primary),
              title: const Text('Share / Download'),
              onTap: () {
                Navigator.pop(ctx);
                shareRemoteFile(context, photo.url, pdf: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(photo);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(WeddingPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('This photo will be removed for everyone.'),
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
        .deletePhoto(widget.wedding.id, photo.id);
  }

  // ── Upload flow ───────────────────────────────────────────────────────────

  void _showUploadSheet() {
    String album = _album != 'All' && WeddingPhoto.albums.contains(_album)
        ? _album
        : WeddingPhoto.albums.first;
    final captionCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Upload Wedding Photo',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: album,
                decoration: InputDecoration(
                  labelText: 'Album',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                items: WeddingPhoto.albums
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setSheetState(() => album = v ?? album),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: captionCtrl,
                decoration: InputDecoration(
                  labelText: 'Caption (optional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                      onPressed: () => _pickAndUpload(
                          ctx, () => album, captionCtrl,
                          camera: false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                      onPressed: () => _pickAndUpload(
                          ctx, () => album, captionCtrl,
                          camera: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(
    BuildContext sheetCtx,
    String Function() album,
    TextEditingController captionCtrl, {
    required bool camera,
  }) async {
    final x = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85);
    if (x == null) return;
    if (!mounted) return;
    final selectedAlbum = album();
    final caption = captionCtrl.text.trim();
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      await ref.read(weddingControllerProvider.notifier).uploadPhoto(
            widget.wedding.id,
            file: File(x.path),
            album: selectedAlbum,
            scope: widget.scope ?? 'shared',
            caption: caption,
            me: widget.identity,
          );
      final failed = ref.read(weddingControllerProvider).hasError;
      messenger.showSnackBar(SnackBar(
          content: Text(failed
              ? 'Upload failed — please try again.'
              : 'Photo added to "$selectedAlbum".')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}
