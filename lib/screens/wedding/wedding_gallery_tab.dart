import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_workspace_screen.dart' show weddingByLine;

/// GALLERY — three independent galleries (Bride / Shared / Groom) with
/// strict side visibility, unlimited categories, per-category "new uploads"
/// badges, ⭐ Selected item per category, an approval system (votes +
/// comments) and multi-select "Move To Shared".
class WeddingGalleryTab extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const WeddingGalleryTab(
      {super.key, required this.wedding, required this.identity});

  @override
  ConsumerState<WeddingGalleryTab> createState() => _WeddingGalleryTabState();
}

class _WeddingGalleryTabState extends ConsumerState<WeddingGalleryTab> {
  late String _scope = widget.identity.side;
  String _category = WeddingPhoto.defaultCategories.first;
  bool _uploading = false;

  /// Multi-selection (long-press) for Move To Shared / bulk delete.
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  WeddingModel get wedding => widget.wedding;
  WeddingIdentity get me => widget.identity;

  bool _canDeletePhoto(WeddingPhoto p) =>
      me.isSuperAdmin ||
      (p.uploadedByKey == me.key &&
          me.can(WeddingPermissions.deleteOwnPhotos));

  bool _isOwner(WeddingPhoto p) => p.uploadedByKey == me.key;

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(weddingGalleryProvider(wedding.id));
    final allPhotos = photosAsync.valueOrNull ?? const <WeddingPhoto>[];
    // STRICT side visibility: my side + shared only, current scope shown.
    final scopedAll = allPhotos
        .where((p) => me.visibleScopes.contains(p.scope))
        .toList();
    final scoped = scopedAll.where((p) => p.scope == _scope).toList();

    final customCategories =
        ref.watch(weddingGalleryCategoriesProvider(wedding.id)).valueOrNull ??
            const <WeddingGalleryCategory>[];
    final categories = <String>[
      ...WeddingPhoto.defaultCategories,
      ...customCategories
          .map((c) => c.name)
          .where((n) => !WeddingPhoto.defaultCategories.contains(n)),
    ];
    if (!categories.contains(_category)) {
      _category = categories.first;
    }

    final seen = ref
            .watch(weddingGallerySeenProvider((wedding.id, me.key)))
            .valueOrNull ??
        const <String, DateTime>{};

