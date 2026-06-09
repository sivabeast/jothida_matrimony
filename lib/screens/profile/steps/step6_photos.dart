import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';

class Step6Photos extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const Step6Photos({super.key, required this.onNext});

  @override
  ConsumerState<Step6Photos> createState() => _Step6State();
}

class _Step6State extends ConsumerState<Step6Photos> {
  final List<File> _photos = [];
  final _picker = ImagePicker();

  Future<void> _pickPhoto() async {
    if (_photos.length >= 5) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Maximum 5 photos allowed')));
      return;
    }
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
    if (picked != null) {
      setState(() => _photos.add(File(picked.path)));
    }
  }

  void _removePhoto(int index) => setState(() => _photos.removeAt(index));

  void _saveAndNext() {
    ref.read(profileCreationProvider.notifier).setPhotos(_photos);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Photos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Add up to 5 photos. First photo will be your profile photo.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _photos.length + (_photos.length < 5 ? 1 : 0),
            itemBuilder: (_, index) {
              if (index == _photos.length) {
                return GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 32, color: Colors.grey),
                        SizedBox(height: 4),
                        Text('Add Photo', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_photos[index], fit: BoxFit.cover),
                  ),
                  if (index == 0)
                    Positioned(
                      bottom: 4,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: AppColors.primary.withOpacity(0.8),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: const Text('Profile',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removePhoto(index),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (_photos.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Adding a photo increases your profile visibility by 3x.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
          GradientButton(onPressed: _saveAndNext, text: 'Next'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saveAndNext,
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }
}
