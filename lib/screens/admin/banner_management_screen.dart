import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../models/banner_model.dart';
import '../../providers/banner_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/data_states.dart';
import '../../widgets/common/skeletons.dart';
import '../../widgets/home/home_banner_slide.dart';

/// Admin "Banner Management" — full control of the Home page banner carousel.
/// Registered at `/admin/banners`.
///
/// Banners are IMAGE ONLY: the admin uploads finished artwork and the exact
/// image is what users see on the Home page. There is no text/template banner
/// builder and nothing is overlaid on the upload. The banner size is FIXED to
/// the user Home banner shape — a recommended upload size is shown and
/// wrong-sized images are rejected (no manual width/height inputs).
///
/// Per banner: enable/disable (publish), display order, replace image, delete.
/// When no banner is published the Home carousel is hidden entirely.
class BannerManagementScreen extends ConsumerWidget {
  const BannerManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allBannersProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Banner Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Upload Banner'),
      ),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: const [
            SkeletonCard(height: 200),
            SkeletonCard(height: 200),
            SkeletonCard(height: 200),
          ],
        ),
        error: (e, _) => ErrorStateView(
          message: 'Unable to load banners. Please try again.',
          onRetry: () => ref.invalidate(allBannersProvider),
        ),
        data: (banners) {
          if (banners.isEmpty) {
            return EmptyState(
              icon: Icons.view_carousel_outlined,
              message: 'No banners yet',
              subtitle: 'Upload a banner image and it will appear in the Home '
                  'page carousel. While this list is empty the Home page shows '
                  'no banner at all.',
              actionLabel: 'Upload Banner',
              onAction: () => _openForm(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: banners.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _BannerCard(
              banner: banners[i],
              isFirst: i == 0,
              isLast: i == banners.length - 1,
              all: banners,
              onEdit: () => _openForm(context, ref, existing: banners[i]),
            ),
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, WidgetRef ref,
      {HomeBannerModel? existing}) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _BannerFormScreen(existing: existing),
    ));
  }
}

// ── One banner row in the admin list ─────────────────────────────────────────

class _BannerCard extends ConsumerWidget {
  final HomeBannerModel banner;
  final bool isFirst;
  final bool isLast;
  final List<HomeBannerModel> all;
  final VoidCallback onEdit;

  const _BannerCard({
    required this.banner,
    required this.isFirst,
    required this.isLast,
    required this.all,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(bannerControllerProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview at the exact user Home banner aspect ratio.
          Opacity(
            opacity: banner.enabled ? 1 : 0.45,
            child: AspectRatio(
              aspectRatio: 1 / kBannerAspectRatio,
              child: HomeBannerSlide(banner: banner),
            ),
          ),
          if (banner.title.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(banner.title.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (banner.enabled ? AppColors.success : Colors.grey)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(banner.enabled ? 'Published' : 'Hidden',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: banner.enabled
                              ? AppColors.success
                              : Colors.grey)),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Move up',
                  visualDensity: VisualDensity.compact,
                  onPressed: isFirst ? null : () => ctrl.move(all, banner, -1),
                  icon: const Icon(Icons.arrow_upward, size: 19),
                ),
                IconButton(
                  tooltip: 'Move down',
                  visualDensity: VisualDensity.compact,
                  onPressed: isLast ? null : () => ctrl.move(all, banner, 1),
                  icon: const Icon(Icons.arrow_downward, size: 19),
                ),
                Switch.adaptive(
                  value: banner.enabled,
                  activeColor: AppColors.success,
                  onChanged: (v) => ctrl.setEnabled(banner.id, v),
                ),
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined,
                      size: 20, color: AppColors.primary),
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDelete(context, ref),
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.error),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete Banner?',
      message: 'It disappears from the Home page immediately. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      danger: true,
    );
    if (!ok) return;
    await ref.read(bannerControllerProvider.notifier).delete(banner.id);
    if (context.mounted) showAppSnack(context, 'Banner deleted.');
  }
}

// ── Upload / Replace form ────────────────────────────────────────────────────

class _BannerFormScreen extends ConsumerStatefulWidget {
  final HomeBannerModel? existing;
  const _BannerFormScreen({this.existing});

