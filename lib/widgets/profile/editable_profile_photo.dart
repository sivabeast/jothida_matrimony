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

/// Tappable profile avatar with a camera badge. Tapping opens View / Change /
/// Remove options. Changing uploads via Cloudinary and writes `profilePhotoUrl`
/// to Firestore (then refreshes the profile); removing clears it. Editing never
/// re-opens onboarding.
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
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(profile.id, {'profilePhotoUrl': url});
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
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || widget.profile == null) return;
    setState(() => _busy = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadProfilePhoto(
            userId: widget.profile!.userId,
            file: File(picked.path),
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

  void _viewPhoto(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(40),
                          child: Icon(Icons.broken_image,
                              color: Colors.white, size: 64),
                        )),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
