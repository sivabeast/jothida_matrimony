import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/network_photo.dart';

/// Profile Photo step — exactly ONE photo (the multi-photo upload was
/// removed per spec). Picking again replaces the current choice. In Edit
/// Profile the existing photo is shown and kept unless replaced.
class Step6Photos extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const Step6Photos({super.key, required this.onNext});

  @override
  ConsumerState<Step6Photos> createState() => _Step6State();
}

class _Step6State extends ConsumerState<Step6Photos> {
  File? _photo;
  final _picker = ImagePicker();

  /// Existing photo URL (edit mode) — kept unless a new file is picked.
  String get _existingUrl {
    final photos = ref.read(profileCreationProvider).data['photos'];
    if (photos is List && photos.isNotEmpty) return photos.first.toString();
    return '';
  }

  @override
  void initState() {
    super.initState();
    final picked = ref.read(profileCreationProvider).photos;
    if (picked.isNotEmpty) _photo = picked.first;
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
    if (picked != null) {
      setState(() => _photo = File(picked.path)); // replaces — only ONE photo
    }
  }

  void _saveAndNext() {
    ref
        .read(profileCreationProvider.notifier)
        .setPhotos(_photo == null ? const [] : [_photo!]);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasExisting = _existingUrl.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.profilePhoto,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.profilePhotoSubtitle,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                width: 220,
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                clipBehavior: Clip.antiAlias,
                child: _photo != null
                    ? Image.file(_photo!, fit: BoxFit.cover)
                    : hasExisting
                        ? NetworkPhoto(url: _existingUrl, fit: BoxFit.cover)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_a_photo_outlined,
                                  size: 44, color: Colors.grey),
                              const SizedBox(height: 10),
                              Text(l10n.addPhoto,
                                  style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_photo != null || hasExisting)
            Center(
              child: TextButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(l10n.changePhoto),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ),
          const SizedBox(height: 12),
          if (_photo == null && !hasExisting)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.photoVisibilityTip,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
          GradientButton(onPressed: _saveAndNext, text: l10n.continueLabel),
        ],
      ),
    );
  }
}
