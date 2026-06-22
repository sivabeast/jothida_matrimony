import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/dev_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_edit_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';

/// Photos section editor — manage the primary profile photo and up to 5
/// additional photos. Uploads go through the storage service (Cloudinary); the
/// resulting URLs are persisted to the profile so completion updates live.
class PhotosEditScreen extends ConsumerWidget {
  const PhotosEditScreen({super.key});

  static const int maxAdditional = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Photos'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) =>
            const Center(child: Text('Could not load your profile.')),
        data: (p) => p == null
            ? const Center(child: Text('Create your profile first.'))
            : _PhotosForm(profile: p),
      ),
    );
  }
}

class _PhotosForm extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _PhotosForm({required this.profile});

  @override
  ConsumerState<_PhotosForm> createState() => _PhotosFormState();
}

class _PhotosFormState extends ConsumerState<_PhotosForm> {
  bool _busy = false;

  ProfileModel get _p => ref.read(myProfileProvider).valueOrNull ?? widget.profile;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<String?> _upload(File file, int index) async {
    if (kBypassAuth) {
      _snack('Photo upload is not available in demo mode.');
      return null;
    }
    return ref.read(storageServiceProvider).uploadProfilePhoto(
          userId: _p.userId,
          file: file,
          index: index,
        );
  }

  Future<void> _persist({String? primary, List<String>? additional}) async {
    final p = _p;
    final updated = (primary != null ? p.withProfilePhoto(primary) : p)
        .copyWith(additionalPhotos: additional ?? p.additionalPhotos);
    final patch = <String, dynamic>{
      if (primary != null) 'profilePhotoUrl': primary,
      if (additional != null) 'additionalPhotos': additional,
    };
    await ref
        .read(profileEditControllerProvider.notifier)
        .save(updated: updated, patch: patch);
  }

  Future<void> _changePrimary() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    setState(() => _busy = true);
    try {
      final url = await _upload(File(x.path), 0);
      if (url != null) {
        await _persist(primary: url);
        if (mounted) _snack('Profile photo updated');
      }
    } catch (_) {
      if (mounted) _snack('Could not update the photo. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhotos() async {
    final remaining = PhotosEditScreen.maxAdditional - _p.additionalPhotos.length;
    if (remaining <= 0) {
      _snack('You can add up to ${PhotosEditScreen.maxAdditional} photos.');
      return;
    }
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    final files = picked.take(remaining).map((x) => File(x.path)).toList();
    setState(() => _busy = true);
    try {
      final urls = <String>[..._p.additionalPhotos];
      for (var i = 0; i < files.length; i++) {
        final url = await _upload(files[i], urls.length + 1);
        if (url != null) urls.add(url);
      }
      await _persist(additional: urls);
      if (mounted) _snack('${files.length} photo(s) added');
    } catch (_) {
      if (mounted) _snack('Could not add photos. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAdditional(String url) async {
    setState(() => _busy = true);
    try {
      final urls = _p.additionalPhotos.where((u) => u != url).toList();
      await _persist(additional: urls);
      if (mounted) _snack('Photo removed');
    } catch (_) {
      if (mounted) _snack('Could not remove photo. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAsPrimary(String url) async {
    setState(() => _busy = true);
    try {
      final p = _p;
      final oldPrimary = p.profilePhotoUrl;
      final additional = p.additionalPhotos.where((u) => u != url).toList();
      if (oldPrimary != null && oldPrimary.isNotEmpty) {
        additional.insert(0, oldPrimary);
      }
      await _persist(primary: url, additional: additional);
      if (mounted) _snack('Primary photo updated');
    } catch (_) {
      if (mounted) _snack('Could not update. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(myProfileProvider).valueOrNull ?? widget.profile;
    final primary = p.profilePhotoUrl ?? '';
    final additional = p.additionalPhotos;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Profile Photo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            Center(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: primary.isEmpty
                        ? Container(
                            width: 160,
                            height: 200,
                            color: AppColors.primary.withOpacity(0.08),
                            child: const Icon(Icons.person,
                                size: 64, color: AppColors.primary),
                          )
                        : GestureDetector(
                            onTap: () => showImageGallery(context, [primary]),
                            child: Image.network(primary,
                                width: 160, height: 200, fit: BoxFit.cover),
                          ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _changePrimary,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text('Additional Photos',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text('${additional.length}/${PhotosEditScreen.maxAdditional}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: [
                ...additional.map(_additionalTile),
                if (additional.length < PhotosEditScreen.maxAdditional)
                  _addTile(),
              ],
            ),
          ],
        ),
        if (_busy)
          Container(
            color: Colors.black.withOpacity(0.15),
            child: const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          ),
      ],
    );
  }

  Widget _additionalTile(String url) => Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              onTap: () => showImageGallery(context, [url]),
              child: Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                        color: AppColors.primary.withOpacity(0.08),
                        child: const Icon(Icons.broken_image_outlined,
                            color: AppColors.primary),
                      )),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9), shape: BoxShape.circle),
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                padding: EdgeInsets.zero,
                onSelected: (v) =>
                    v == 'primary' ? _setAsPrimary(url) : _removeAdditional(url),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'primary',
                      child: ListTile(
                          dense: true,
                          leading: Icon(Icons.star_outline),
                          title: Text('Set as primary'))),
                  PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                          dense: true,
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Delete',
                              style: TextStyle(color: Colors.red)))),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _addTile() => GestureDetector(
        onTap: _addPhotos,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withOpacity(0.4),
                style: BorderStyle.solid),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
              SizedBox(height: 4),
              Text('Add', style: TextStyle(color: AppColors.primary, fontSize: 12)),
            ],
          ),
        ),
      );
}
