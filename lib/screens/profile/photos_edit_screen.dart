import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/dev_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_edit_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/fullscreen_photo_viewer.dart';
import 'square_crop_screen.dart';

/// Profile Photo editor — exactly ONE photo per member (§1).
///
/// Picking an image of any aspect ratio opens the mandatory 1:1 crop screen;
/// only the cropped square is uploaded, and it REPLACES the current photo.
/// There is no gallery and no "additional photos" — that support was removed
/// completely.
class PhotosEditScreen extends ConsumerWidget {
  const PhotosEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.profilePhoto),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) =>
            Center(child: Text(context.l10n.couldNotLoadYourProfile)),
        data: (p) => p == null
            ? Center(child: Text(context.l10n.createYourProfileFirst))
            : _PhotoForm(profile: p),
      ),
    );
  }
}

class _PhotoForm extends ConsumerStatefulWidget {
  final ProfileModel profile;
  const _PhotoForm({required this.profile});

  @override
  ConsumerState<_PhotoForm> createState() => _PhotoFormState();
}

class _PhotoFormState extends ConsumerState<_PhotoForm> {
  bool _busy = false;

  ProfileModel get _p =>
      ref.read(myProfileProvider).valueOrNull ?? widget.profile;

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  /// Pick → MANDATORY square crop → upload → replace.
  Future<void> _changePhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    // The crop screen is not optional: backing out of it saves nothing.
    final cropped = await SquareCropScreen.open(context, File(picked.path));
    if (cropped == null || !mounted) return;

    if (kBypassAuth) {
      _snack(context.l10n.photoUploadNotInDemo);
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadProfilePhoto(
            userId: _p.userId,
            file: cropped,
            index: 0,
          );
      final p = _p;
      await ref.read(profileEditControllerProvider.notifier).save(
            updated: p.withProfilePhoto(url),
            patch: {'profilePhotoUrl': url, 'additionalPhotos': <String>[]},
          );
      // Keep the denormalized users/{uid}.photoUrl in sync so the same 1:1
      // image shows in the header, chats and everywhere else.
      await ref.read(firestoreServiceProvider).updateUserPhoto(p.userId, url);
      if (mounted) _snack(context.l10n.photoUpdated);
    } catch (_) {
      if (mounted) _snack(context.l10n.couldNotUpdatePhoto);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.removePhoto),
        content: Text(l10n.removePhotoConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final p = _p;
      await ref.read(profileEditControllerProvider.notifier).save(
            updated: p.withProfilePhoto(null),
            patch: {'profilePhotoUrl': null, 'additionalPhotos': <String>[]},
          );
      await ref.read(firestoreServiceProvider).updateUserPhoto(p.userId, null);
      if (mounted) _snack(context.l10n.photoRemoved);
    } catch (_) {
      if (mounted) _snack(context.l10n.couldNotRemovePhoto);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = ref.watch(myProfileProvider).valueOrNull ?? widget.profile;
    final photo = p.profilePhotoUrl ?? '';

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l10n.profilePhoto,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            Text(l10n.profilePhotoOneOnly,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
            const SizedBox(height: 16),
            Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: photo.isEmpty
                              ? Container(
                                  color: AppColors.primary.withOpacity(0.08),
                                  child: const Icon(Icons.person,
                                      size: 72, color: AppColors.primary),
                                )
                              : GestureDetector(
                                  onTap: () =>
                                      FullScreenPhotoViewer.open(context, photo),
                                  child: Image.network(photo,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                            color: AppColors.primary
                                                .withOpacity(0.08),
                                            child: const Icon(
                                                Icons.broken_image_outlined,
                                                color: AppColors.primary),
                                          )),
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _changePhoto,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (photo.isNotEmpty)
              Center(
                child: Text(l10n.tapPhotoToEnlarge,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _changePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(photo.isEmpty ? l10n.uploadPhoto : l10n.changePhoto),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (photo.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: TextButton.icon(
                  onPressed: _removePhoto,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.removePhoto),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                ),
              ),
            ],
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
}
