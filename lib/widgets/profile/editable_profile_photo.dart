import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/dev_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_edit_provider.dart';
import '../../providers/service_providers.dart';
import '../../screens/profile/square_crop_screen.dart';
import '../common/fullscreen_photo_viewer.dart';
import '../common/network_photo.dart';

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

  /// Saves the new photo reference through the ONE profile-edit path
  /// ([ProfileEditController.save]).
  ///
  /// Everything that has to happen alongside it lives there and happens for
  /// every screen that edits a profile, not just this one: the Firestore write,
  /// the `users/{uid}.photoUrl` mirror, the chat participant refresh (§2), the
  /// deletion of the Cloudinary asset being replaced (§6/§24) and the eviction
  /// of its cached bytes (§25). Writing the document directly from here is what
  /// previously made this widget the odd one out.
  Future<void> _persist(String? url) async {
    final profile = widget.profile!;
    await ref.read(profileEditControllerProvider.notifier).save(
          updated: profile.withProfilePhoto(url),
          patch: {
            'profilePhotoUrl': url,
            // Multi-photo support is gone — clear any legacy extras (§1).
            // Both legacy arrays: the app still READS an image out of them for
            // a profile with no `profilePhotoUrl`, so a removed photo left in
            // one would come back.
            'additionalPhotos': <String>[],
            'photos': <String>[],
          },
        );
    if (!kBypassAuth) ref.invalidate(currentUserProvider);
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
    final uid = widget.profile!.userId;
    try {
      debugPrint('[ProfilePhoto] uid=$uid uploading ${cropped.path}');
      // Upload FIRST. Only a real `secure_url` returned by the upload is ever
      // saved — a failed upload throws before Firestore is touched, so the
      // current photo stays exactly as it was.
      final url = await ref.read(storageServiceProvider).uploadProfilePhoto(
            userId: uid,
            file: cropped,
            index: 0,
          );
      debugPrint('[ProfilePhoto] uid=$uid uploaded → $url');
      await _persist(url);
      if (mounted) _snack(context.l10n.photoUpdated);
    } catch (e, st) {
      debugPrint('[ProfilePhoto] uid=$uid photo change FAILED: $e\n$st');
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
          // Cached, with the person placeholder for BOTH "no photo" and "photo
          // could not load" — a bare NetworkImage painted an empty circle.
          PhotoAvatar(
            url: hasPhoto ? photoUrl : '',
            radius: widget.radius,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            placeholder:
                Icon(Icons.person, size: widget.radius, color: AppColors.primary),
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
