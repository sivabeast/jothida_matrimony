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
///  • Image banners: upload finished artwork. The banner size is FIXED to the
///    user Home banner dimensions — a recommended upload size is shown and
///    wrong-sized images are rejected (no manual width/height inputs).
///  • Text banners: the professional advertisement builder — premium templates
///    (Red Premium, Royal Blue, Purple, Gold Luxury, Green, Dark Elegant),
///    fixed text-left / graphics-right layout, gradient text, background
///    styles, fonts and logo illustrations, with a live preview that matches
///    the user app exactly.
///  • Per banner: enable/disable (publish), display order, edit, delete.
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
          // Preview at the exact user Home banner aspect ratio.
          Opacity(
            opacity: banner.enabled ? 1 : 0.45,
            child: AspectRatio(
              aspectRatio: 1 / kBannerAspectRatio,
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

  late BannerTemplate _template;
  Color? _primaryOverride; // null → template default
  Color? _secondaryOverride; // null → template default
  late Color _textColor;
  late BannerBackgroundStyle _bgStyle;
  late BannerTextFill _textFill;
  late List<Color> _gradientColors;
  late String _fontFamily;
  late BannerLogoStyle _logoStyle;
  late double _fontSize; // 0 = auto
  late String _textAlign;

  bool _uploading = false;
  bool _saving = false;

  static const _overridePalette = <Color>[
    Color(0xFF8B0000), Color(0xFF14337F), Color(0xFF5B2C93),
    Color(0xFFB8860B), Color(0xFF1B5E20), Color(0xFF262B38),
    Color(0xFFE65100), Color(0xFF880E4F), Color(0xFF00695C),
  ];
  static const _textPalette = <Color>[
    Colors.white, Color(0xFFFFD700), Color(0xFFFFF3C9), Color(0xFFFFE0B2),
    Color(0xFFB9F6CA), Color(0xFFE0B3FF), Color(0xFF212121),
  ];
  static const _fonts = <(String, String)>[
    ('Poppins', 'Poppins'),
    ('NotoSansTamil', 'Tamil (Noto Sans)'),
    ('', 'System Default'),
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
    _template = e?.templateEnum ?? BannerTemplate.redPremium;
    _primaryOverride = (e != null && e.primaryColor.trim().isNotEmpty)
        ? e.effectivePrimary
        : null;
    _secondaryOverride = (e != null && e.secondaryColor.trim().isNotEmpty)
        ? e.effectiveSecondary
        : null;
    _textColor = e?.fgColor ?? Colors.white;
    _bgStyle = e?.backgroundStyleEnum ?? BannerBackgroundStyle.gradient;
    _textFill = e?.textFillEnum ?? BannerTextFill.solid;
    _gradientColors = e != null && e.textGradientColors.isNotEmpty
        ? [
            for (final h in e.textGradientColors)
              HomeBannerModel.parseHexColor(h, _template.accent),
          ]
        : [Colors.white, _template.accent];
    _fontFamily = e?.fontFamily ?? 'Poppins';
    _logoStyle = e?.logoStyleEnum ?? BannerLogoStyle.zodiacWheel;
    _fontSize = e?.fontSize ?? 0;
    _textAlign = e?.textAlign ?? 'left';
  }

  @override
  void dispose() {
    _titleC.dispose();
    _subtitleC.dispose();
    _descC.dispose();
    super.dispose();
  }

  /// The banner as currently configured — drives the LIVE preview, which is
  /// rendered by the same [HomeBannerSlide] the user Home page uses.
  HomeBannerModel get _draft => HomeBannerModel(
        id: widget.existing?.id ?? '',
        type: _type,
        imageUrl: _imageUrl,
        title: _titleC.text,
        subtitle: _subtitleC.text,
        description: _descC.text,
        template: _template.key,
        primaryColor: _primaryOverride == null
            ? ''
            : HomeBannerModel.colorToHex(_primaryOverride!),
        secondaryColor: _secondaryOverride == null
            ? ''
            : HomeBannerModel.colorToHex(_secondaryOverride!),
        textColor: HomeBannerModel.colorToHex(_textColor),
        backgroundStyle: _bgStyle.key,
        textFill: _textFill.key,
        textGradientColors: [
          for (final c in _gradientColors) HomeBannerModel.colorToHex(c),
        ],
        fontFamily: _fontFamily,
        logoStyle: _logoStyle.key,
        fontSize: _fontSize,
        textAlign: _textAlign,
        enabled: widget.existing?.enabled ?? true,
        order: widget.existing?.order ?? 0,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

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
        _snack('Image rejected: ${w}×$h is not the required banner shape. '
            'Please upload $kBannerRecommendedWidth × '
            '$kBannerRecommendedHeight px (5:3).');
        return;
      }
      if (w < kBannerMinUploadWidth) {
        _snack('Image rejected: too small (${w}px wide). Upload at least '
            '$kBannerMinUploadWidth px wide — recommended '
            '$kBannerRecommendedWidth × $kBannerRecommendedHeight px.');
        return;
      }

      final url = await ref.read(storageServiceProvider).uploadChatAttachment(
          threadId: 'home_banners', file: file, isImage: true);
      if (!mounted) return;
      setState(() => _imageUrl = url);
      _snack('Image uploaded (${w}×$h)');
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
          template: draft.template,
          primaryColor: draft.primaryColor,
          secondaryColor: draft.secondaryColor,
          textColor: draft.textColor,
          backgroundStyle: draft.backgroundStyle,
          textFill: draft.textFill,
          textGradientColors: draft.textGradientColors,
          fontFamily: draft.fontFamily,
          logoStyle: draft.logoStyle,
          fontSize: draft.fontSize,
          textAlign: draft.textAlign,
          enabled: true,
          order: nextOrder,
          createdAt: DateTime.now(),
        ));
      } else {
        await ctrl.update(widget.existing!.id, {
          'type': draft.type,
          'imageUrl': draft.imageUrl,
          'title': draft.title.trim(),
          'subtitle': draft.subtitle.trim(),
          'description': draft.description.trim(),
          'template': draft.template,
          'primaryColor': draft.primaryColor,
          'secondaryColor': draft.secondaryColor,
          'textColor': draft.textColor,
          'backgroundStyle': draft.backgroundStyle,
          'textFill': draft.textFill,
          'textGradientColors': draft.textGradientColors,
          'fontFamily': draft.fontFamily,
          'logoStyle': draft.logoStyle,
          'fontSize': draft.fontSize,
          'textAlign': draft.textAlign,
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
          // ── Live preview — identical to the user Home banner ────────────
          _sectionLabel('Live Preview'),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1 / kBannerAspectRatio,
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
                  icon: Icon(Icons.auto_awesome),
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.primary.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.straighten,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recommended size: $kBannerRecommendedWidth × '
                      '$kBannerRecommendedHeight px (5:3). The banner always '
                      'renders at the user Home banner dimensions — uploads '
                      'with a different shape are rejected.',
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
              ),
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
            _sectionLabel('Background Theme (Templates)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in BannerTemplate.values)
                  _templateChip(t, selected: t == _template),
              ],
            ),
            const SizedBox(height: 16),
            _sectionLabel('Content'),
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
            _sectionLabel('Background Style'),
            SegmentedButton<BannerBackgroundStyle>(
              segments: [
                for (final s in BannerBackgroundStyle.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {_bgStyle},
              onSelectionChanged: (s) => setState(() => _bgStyle = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.primary.withOpacity(0.12),
                selectedForegroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(height: 14),
            _sectionLabel('Primary Color'),
            _swatchRow(
              [null, ..._overridePalette],
              _primaryOverride,
              (c) => setState(() => _primaryOverride = c),
              templateDefault: _template.primary,
            ),
            const SizedBox(height: 12),
            _sectionLabel('Secondary Color'),
            _swatchRow(
              [null, ..._overridePalette],
              _secondaryOverride,
              (c) => setState(() => _secondaryOverride = c),
              templateDefault: _template.secondary,
            ),
            const SizedBox(height: 14),
            _sectionLabel('Text Style'),
            SegmentedButton<BannerTextFill>(
              segments: [
                for (final f in BannerTextFill.values)
                  ButtonSegment(
                      value: f,
                      label: Text(f == BannerTextFill.solid
                          ? 'Solid'
                          : f == BannerTextFill.gradient2
                              ? '2-Color'
                              : 'Multi')),
              ],
              selected: {_textFill},
              onSelectionChanged: (s) =>
                  setState(() => _textFill = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.primary.withOpacity(0.12),
                selectedForegroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            if (_textFill == BannerTextFill.solid) ...[
              _sectionLabel('Text Color'),
              _swatchRow(
                [for (final c in _textPalette) c],
                _textColor,
                (c) => setState(() => _textColor = c ?? Colors.white),
              ),
            ] else ...[
              _sectionLabel(_textFill == BannerTextFill.gradient2
                  ? 'Gradient Colors (2)'
                  : 'Gradient Colors (3)'),
              for (var i = 0;
                  i < (_textFill == BannerTextFill.gradient2 ? 2 : 3);
                  i++) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _swatchRow(
                    [for (final c in _textPalette) c],
                    i < _gradientColors.length ? _gradientColors[i] : null,
                    (c) => setState(() {
                      while (_gradientColors.length <= i) {
                        _gradientColors.add(_template.accent);
                      }
                      _gradientColors[i] = c ?? Colors.white;
                    }),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 6),
            _sectionLabel('Font'),
            DropdownButtonFormField<String>(
              value: _fontFamily,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true),
              items: [
                for (final (v, label) in _fonts)
                  DropdownMenuItem(value: v, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _fontFamily = v ?? 'Poppins'),
            ),
            const SizedBox(height: 14),
            _sectionLabel('Logo Template (right-side graphic)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in BannerLogoStyle.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: s == _logoStyle,
                    selectedColor: AppColors.primary.withOpacity(0.15),
                    labelStyle: TextStyle(
                        fontSize: 12.5,
                        color: s == _logoStyle
                            ? AppColors.primary
                            : Colors.grey[800],
                        fontWeight: FontWeight.w600),
                    onSelected: (_) => setState(() => _logoStyle = s),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _sectionLabel('Font Size'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _fontSize == 0 ? 21 : _fontSize,
                    min: 14,
                    max: 34,
                    divisions: 20,
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
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13.5,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      );

  /// A premium template chip showing its gradient + name.
  Widget _templateChip(BannerTemplate t, {required bool selected}) {
    return GestureDetector(
      onTap: () => setState(() {
        _template = t;
        // Re-anchor the default gradient text to the new template's accent
        // when the admin hasn't customised it away from defaults.
        if (_gradientColors.length == 2 &&
            _gradientColors[0] == Colors.white) {
          _gradientColors = [Colors.white, t.accent];
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [t.primary, t.secondary]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? t.accent : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [BoxShadow(color: t.primary.withOpacity(0.4), blurRadius: 8)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_circle, size: 15, color: t.accent),
              const SizedBox(width: 5),
            ],
            Text(t.label,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// Colour swatch row. A `null` entry renders the "template default" swatch
  /// (shown with the [templateDefault] colour and a refresh glyph).
  Widget _swatchRow(
    List<Color?> palette,
    Color? selected,
    ValueChanged<Color?> onPick, {
    Color? templateDefault,
  }) {
    bool same(Color? a, Color? b) =>
        (a == null && b == null) ||
        (a != null && b != null && a.value == b.value);
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
                color: c ?? templateDefault ?? Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: same(selected, c)
                      ? AppColors.primary
                      : Colors.grey.shade300,
                  width: same(selected, c) ? 3 : 1,
                ),
              ),
              child: c == null
                  ? const Icon(Icons.auto_fix_high,
                      size: 15, color: Colors.white)
                  : (same(selected, c)
                      ? Icon(Icons.check,
                          size: 16,
                          color: ThemeData.estimateBrightnessForColor(c) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black87)
                      : null),
            ),
          ),
      ],
    );
  }
}
