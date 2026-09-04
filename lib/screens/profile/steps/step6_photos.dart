import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/network_photo.dart';
import '../../../widgets/common/step_actions.dart';
import '../square_crop_screen.dart';

/// Profile Photo step — exactly ONE photo (§1; multi-photo upload was removed
/// completely). The photo may come from the CAMERA or the GALLERY; any aspect
/// ratio may be picked, but the image ALWAYS goes through the mandatory 1:1
/// crop screen before it is kept, and only the cropped square is uploaded.
/// Picking again replaces the current choice, and Remove clears it. In Edit
/// Profile the existing photo is shown and kept unless replaced.
///
/// The whole step is OPTIONAL: Continue keeps whatever is (or is not) there,
/// and Skip moves on without touching it.
class Step6Photos extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  /// Moves on without saving anything. Null hides the Skip button.
  final VoidCallback? onSkip;
  const Step6Photos({super.key, required this.onNext, this.onSkip});

  @override
  ConsumerState<Step6Photos> createState() => _Step6State();
}

class _Step6State extends ConsumerState<Step6Photos> {
  File? _photo;
  final _picker = ImagePicker();

  /// Existing photo URL (edit mode) — kept unless a new file is picked, or the
  /// member explicitly removes it.
  String _existingUrl = '';

  @override
  void initState() {
    super.initState();
    final state = ref.read(profileCreationProvider);
    final picked = state.photos;
    if (picked.isNotEmpty) _photo = picked.first;
    final photos = state.data['photos'];
    if (photos is List && photos.isNotEmpty) {
      _existingUrl = photos.first.toString();
    }
  }

  bool get _hasPhoto => _photo != null || _existingUrl.isNotEmpty;

  /// Camera or gallery — asked once, in a sheet, rather than assuming the
  /// member has already taken the photo they want to use.
  Future<void> _choosePhoto() async {
    final l10n = context.l10n;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: Text(l10n.takePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: Text(l10n.chooseFromGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickPhoto(source);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    // Pick at full quality — the crop screen handles resizing/compression.
    final picked = await _picker.pickImage(source: source);
    if (picked == null || !mounted) return;
    // MANDATORY 1:1 crop: cancelling it keeps the previous selection.
    final cropped = await SquareCropScreen.open(context, File(picked.path));
    if (cropped == null || !mounted) return;
    setState(() {
      _photo = cropped; // replaces — only ONE photo
      _existingUrl = ''; // a new pick supersedes whatever was stored
    });
  }

  void _removePhoto() => setState(() {
        _photo = null;
        _existingUrl = '';
      });

  void _saveAndNext() {
    final notifier = ref.read(profileCreationProvider.notifier);
    notifier.setPhotos(_photo == null ? const [] : [_photo!]);
    // Removing an existing photo has to clear the STORED url too: the submit
    // keeps `data['photos']` whenever no new file was picked, so without this
    // a removal would silently put the old photo straight back. Written here
    // and not in _removePhoto so that Skip really does change nothing.
    if (_photo == null && _existingUrl.isEmpty) {
      notifier.updateData({'photos': const <String>[]});
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.profilePhoto,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: _choosePhoto,
              child: Container(
                // 1:1 preview — exactly what will be saved and shown app-wide.
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                clipBehavior: Clip.antiAlias,
                child: _photo != null
                    ? Image.file(_photo!, fit: BoxFit.cover)
                    : _existingUrl.isNotEmpty
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
          if (_hasPhoto) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _choosePhoto,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(l10n.changePhoto),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.primary),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _removePhoto,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(l10n.removePhoto),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          StepActions(onContinue: _saveAndNext, onSkip: widget.onSkip),
        ],
      ),
    );
  }
}
