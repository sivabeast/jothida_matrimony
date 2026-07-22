import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';

/// Horoscope Upload step — optionally attach a horoscope PDF. Mirrors the
/// website's separate "Upload" step. The file is uploaded to storage on submit
/// (see [ProfileCreationNotifier.submitProfile]); skipping is always allowed.
class StepHoroscopeUpload extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepHoroscopeUpload({super.key, required this.onNext});

  @override
  ConsumerState<StepHoroscopeUpload> createState() =>
      _StepHoroscopeUploadState();
}

class _StepHoroscopeUploadState extends ConsumerState<StepHoroscopeUpload> {
  File? _pdf;

  /// Existing uploaded PDF URL (edit mode) — kept unless a new file is picked.
  String get _existingUrl {
    final h = ref.read(profileCreationProvider).data['horoscopeDetails'];
    if (h is Map) {
      final url = (h['horoscopePdfUrl'] as String?) ?? '';
      return url;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _pdf = ref.read(profileCreationProvider).horoscopePdf;
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    if (path != null) {
      setState(() => _pdf = File(path));
      ref.read(profileCreationProvider.notifier).setHoroscopePdf(File(path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasExisting = _existingUrl.isNotEmpty;
    final fileName = _pdf != null ? _pdf!.path.split(Platform.pathSeparator).last : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.uploadHoroscope,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.uploadHoroscopeSubtitle,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _pickPdf,
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
                  Icon(
                    fileName != null || hasExisting
                        ? Icons.picture_as_pdf
                        : Icons.upload_file_outlined,
                    size: 44,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    fileName ??
                        (hasExisting
                            ? l10n.horoscopePdfAttached
                            : l10n.tapToSelectPdf),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ),
          if (fileName != null || hasExisting) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _pickPdf,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(l10n.changePdf),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ),
          ],
          const SizedBox(height: 32),
          GradientButton(
              onPressed: widget.onNext, text: l10n.continueLabel),
        ],
      ),
    );
  }
}