  @override
  ConsumerState<_BannerFormScreen> createState() => _BannerFormScreenState();
}

class _BannerFormScreenState extends ConsumerState<_BannerFormScreen> {
  late final TextEditingController _titleC;
  String _imageUrl = '';

  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleC = TextEditingController(text: e?.title ?? '');
    _imageUrl = e?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _titleC.dispose();
    super.dispose();
  }

  void _snack(String m, {bool error = false}) =>
      showAppSnack(context, m, error: error);

  // ── Image upload with dimension validation ────────────────────────────────

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final w = decoded.width, h = decoded.height;
      decoded.dispose();

      // The banner renders at the FIXED user Home banner shape (5:3). Reject
      // uploads whose aspect ratio deviates beyond the tolerance, or that are
      // too small to look crisp.
      final ratio = h / w;
      final off = (ratio - kBannerAspectRatio).abs() / kBannerAspectRatio;
      if (off > kBannerAspectTolerance) {
        _snack(
            'Image rejected: ${w}×$h is not the required banner shape. '
            'Please upload $kBannerRecommendedWidth × '
            '$kBannerRecommendedHeight px (5:3).',
            error: true);
        return;
      }
      if (w < kBannerMinUploadWidth) {
        _snack(
            'Image rejected: too small (${w}px wide). Upload at least '
            '$kBannerMinUploadWidth px wide — recommended '
            '$kBannerRecommendedWidth × $kBannerRecommendedHeight px.',
            error: true);
        return;
      }

      final url = await ref.read(storageServiceProvider).uploadChatAttachment(
          threadId: 'home_banners', file: file, isImage: true);
      if (!mounted) return;
      setState(() => _imageUrl = url);
      _snack('Image uploaded (${w}×$h)');
    } catch (e) {
      debugPrint('[BannerForm] upload failed: $e');
      if (mounted) {
        _snack('Upload failed. Please check your connection and try again.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_imageUrl.trim().isEmpty) {
      _snack('Please upload a banner image first', error: true);
      return;
    }

    setState(() => _saving = true);
    final ctrl = ref.read(bannerControllerProvider.notifier);
    try {
      if (widget.existing == null) {
        final current = ref.read(allBannersProvider).valueOrNull ?? const [];
        final nextOrder = current.isEmpty
            ? 0
            : current.map((b) => b.order).reduce((a, b) => a > b ? a : b) + 1;
        await ctrl.create(HomeBannerModel(
          id: '',
          imageUrl: _imageUrl.trim(),
          title: _titleC.text.trim(),
          enabled: true,
          order: nextOrder,
          createdAt: DateTime.now(),
        ));
      } else {
        await ctrl.update(widget.existing!.id, {
          'imageUrl': _imageUrl.trim(),
          'title': _titleC.text.trim(),
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[BannerForm] save failed: $e');
      if (mounted) {
        _snack('Could not save the banner. Please try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Upload Banner' : 'Edit Banner'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _sectionLabel('Banner Image'),
          // Live preview at the exact Home carousel shape — what the admin sees
          // here is exactly what the user gets, with no overlay.
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 1 / kBannerAspectRatio,
              child: _imageUrl.trim().isEmpty
                  ? Container(
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image_outlined,
                              size: 42, color: Colors.grey.shade500),
                          const SizedBox(height: 8),
                          Text('No image selected',
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : HomeBannerSlide(
                      banner: HomeBannerModel(
                        id: '',
                        imageUrl: _imageUrl,
                        createdAt: DateTime.now(),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _pickImage,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_outlined, size: 18),
              label: Text(_imageUrl.trim().isEmpty
                  ? 'Choose Banner Image'
                  : 'Replace Image'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload the finished artwork at $kBannerRecommendedWidth × '
            '$kBannerRecommendedHeight px (5:3). The image is shown on the '
            'Home page exactly as uploaded — no title, text or button is added '
            'on top of it.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 22),
          _sectionLabel('Internal Label (optional)'),
          TextField(
            controller: _titleC,
            decoration: InputDecoration(
              hintText: 'e.g. Diwali Offer 2026',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Only used to identify this banner in the admin list. It is never '
            'shown to users.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: Colors.grey[600])),
      );
}
