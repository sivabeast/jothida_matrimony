import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../models/banner_model.dart';
import '../../providers/banner_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/home/home_banner_slide.dart';

/// Admin "Banner Management" — full control of the Home page banner carousel.
/// Registered at `/admin/banners`.
///
///  • Image banners: upload finished artwork (offers / posters / promotions).
///  • Text banners: built with the Text Banner Builder (title, subtitle,
///    description, background & text colours, font size, alignment) with a
///    LIVE preview — no image required.
///  • Per banner: enable/disable (publish), display order (move up/down),
///    height, edit and delete. Users only ever see enabled banners.
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
        icon: const Icon(Icons.add),
        label: const Text('Add Banner'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load banners.\n$e')),
        data: (banners) {
          if (banners.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.view_carousel_outlined,
                      size: 72, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  const Text('No banners yet',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text('Tap "Add Banner" to create an image or text banner.',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Small live preview of exactly what users see.
          Opacity(
            opacity: banner.enabled ? 1 : 0.45,
            child: AspectRatio(
              aspectRatio: 1 / banner.heightRatio.clamp(0.3, 1.2),
              child: HomeBannerSlide(banner: banner),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (banner.isImage ? Colors.blue : Colors.purple)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(banner.isImage ? 'Image' : 'Text',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color:
                              banner.isImage ? Colors.blue : Colors.purple)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (banner.enabled ? AppColors.success : Colors.grey)
                        .withOpacity(0.12),
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
                // Reorder.
                IconButton(
                  tooltip: 'Move up',
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      isFirst ? null : () => ctrl.move(all, banner, -1),
                  icon: const Icon(Icons.arrow_upward, size: 19),
                ),
                IconButton(
                  tooltip: 'Move down',
                  visualDensity: VisualDensity.compact,
                  onPressed: isLast ? null : () => ctrl.move(all, banner, 1),
                  icon: const Icon(Icons.arrow_downward, size: 19),
                ),
                // Publish toggle.
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Banner'),
        content: const Text(
            'Delete this banner? It disappears from the Home page immediately. '
            'This cannot be undone.'),
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
    if (ok != true) return;
    await ref.read(bannerControllerProvider.notifier).delete(banner.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Banner deleted')));
    }
  }
}

// ── Add / Edit form with live preview ────────────────────────────────────────

class _BannerFormScreen extends ConsumerStatefulWidget {
  final HomeBannerModel? existing;
  const _BannerFormScreen({this.existing});

  @override
  ConsumerState<_BannerFormScreen> createState() => _BannerFormScreenState();
}

class _BannerFormScreenState extends ConsumerState<_BannerFormScreen> {
  late String _type;
  late final TextEditingController _titleC;
  late final TextEditingController _subtitleC;
  late final TextEditingController _descC;
  String _imageUrl = '';
  late Color _bgColor;
  late Color _textColor;
  late double _fontSize; // 0 = auto
  late String _textAlign;
  late double _heightRatio;
  bool _uploading = false;
  bool _saving = false;

  static const _bgPalette = <Color>[
    Color(0xFF8B0000), Color(0xFF800020), Color(0xFF1B5E20),
    Color(0xFF0D47A1), Color(0xFF4A148C), Color(0xFFE65100),
    Color(0xFFB8860B), Color(0xFF263238), Color(0xFF000000),
    Color(0xFFFFF8E1), Color(0xFFFFFFFF),
  ];
  static const _textPalette = <Color>[
    Colors.white, Color(0xFFFFD700), Color(0xFFFFF8E1), Color(0xFF212121),
    Color(0xFF8B0000), Color(0xFF1B5E20), Color(0xFF0D47A1),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? HomeBannerModel.typeImage;
    _titleC = TextEditingController(text: e?.title ?? '');
    _subtitleC = TextEditingController(text: e?.subtitle ?? '');
    _descC = TextEditingController(text: e?.description ?? '');
    _imageUrl = e?.imageUrl ?? '';
    _bgColor = e?.bgColor ?? const Color(0xFF8B0000);
    _textColor = e?.fgColor ?? Colors.white;
    _fontSize = e?.fontSize ?? 0;
    _textAlign = e?.textAlign ?? 'left';
    _heightRatio = (e?.heightRatio ?? 0.6).clamp(0.35, 1.0);
  }

  @override
  void dispose() {
    _titleC.dispose();
    _subtitleC.dispose();
    _descC.dispose();
    super.dispose();
  }

  /// The banner as currently configured — drives the LIVE preview.
  HomeBannerModel get _draft => HomeBannerModel(
        id: widget.existing?.id ?? '',
        type: _type,
        imageUrl: _imageUrl,
        title: _titleC.text,
        subtitle: _subtitleC.text,
        description: _descC.text,
        backgroundColor: HomeBannerModel.colorToHex(_bgColor),
        textColor: HomeBannerModel.colorToHex(_textColor),
        fontSize: _fontSize,
        textAlign: _textAlign,
        enabled: widget.existing?.enabled ?? true,
        order: widget.existing?.order ?? 0,
        heightRatio: _heightRatio,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadChatAttachment(
          threadId: 'home_banners', file: File(picked.path), isImage: true);
      if (!mounted) return;
      setState(() => _imageUrl = url);
      _snack('Image uploaded');
    } catch (e) {
      if (mounted) _snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final isImage = _type == HomeBannerModel.typeImage;
    if (isImage && _imageUrl.trim().isEmpty) {
      _snack('Please upload a banner image first');
      return;
    }
    if (!isImage && _titleC.text.trim().isEmpty) {
      _snack('Title is required for a text banner');
      return;
    }

    setState(() => _saving = true);
    final ctrl = ref.read(bannerControllerProvider.notifier);
    final draft = _draft;
    try {
      if (widget.existing == null) {
        // New banners go to the END of the carousel.
        final current = ref.read(allBannersProvider).valueOrNull ?? const [];
        final nextOrder = current.isEmpty
            ? 0
            : current.map((b) => b.order).reduce((a, b) => a > b ? a : b) + 1;
        await ctrl.create(HomeBannerModel(
          id: '',
          type: draft.type,
          imageUrl: draft.imageUrl,
          title: draft.title.trim(),
          subtitle: draft.subtitle.trim(),
          description: draft.description.trim(),
          backgroundColor: draft.backgroundColor,
          textColor: draft.textColor,
          fontSize: draft.fontSize,
          textAlign: draft.textAlign,
          enabled: true,
          order: nextOrder,
          heightRatio: draft.heightRatio,
          createdAt: DateTime.now(),
        ));
      } else {
        await ctrl.update(widget.existing!.id, {
          'type': draft.type,
          'imageUrl': draft.imageUrl,
          'title': draft.title.trim(),
          'subtitle': draft.subtitle.trim(),
          'description': draft.description.trim(),
          'backgroundColor': draft.backgroundColor,
          'textColor': draft.textColor,
          'fontSize': draft.fontSize,
          'textAlign': draft.textAlign,
          'heightRatio': draft.heightRatio,
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack('Could not save banner: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isImage = _type == HomeBannerModel.typeImage;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add Banner' : 'Edit Banner'),
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
        padding: const EdgeInsets.all(16),
        children: [
          // ── Live preview ────────────────────────────────────────────────
          _sectionLabel('Live Preview'),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1 / _heightRatio,
              child: HomeBannerSlide(banner: _draft),
            ),
          ),
          const SizedBox(height: 18),

          // ── Banner type ─────────────────────────────────────────────────
          _sectionLabel('Banner Type'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: HomeBannerModel.typeImage,
                  icon: Icon(Icons.image_outlined),
                  label: Text('Image Banner')),
              ButtonSegment(
                  value: HomeBannerModel.typeText,
                  icon: Icon(Icons.text_fields),
                  label: Text('Text Banner')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppColors.primary.withOpacity(0.12),
              selectedForegroundColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),

          // ── Image banner content ────────────────────────────────────────
          if (isImage) ...[
            _sectionLabel('Banner Image'),
            Text(
              'Upload the finished artwork — offers, posters, promotions or '
              'announcements are shown exactly as uploaded.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickImage,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_outlined, size: 18),
              label: Text(_imageUrl.isEmpty
                  ? 'Upload Banner Image'
                  : 'Replace Banner Image'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],

          // ── Text banner builder ─────────────────────────────────────────
          if (!isImage) ...[
            _sectionLabel('Text Banner Builder'),
            TextField(
              controller: _titleC,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subtitleC,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Subtitle (optional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descC,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            _sectionLabel('Background Color'),
            _swatchRow(_bgPalette, _bgColor,
                (c) => setState(() => _bgColor = c)),
            const SizedBox(height: 14),
            _sectionLabel('Text Color'),
            _swatchRow(_textPalette, _textColor,
                (c) => setState(() => _textColor = c)),
            const SizedBox(height: 14),
            _sectionLabel('Font Size'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _fontSize == 0 ? 22 : _fontSize,
                    min: 14,
                    max: 40,
                    divisions: 26,
                    activeColor: AppColors.primary,
                    label:
                        _fontSize == 0 ? 'Auto' : _fontSize.round().toString(),
                    onChanged: (v) =>
                        setState(() => _fontSize = v.roundToDouble()),
                  ),
                ),
                TextButton(
                  onPressed: _fontSize == 0
                      ? null
                      : () => setState(() => _fontSize = 0),
                  child: const Text('Auto'),
                ),
              ],
            ),
            _sectionLabel('Text Alignment'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'left', icon: Icon(Icons.format_align_left)),
                ButtonSegment(
                    value: 'center', icon: Icon(Icons.format_align_center)),
                ButtonSegment(
                    value: 'right', icon: Icon(Icons.format_align_right)),
              ],
              selected: {_textAlign},
              onSelectionChanged: (s) => setState(() => _textAlign = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.primary.withOpacity(0.12),
                selectedForegroundColor: AppColors.primary,
              ),
            ),
          ],

          const SizedBox(height: 18),
          _sectionLabel('Banner Height'),
          Text(
            'Height relative to the banner width — applies to how tall the '
            'banner renders on the Home page.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
          Slider(
            value: _heightRatio,
            min: 0.35,
            max: 1.0,
            divisions: 13,
            activeColor: AppColors.primary,
            label: _heightRatio < 0.5
                ? 'Compact'
                : (_heightRatio <= 0.7 ? 'Standard' : 'Tall'),
            onChanged: (v) => setState(() => _heightRatio = v),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check, size: 18),
            label: Text(
                widget.existing == null ? 'Create Banner' : 'Save Changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13.5,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      );

  Widget _swatchRow(
      List<Color> palette, Color selected, ValueChanged<Color> onPick) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in palette)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected.value == c.value
                      ? AppColors.primary
                      : Colors.grey.shade300,
                  width: selected.value == c.value ? 3 : 1,
                ),
              ),
              child: selected.value == c.value
                  ? Icon(Icons.check,
                      size: 16,
                      color: ThemeData.estimateBrightnessForColor(c) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black87)
                  : null,
            ),
          ),
      ],
    );
  }
}
