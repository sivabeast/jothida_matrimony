import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_account_model.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../../../providers/service_providers.dart';
import '../profile/astrologer_certificates_screen.dart';
import '../profile/astrologer_profile_sections.dart';
import 'astrologer_common.dart';

/// The astrologer's profile — a professional account-management home: identity
/// header (photo, name, rating, location) + sections that each open their own
/// view/edit screen. Editing happens directly on those screens; the astrologer
/// is never sent back through onboarding/registration.
class AstrologerProfileTab extends ConsumerStatefulWidget {
  const AstrologerProfileTab({super.key});

  @override
  ConsumerState<AstrologerProfileTab> createState() => _AstrologerProfileTabState();
}

class _AstrologerProfileTabState extends ConsumerState<AstrologerProfileTab> {
  bool _uploadingPhoto = false;

  Future<void> _changePhoto() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final account = ref.read(myAstrologerAccountProvider);
    if (account == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadProfilePhoto(
            userId: account.id,
            file: File(picked.path),
            index: 0,
          );
      await ref
          .read(myAstrologerAccountProvider.notifier)
          .saveAccount(account.copyWith(photoUrl: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile photo updated')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not update photo — please try again.')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(myAstrologerAccountProvider);
    if (account == null) return const AstrologerLoading();

    final location = [account.city, account.state, account.country]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        _header(account, location),
        const SizedBox(height: 20),
        _menuItem(Icons.person_outline, 'Personal Details',
            'Name, gender, contact, location',
            () => _open(const AstrologerPersonalDetailsScreen())),
        _menuItem(Icons.auto_awesome_outlined, 'Professional Details',
            'Experience, specializations, qualification, languages',
            () => _open(const AstrologerProfessionalDetailsScreen())),
        _menuItem(Icons.payments_outlined, 'Consultation Details',
            'Fee, timings, online/offline, about me',
            () => _open(const AstrologerConsultationDetailsScreen())),
        _menuItem(Icons.workspace_premium_outlined, 'Certificates',
            'Upload & manage verification documents',
            () => _open(const AstrologerCertificatesScreen())),
        _menuItem(Icons.settings_outlined, 'Account Settings',
            'Verification status & sign out',
            () => _open(const AstrologerAccountSettingsScreen())),
      ],
    );
  }

  Widget _header(AstrologerAccount account, String location) => Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: account.photoUrl.isNotEmpty
                    ? NetworkImage(account.photoUrl)
                    : null,
                child: account.photoUrl.isEmpty
                    ? const Icon(Icons.person, size: 46, color: AppColors.primary)
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: _uploadingPhoto ? null : _changePhoto,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                    child: _uploadingPhoto
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.camera_alt,
                            size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(account.fullName,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 16, color: AppColors.gold),
                const SizedBox(width: 4),
                Text(account.rating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('· ${account.reviewCount} Reviews',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12.5)),
              ],
            ),
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on_outlined,
                    size: 15, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(location,
                    style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              ],
            ),
          ],
        ],
      );

  Widget _menuItem(
          IconData icon, String title, String subtitle, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            trailing: const Icon(Icons.arrow_forward_ios, size: 15),
            onTap: onTap,
          ),
        ),
      );
}
