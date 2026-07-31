import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/dev_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/demo_data_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../screens/profile/square_crop_screen.dart';
import '../common/fullscreen_photo_viewer.dart';

/// Tappable profile avatar with a camera badge. Tapping opens View / Change /
/// Remove options. Changing runs the picked image through the MANDATORY 1:1
/// crop screen (§1), uploads the cropped square via Cloudinary and writes
/// `profilePhotoUrl` to Firestore (then refreshes the profile); removing clears
/// it. There is only ever ONE photo — a new upload replaces the old one.
/// Editing never re-opens onboarding.
///
/// Reused by the Profile Details page so "Change Profile Photo" lives next to
/// the rest of the profile information.
class EditableProfilePhoto extends ConsumerStatefulWidget {
  final ProfileModel? profile;
  final double radius;
  const EditableProfilePhoto({super.key, required this.profile, this.radius = 52});

  @override
  ConsumerState<EditableProfilePhoto> createState() =>
      _EditableProfilePhotoState();
}

class _EditableProfilePhotoState extends ConsumerState<EditableProfilePhoto> {
  bool _busy = false;

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _persist(String? url) async {
    final profile = widget.profile!;
    if (kBypassAuth) {
      ref
          .read(demoProfilesProvider.notifier)
          .upsert(profile.withProfilePhoto(url));
    } else {
      await ref.read(profileRepositoryProvider).updateProfile(profile.id, {
        'profilePhotoUrl': url,
        // Multi-photo support is gone — clear any legacy extras (§1).
        'additionalPhotos': <String>[],
      });
      // Keep the denormalized users/{uid}.photoUrl in sync so the new image
      // also shows in the home header, chats and elsewhere that reads it.
      await ref
          .read(firestoreServiceProvider)
          .updateUserPhoto(profile.userId, url);
      ref.invalidate(myProfileProvider);
      ref.invalidate(currentUserProvider);
    }
  }

  Future<void> _changePhoto() async {
    // Full-quality pick: the crop screen does the resizing/compression, so no
    // imageQuality/maxWidth here — cropping a pre-shrunk image loses detail.
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || widget.profile == null || !mounted) return;

    // MANDATORY 1:1 crop — backing out of it saves nothing.
    final cropped = await SquareCropScreen.open(context, File(picked.path));
    if (cropped == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadProfilePhoto(
            userId: widget.profile!.userId,
            file: cropped,
            index: 0,
          );
      await _persist(url);
      if (mounted) _snack(context.l10n.photoUpdated);
    } catch (_) {
      if (mounted) _snack(context.l10n.couldNotUpdatePhoto);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    if (widget.profile == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.removePhoto),
        content: Text(context.l10n.removePhotoConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _persist(null);
      if (mounted) _snack(context.l10n.photoRemoved);
    } catch (_) {
      if (mounted) _snack(context.l10n.couldNotRemovePhoto);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Full screen, dark background, zoom + pan, explicit close (§10).
  void _viewPhoto(String url) => FullScreenPhotoViewer.open(context, url);

  void _showOptions() {
    final profile = widget.profile;
    if (profile == null) return;
    final photoUrl = profile.profilePhotoUrl ?? '';
    final hasPhoto = photoUrl.isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.visibility_outlined,
                    color: AppColors.primary),
                title: Text(context.l10n.viewPhoto),
                onTap: () {
                  Navigator.pop(ctx);
                  _viewPhoto(photoUrl);
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: Text(
                  hasPhoto ? context.l10n.changePhoto : context.l10n.uploadPhoto),
              onTap: () {
                Navigator.pop(ctx);
                _changePhoto();
              },
            ),
            if (hasPhoto)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: AppColors.error),
                title: Text(context.l10n.removePhoto,
                    style: const TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final photoUrl = profile?.profilePhotoUrl ?? '';
    final hasPhoto = photoUrl.isNotEmpty;
    return GestureDetector(
      onTap: profile == null ? null : _showOptions,
      child: Stack(
        children: [
          CircleAvatar(
            radius: widget.radius,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
            child: hasPhoto
                ? null
                : Icon(Icons.person,
                    size: widget.radius, color: AppColors.primary),
          ),
          if (_busy)
            const Positioned.fill(
              child: DecoratedBox(
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                child:
                    Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
          if (profile != null && !_busy)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
                child:
                    const Icon(Icons.camera_alt, size: 16, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
