import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/aadhaar_details.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/service_providers.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/network_photo.dart';

/// Aadhaar Verification step — Aadhaar number + front/back images.
///
/// The details are stored in the strictly-gated `aadhaar/{userId}` record
/// (owner + admin only — never on the public profile), land UNVERIFIED, and
/// the admin verifies them (which stamps the profile's "Verified" badge).
/// Fully editable later through Edit Profile; an edit resets verification.
class StepAadhaar extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepAadhaar({super.key, required this.onNext});

  @override
  ConsumerState<StepAadhaar> createState() => _StepAadhaarState();
}

class _StepAadhaarState extends ConsumerState<StepAadhaar> {
  final _number = TextEditingController();
  final _picker = ImagePicker();
  File? _front;
  File? _back;
  AadhaarDetails? _existing; // saved record (edit mode / resumed draft)
  bool _loadedExisting = false;

  @override
  void initState() {
    super.initState();
    _number.text = (ref.read(profileCreationProvider).data['aadhaarNumber'] ??
            '')
        .toString();
    _front = ref.read(profileCreationProvider).aadhaarFront;
    _back = ref.read(profileCreationProvider).aadhaarBack;
    _loadExisting();
  }

  /// Prefills from the saved gated record so Edit Profile shows the current
  /// number/images instead of blank fields.
  Future<void> _loadExisting() async {
    try {
      final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      if (uid == null) return;
      final existing =
          await ref.read(firestoreServiceProvider).getAadhaar(uid);
      if (!mounted) return;
      setState(() {
        _existing = existing;
        _loadedExisting = true;
        if (_number.text.trim().isEmpty && existing != null) {
          _number.text = existing.number;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadedExisting = true);
    }
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _pick(bool front) async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (picked == null) return;
    setState(() {
      if (front) {
        _front = File(picked.path);
      } else {
        _back = File(picked.path);
      }
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _saveAndNext() {
    final number = _number.text.trim().replaceAll(' ', '');
    if (!AadhaarDetails.isValidNumber(number)) {
      _snack('Enter a valid 12-digit Aadhaar number');
      return;
    }
    // Both images are required — a newly picked file OR an already-saved one.
    final hasFront = _front != null || (_existing?.frontUrl.isNotEmpty ?? false);
    final hasBack = _back != null || (_existing?.backUrl.isNotEmpty ?? false);
    if (!hasFront || !hasBack) {
      _snack('Upload both the front and back images of your Aadhaar card');
      return;
    }
    ref
        .read(profileCreationProvider.notifier)
        .updateData({'aadhaarNumber': number});
    ref
        .read(profileCreationProvider.notifier)
        .setAadhaarImages(front: _front, back: _back);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aadhaar Verification', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text(
              'Your Aadhaar is used ONLY for verification. It is stored '
              'securely, is never shown to other members, and unlocks the '
              '"Verified" badge once our team approves it.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          if (_existing?.verified ?? false)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.success.withOpacity(0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified, color: AppColors.success, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Your Aadhaar is verified. Editing it will require '
                        're-verification by our team.',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            maxLength: 12,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Aadhaar Number *',
              hintText: '12-digit number',
              counterText: '',
              prefixIcon: const Icon(Icons.badge_outlined),
              filled: true,
              fillColor: Colors.grey[50],
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _imagePicker('Front Image *', _front,
                      _existing?.frontUrl ?? '', () => _pick(true))),
              const SizedBox(width: 12),
              Expanded(
                  child: _imagePicker('Back Image *', _back,
                      _existing?.backUrl ?? '', () => _pick(false))),
            ],
          ),
          if (!_loadedExisting)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Checking saved Aadhaar details…',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: 'Continue'),
        ],
      ),
    );
  }

  /// One upload tile: shows the newly-picked file, else the saved image, else
  /// the add prompt.
  Widget _imagePicker(
      String label, File? file, String savedUrl, VoidCallback onTap) {
    Widget content;
    if (file != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(file, fit: BoxFit.cover),
      );
    } else if (savedUrl.isNotEmpty) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: NetworkPhoto(url: savedUrl, fit: BoxFit.cover),
      );
    } else {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_a_photo_outlined,
              size: 30, color: Colors.grey),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 130,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: content,
          ),
        ),
        if (file != null || savedUrl.isNotEmpty)
          TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: Text('Change ${label.replaceAll(' *', '')}',
                style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact),
          ),
      ],
    );
  }
}