    final photos = scoped.where((p) => p.album == _category).toList();
    final selectedPhoto =
        photos.where((p) => p.isSelected).toList().firstOrNull;
    final gridPhotos =
        photos.where((p) => !p.isSelected).toList(); // selected shown on top

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _selecting
          ? null
          : me.can(WeddingPermissions.uploadPhotos)
              ? FloatingActionButton.extended(
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
                  label: Text(_uploading ? 'Uploading…' : 'Upload'),
                  onPressed: _uploading ? null : _showUploadSheet,
                )
              : null,
      body: Column(
        children: [
          _scopeSwitcher(),
          _categoryBar(categories, scoped, seen),
          if (_selecting) _selectionBar(scoped),
          Expanded(
            child: photosAsync.isLoading && allPhotos.isEmpty
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                    children: [
                      if (selectedPhoto != null)
                        _selectedItemCard(selectedPhoto),
                      if (photos.isEmpty)
                        _empty()
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: gridPhotos.length,
                          itemBuilder: (_, i) => _photoTile(gridPhotos[i]),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Scope switcher (my side ↔ shared) ────────────────────────────────────

  Widget _scopeSwitcher() {
    Widget chip(String scope, String label, String emoji) {
      final active = _scope == scope;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _scope = scope;
            _selected.clear();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: active ? AppColors.primary : Colors.grey.shade300),
            ),
            child: Text('$emoji  $label',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : Colors.grey[700])),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          chip(
              me.side,
              me.side == 'groom' ? 'Groom Gallery' : 'Bride Gallery',
              me.side == 'groom' ? '🤵' : '👰'),
          const SizedBox(width: 10),
          chip('shared', 'Shared Gallery', '❤️'),
        ],
      ),
    );
  }

  // ── Category chips (+ new-upload badges, + Add Category) ─────────────────

  Widget _categoryBar(List<String> categories, List<WeddingPhoto> scoped,
      Map<String, DateTime> seen) {
    bool hasNew(String category) {
      final lastSeen = seen[weddingFieldKey(category)];
      return scoped.any((p) =>
          p.album == category &&
          p.uploadedByKey != me.key &&
          (lastSeen == null || p.uploadedAt.isAfter(lastSeen)));
    }

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ChoiceChip(
                    label: Text(category,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _category == category
                                ? Colors.white
                                : Colors.grey[700])),
                    selected: _category == category,
                    selectedColor: AppColors.primary,
                    backgroundColor: Colors.white,
                    onSelected: (_) {
                      setState(() {
                        _category = category;
                        _selected.clear();
                      });
                      // Opening a category clears its "new uploads" badge.
                      ref
                          .read(weddingControllerProvider.notifier)
                          .markCategorySeen(wedding.id, me, category);
                    },
                  ),
                  if (hasNew(category))
                    Positioned(
                      right: -2,
                      top: 2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                            color: AppColors.error, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          // "+ Add Category" always at the end — unlimited custom categories.
          if (me.can(WeddingPermissions.createGalleryCategory))
            ActionChip(
              avatar:
                  const Icon(Icons.add, size: 16, color: AppColors.primary),
              label: const Text('Add Category',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
              backgroundColor: AppColors.primary.withOpacity(0.06),
              onPressed: _showAddCategoryDialog,
            ),
        ],
      ),
    );
  }

  Future<void> _showAddCategoryDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Gallery Category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              hintText: 'e.g. Mehndi, Sangeet, Honeymoon'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .addGalleryCategory(wedding.id, name, me);
    if (mounted) setState(() => _category = name);
  }

  // ── Multi-selection action bar ────────────────────────────────────────────

  Widget _selectionBar(List<WeddingPhoto> scoped) {
    final selectedPhotos =
        scoped.where((p) => _selected.contains(p.id)).toList();
    final canDeleteAll = selectedPhotos.every(_canDeletePhoto);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () => setState(_selected.clear),
          ),
          Expanded(
            child: Text('${_selected.length} selected',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
          if (_scope != 'shared')
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.drive_file_move_outline, size: 18),
              label: const Text('Move To Shared'),
              onPressed: () => _moveSelectedToShared(selectedPhotos),
            ),
          if (canDeleteAll)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white, size: 20),
              onPressed: () => _deleteSelected(selectedPhotos),
            ),
        ],
      ),
    );
  }

  Future<void> _moveSelectedToShared(List<WeddingPhoto> photos) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move To Shared?'),
        content: Text(
            '${photos.length} photo${photos.length == 1 ? '' : 's'} will move '
            'into the same categor${photos.map((p) => p.album).toSet().length == 1 ? 'y' : 'ies'} '
            'inside the Shared Gallery and become visible to BOTH sides.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move To Shared'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .movePhotosToShared(wedding.id, photos, me);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _deleteSelected(List<WeddingPhoto> photos) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete photos?'),
        content: Text(
            '${photos.length} photo${photos.length == 1 ? '' : 's'} will be '
            'removed for everyone.'),
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
    final controller = ref.read(weddingControllerProvider.notifier);
    for (final p in photos) {
      await controller.deletePhoto(wedding.id, p.id);
    }
    if (mounted) setState(_selected.clear);
  }

  // ── ⭐ Selected item card ──────────────────────────────────────────────────

  Widget _selectedItemCard(WeddingPhoto photo) {
    final vendors =
        ref.watch(weddingVendorsProvider(wedding.id)).valueOrNull ??
            const <WeddingVendor>[];
    final vendor =
        vendors.where((v) => v.id == photo.vendorId).toList().firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 12, top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(color: AppColors.gold.withOpacity(0.15), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⭐', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Selected $_category',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.goldDark)),
              ),
              if (photo.voteResult != null) _voteResultBadge(photo),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _openPhotoDetail(photo),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                photo.url,
                width: double.infinity,
                height: 170,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 170,
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (photo.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(photo.caption,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _metaText(Icons.person_outline,
                  'Selected by ${photo.selectedBy.isEmpty ? '—' : photo.selectedBy}'),
              if (photo.selectedAt != null)
                _metaText(Icons.event_outlined,
                    '${photo.selectedAt!.day}/${photo.selectedAt!.month}/${photo.selectedAt!.year}'),
              _metaText(Icons.how_to_vote_outlined,
                  '${photo.approveCount} 👍 · ${photo.rejectCount} 👎'),
              if (vendor != null)
                _metaText(Icons.storefront_outlined, vendor.name),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaText(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11.5, color: Colors.grey[700])),
      ],
    );
  }

  Widget _voteResultBadge(WeddingPhoto photo) {
    final result = photo.voteResult!;
    final color = switch (result) {
      'Approved' => AppColors.success,
      'Rejected' => AppColors.error,
      _ => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(result,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.bold)),
    );
  }

  // ── Photo grid ────────────────────────────────────────────────────────────

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.photo_library_outlined,
              size: 52, color: Colors.grey[350]),
          const SizedBox(height: 10),
          Text('No $_category photos yet',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            _scope == 'shared'
                ? 'Shared photos are visible to both sides.'
                : 'These photos stay private to the ${me.side} side until '
                    'moved to Shared.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _photoTile(WeddingPhoto photo) {
    final selected = _selected.contains(photo.id);
    return GestureDetector(
      onTap: () {
        if (_selecting) {
          setState(() =>
              selected ? _selected.remove(photo.id) : _selected.add(photo.id));
        } else {
          _openPhotoDetail(photo);
        }
      },
      onLongPress: () => setState(() => _selected.add(photo.id)),
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
            if (photo.votes.isNotEmpty)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                      '👍${photo.approveCount} 👎${photo.rejectCount}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9.5)),
                ),
              ),
            if (_selecting || selected)
              Container(
                color: selected ? AppColors.primary.withOpacity(0.35) : null,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.all(4),
                child: Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Photo detail (view / votes / comments / owner actions) ───────────────

  void _openPhotoDetail(WeddingPhoto photo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => _PhotoDetailSheet(
          wedding: wedding,
          identity: me,
          photoId: photo.id,
          scrollController: scrollCtrl,
          canDelete: _canDeletePhoto,
          isOwner: _isOwner,
        ),
      ),
    );
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  void _showUploadSheet() {
    final captionCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upload to $_category',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              _scope == 'shared'
                  ? 'Visible to both sides (Shared Gallery).'
                  : 'Private to the ${me.side} side until moved to Shared.',
              style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: captionCtrl,
              decoration: InputDecoration(
                labelText: 'Caption / Name (optional)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                    onPressed: () =>
                        _pickAndUpload(ctx, captionCtrl, camera: false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                    onPressed: () =>
                        _pickAndUpload(ctx, captionCtrl, camera: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(
      BuildContext sheetCtx, TextEditingController captionCtrl,
      {required bool camera}) async {
    final picker = ImagePicker();
    final files = <XFile>[];
    if (camera) {
      final x =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (x != null) files.add(x);
    } else {
      files.addAll(await picker.pickMultiImage(imageQuality: 85));
    }
    if (files.isEmpty || !mounted) return;
    final caption = captionCtrl.text.trim();
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final controller = ref.read(weddingControllerProvider.notifier);
      for (final x in files) {
        await controller.uploadPhoto(
          wedding.id,
          file: File(x.path),
          album: _category,
          scope: _scope,
          caption: caption,
          me: me,
        );
      }
      final failed = ref.read(weddingControllerProvider).hasError;
      messenger.showSnackBar(SnackBar(
          content: Text(failed
              ? 'Upload failed — please try again.'
              : '${files.length} photo${files.length == 1 ? '' : 's'} added '
                  'to "$_category".')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}

// ── Photo detail sheet ────────────────────────────────────────────────────────

/// Live photo detail: full preview, approval voting (Approve / Reject +
/// most-voted result), comments, ⭐ selection, vendor link and the owner /
/// Super-Admin actions (rename, replace, delete, share/download).
class _PhotoDetailSheet extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  final String photoId;
  final ScrollController scrollController;
  final bool Function(WeddingPhoto) canDelete;
  final bool Function(WeddingPhoto) isOwner;

  const _PhotoDetailSheet({
    required this.wedding,
    required this.identity,
    required this.photoId,
    required this.scrollController,
    required this.canDelete,
    required this.isOwner,
  });

  @override
  ConsumerState<_PhotoDetailSheet> createState() => _PhotoDetailSheetState();
}

class _PhotoDetailSheetState extends ConsumerState<_PhotoDetailSheet> {
  final _commentCtrl = TextEditingController();

  WeddingIdentity get me => widget.identity;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Live photo — votes/comments update in place while the sheet is open.
    final photos =
        ref.watch(weddingGalleryProvider(widget.wedding.id)).valueOrNull ??
            const <WeddingPhoto>[];
    final photo =
        photos.where((p) => p.id == widget.photoId).toList().firstOrNull;
    if (photo == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('This photo was deleted.'),
      );
    }
    final myVote = photo.voteOf(me.key);
    final canManage = widget.isOwner(photo) || me.isSuperAdmin;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                photo.caption.isNotEmpty ? photo.caption : photo.album,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            if (photo.isSelected)
              const Text('⭐', style: TextStyle(fontSize: 18)),
          ],
        ),
        Text(
            'Uploaded by ${weddingByLine(photo.uploadedByName, photo.uploadedAt)}',
            style: TextStyle(color: Colors.grey[500], fontSize: 11.5)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => showImageGallery(context, [photo.url]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              photo.url,
              width: double.infinity,
              height: 240,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 240,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image_outlined,
                    color: Colors.grey),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── Approval system ──
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  backgroundColor: myVote == 'approve'
                      ? AppColors.success.withOpacity(0.12)
                      : null,
                  side: const BorderSide(color: AppColors.success),
                ),
                icon: const Icon(Icons.thumb_up_alt_outlined, size: 17),
                label: Text('Approve (${photo.approveCount})'),
                onPressed: () => ref
                    .read(weddingControllerProvider.notifier)
                    .votePhoto(widget.wedding.id, photo,
                        me: me,
                        vote: myVote == 'approve' ? null : 'approve'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  backgroundColor: myVote == 'reject'
                      ? AppColors.error.withOpacity(0.12)
                      : null,
                  side: const BorderSide(color: AppColors.error),
                ),
                icon: const Icon(Icons.thumb_down_alt_outlined, size: 17),
                label: Text('Reject (${photo.rejectCount})'),
                onPressed: () => ref
                    .read(weddingControllerProvider.notifier)
                    .votePhoto(widget.wedding.id, photo,
                        me: me, vote: myVote == 'reject' ? null : 'reject'),
              ),
            ),
          ],
        ),
        if (photo.voteResult != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Most voted: ${photo.voteResult}',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: switch (photo.voteResult) {
                    'Approved' => AppColors.success,
                    'Rejected' => AppColors.error,
                    _ => AppColors.warning,
                  }),
            ),
          ),
        ],
        const SizedBox(height: 14),

        // ── Actions ──
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar:
                  const Icon(Icons.star_outline, size: 16, color: AppColors.goldDark),
              label: Text(photo.isSelected
                  ? 'Selected ⭐'
                  : 'Select as ⭐ ${photo.album}'),
              onPressed: photo.isSelected
                  ? null
                  : () => _selectAsStar(photo),
            ),
            ActionChip(
              avatar: const Icon(Icons.download_outlined,
                  size: 16, color: AppColors.primary),
              label: const Text('Share / Download'),
              onPressed: () =>
                  shareRemoteFile(context, photo.url, pdf: false),
            ),
            if (canManage) ...[
              ActionChip(
                avatar: const Icon(Icons.drive_file_rename_outline,
                    size: 16, color: AppColors.primary),
                label: const Text('Rename'),
                onPressed: () => _rename(photo),
              ),
              if (widget.isOwner(photo))
                ActionChip(
                  avatar: const Icon(Icons.flip_camera_ios_outlined,
                      size: 16, color: AppColors.primary),
                  label: const Text('Replace'),
                  onPressed: () => _replace(photo),
                ),
              ActionChip(
                avatar: const Icon(Icons.storefront_outlined,
                    size: 16, color: AppColors.primary),
                label: Text(photo.vendorId.isEmpty
                    ? 'Link Vendor'
                    : 'Change Vendor'),
                onPressed: () => _linkVendor(photo),
              ),
            ],
            if (widget.canDelete(photo))
              ActionChip(
                avatar: const Icon(Icons.delete_outline,
                    size: 16, color: AppColors.error),
                label: const Text('Delete',
                    style: TextStyle(color: AppColors.error)),
                onPressed: () => _delete(photo),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Comments ──
        const Text('Comments',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 13.5)),
        const SizedBox(height: 8),
        if (photo.comments.isEmpty)
          Text('No comments yet.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12))
        else
          ...photo.comments.map((c) {
            final at = c['at'];
            final atDate = at is Timestamp ? at.toDate() : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(
                        (c['byName'] ?? '?').toString().isNotEmpty
                            ? (c['byName'] as String)[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.primary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${c['byName'] ?? ''}'
                            '${atDate != null ? ' · ${atDate.day}/${atDate.month}' : ''}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[600])),
                        Text('${c['text'] ?? ''}',
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                decoration: InputDecoration(
                  hintText: 'Add a comment…',
                  hintStyle:
                      TextStyle(fontSize: 12.5, color: Colors.grey[500]),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send, color: AppColors.primary),
              onPressed: () async {
                final text = _commentCtrl.text.trim();
                if (text.isEmpty) return;
                _commentCtrl.clear();
                await ref
                    .read(weddingControllerProvider.notifier)
                    .commentPhoto(widget.wedding.id, photo.id,
                        me: me, text: text);
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _selectAsStar(WeddingPhoto photo) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select as ⭐ ${photo.album}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'This becomes the finalized choice shown at the top of the '
                'category. Any previous selection is replaced and recorded '
                'in the Decision History.'),
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
            child: const Text('Select ⭐'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(weddingControllerProvider.notifier).selectPhoto(
        widget.wedding.id, photo, me,
        reason: reasonCtrl.text.trim());
  }

  Future<void> _rename(WeddingPhoto photo) async {
    final ctrl = TextEditingController(text: photo.caption);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename photo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration:
              const InputDecoration(labelText: 'Caption / Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .renamePhoto(widget.wedding.id, photo.id, name);
  }

  Future<void> _replace(WeddingPhoto photo) async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null || !mounted) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .replacePhoto(widget.wedding.id, photo.id, File(x.path));
  }

  Future<void> _linkVendor(WeddingPhoto photo) async {
    final vendors =
        ref.read(weddingVendorsProvider(widget.wedding.id)).valueOrNull ??
            const <WeddingVendor>[];
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Link a vendor to this photo',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ),
            if (vendors.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No vendors yet — add them in Vendor Management.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (photo.vendorId.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.link_off,
                            color: AppColors.error),
                        title: const Text('Remove vendor link'),
                        onTap: () => Navigator.pop(ctx, ''),
                      ),
                    ...vendors.map((v) => ListTile(
                          leading: const Icon(Icons.storefront_outlined,
                              color: AppColors.primary),
                          title: Text(v.name),
                          subtitle: Text(v.category,
                              style: const TextStyle(fontSize: 12)),
                          trailing: v.id == photo.vendorId
                              ? const Icon(Icons.check,
                                  color: AppColors.success)
                              : null,
                          onTap: () => Navigator.pop(ctx, v.id),
                        )),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ref.read(weddingServiceProvider).updatePhoto(
        widget.wedding.id, photo.id, {'vendorId': picked});
  }

  Future<void> _delete(WeddingPhoto photo) async {
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
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await ref
        .read(weddingControllerProvider.notifier)
        .deletePhoto(widget.wedding.id, photo.id);
    if (navigator.canPop()) navigator.pop();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
