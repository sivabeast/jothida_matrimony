import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_actions.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../models/profile_model.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/horoscope_documents_view.dart';

/// Horoscope Upload step — optionally attach the horoscope as **images
/// (JPG / PNG)** and/or **PDF** files. Any number of each may be added.
///
/// Newly picked files are previewed locally and uploaded on submit (see
/// [ProfileCreationNotifier.submitProfile], which merges the resulting URLs
/// into `horoscopeDetails.horoscopeImages` / `.horoscopePdfUrls`). In edit mode
/// the documents already on the profile are shown above, with their own
/// view/download actions. Skipping is always allowed.
class StepHoroscopeUpload extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepHoroscopeUpload({super.key, required this.onNext});

  @override
  ConsumerState<StepHoroscopeUpload> createState() =>
      _StepHoroscopeUploadState();
}

class _StepHoroscopeUploadState extends ConsumerState<StepHoroscopeUpload> {
  final _picker = ImagePicker();
  final List<File> _images = [];
  final List<File> _pdfs = [];

  /// Documents ALREADY stored on the profile (edit mode) — kept as they are.
  HoroscopeDetails? get _existing {
    final h = ref.read(profileCreationProvider).data['horoscopeDetails'];
    if (h is Map) {
      return HoroscopeDetails.fromMap(Map<String, dynamic>.from(h));
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final state = ref.read(profileCreationProvider);
    _images.addAll(state.horoscopeImages);
    _pdfs.addAll(state.horoscopePdfs);
  }

  void _sync() => ref
      .read(profileCreationProvider.notifier)
      .setHoroscopeFiles(images: _images, pdfs: _pdfs);

  Future<void> _pickImages() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;
      setState(() => _images.addAll(picked.map((x) => File(x.path))));
      _sync();
    } catch (e) {
      debugPrint('[HoroscopeUpload] image pick failed: $e');
      _snack(context.l10n.couldNotPickFile);
    }
  }

  Future<void> _pickPdfs() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: true,
      );
      final paths = (result?.files ?? const [])
          .map((f) => f.path)
          .whereType<String>()
          .toList();
      if (paths.isEmpty) return;
      setState(() => _pdfs.addAll(paths.map(File.new)));
      _sync();
    } catch (e) {
      debugPrint('[HoroscopeUpload] pdf pick failed: $e');
      _snack(context.l10n.couldNotPickFile);
    }
  }

  void _removeImage(int i) {
    setState(() => _images.removeAt(i));
    _sync();
  }

  void _removePdf(int i) {
    setState(() => _pdfs.removeAt(i));
    _sync();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final existing = _existing;
    final hasExisting = (existing?.horoscopeImages.isNotEmpty ?? false) ||
        (existing?.allPdfUrls.isNotEmpty ?? false);
    final hasNew = _images.isNotEmpty || _pdfs.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.uploadHoroscope,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.uploadHoroscopeHint,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          // ── Already uploaded (edit mode) ────────────────────────────────
          if (hasExisting) ...[
            HoroscopeDocumentsView.fromHoroscope(
              existing,
              title: l10n.horoscopeDocuments,
              emptyMessage: '',
            ),
            const SizedBox(height: 20),
          ],

          // ── Add buttons — Wrap so they stack on narrow phones ───────────
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _addButton(
                  icon: Icons.image_outlined,
                  label: l10n.addImages,
                  onTap: _pickImages),
              _addButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: l10n.addPdf,
                  onTap: _pickPdfs),
            ],
          ),
          const SizedBox(height: 16),

          if (!hasNew && !hasExisting)
            GestureDetector(
              onTap: _pickImages,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 34),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.upload_file_outlined,
                        size: 44, color: AppColors.primary),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(l10n.tapToSelectPdf,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[700])),
                    ),
                  ],
                ),
              ),
            ),

          // ── Newly picked files, previewed before upload ─────────────────
          if (_images.isNotEmpty) ...[
            Text(l10n.horoscopeImages,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            const SizedBox(height: 6),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                padding: EdgeInsets.zero,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _localThumb(i),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_pdfs.isNotEmpty) ...[
            Text(l10n.horoscopePdfs,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            const SizedBox(height: 6),
            for (var i = 0; i < _pdfs.length; i++) _localPdfRow(i),
            const SizedBox(height: 8),
          ],

          if (hasNew) ...[
            const SizedBox(height: 4),
            Text(l10n.filesSelected(_images.length + _pdfs.length),
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],

          const SizedBox(height: 32),
          GradientButton(
              onPressed: widget.onNext, text: l10n.continueLabel),
        ],
      ),
    );
  }

  Widget _addButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  /// Local (not yet uploaded) image with a tap-to-preview and a remove badge.
  Widget _localThumb(int i) => SizedBox(
        width: 88,
        height: 96,
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => showLocalImagePreview(context, _images[i]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(_images[i],
                    width: 88, height: 88, fit: BoxFit.cover),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: IconButton(
                iconSize: 18,
                icon: const CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, size: 13, color: Colors.white),
                ),
                onPressed: () => _removeImage(i),
              ),
            ),
          ],
        ),
      );

  /// Local (not yet uploaded) PDF row with the picked file's name.
  Widget _localPdfRow(int i) {
    final name = _pdfs[i].path.split(Platform.pathSeparator).last;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_outlined,
              color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          IconButton(
            tooltip: context.l10n.remove,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => _removePdf(i),
          ),
        ],
      ),
    );
  }
}
