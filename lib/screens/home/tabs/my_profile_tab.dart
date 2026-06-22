import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/dev_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../models/profile_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/demo_data_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/service_providers.dart';
import '../../../providers/subscription_provider.dart';
import '../../../widgets/home/profile_completion_card.dart';

class MyProfileTab extends ConsumerWidget {
  const MyProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final subAsync = ref.watch(activeSubscriptionProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile header card
          profileAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (profile) => Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _ProfilePhotoAvatar(profile: profile),
                    const SizedBox(height: 12),
                    Text(
                      profile?.name ?? context.l10n.completeProfile,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (profile != null) ...[
                      Text(
                        '${profile.age} yrs • ${profile.city}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      const ProfileStatusBadge(showPercent: true),
                      if (profile.isMarried) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.gold.withOpacity(0.5)),
                          ),
                          child: Text('🎉 ${context.l10n.married}',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                    // Profile editing lives on the Personal Details page (and the
                    // menu items below) — the single, primary place to manage the
                    // profile. Only the "Create Profile" action appears here, and
                    // only when no profile exists yet.
                    if (profile == null) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/profile/create'),
                        icon: const Icon(Icons.add),
                        label: Text(context.l10n.createProfile),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Subscription card
          subAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (sub) => sub == null
                ? _buildUpgradeCard(context)
                : _buildSubCard(context, sub.plan, sub.daysRemaining),
          ),
          const SizedBox(height: 16),
          // Menu items
          _buildMenuItem(context, Icons.person_outline, context.l10n.personalDetails, '/personal-details'),
          _buildMenuItem(context, Icons.auto_awesome_outlined, context.l10n.horoscopeDetails, '/horoscope'),
          _buildMenuItem(context, Icons.folder_open_outlined, 'Horoscope Documents', '/horoscope-files'),
          _buildMenuItem(context, Icons.family_restroom_outlined, context.l10n.familyDetails, '/family-tree'),
          _buildMenuItem(context, Icons.tune, context.l10n.partnerPreferences, '/partner-preferences'),
          // Match analysis the user booked with astrologers (porutham reports).
          _buildMenuItem(context, Icons.insights_outlined, 'My Match Analysis', '/my-analysis'),
          _buildMenuItem(context, Icons.workspace_premium_outlined, context.l10n.subscriptionPlans, '/subscription'),
          _buildMenuItem(context, Icons.settings_outlined, context.l10n.settings, '/settings'),
          _buildMenuItem(context, Icons.help_outline, context.l10n.helpSupport, '/help'),
          _buildMenuItem(context, Icons.privacy_tip_outlined, context.l10n.privacyPolicy, '/privacy-policy'),
          _buildMenuItem(context, Icons.description_outlined, context.l10n.termsConditions, '/terms'),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(context.l10n.logout, style: const TextStyle(color: Colors.red)),
            onTap: () async {
              debugPrint('[MyProfileTab] Sign Out tapped — showing confirmation');
              final l10n = context.l10n;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.logout),
                  content: Text(l10n.signOutConfirm),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: Text(l10n.logout),
                    ),
                  ],
                ),
              );
              if (confirmed != true) {
                debugPrint('[MyProfileTab] Sign Out cancelled by user.');
                return;
              }
              debugPrint('[MyProfileTab] Sign Out confirmed — calling signOut()');
              await ref.read(authNotifierProvider.notifier).signOut();
              debugPrint('[MyProfileTab] signOut() complete — '
                  'router redirect will handle navigation');
              // Safety-net: if the GoRouterRefreshStream fires after this
              // widget's context is gone, the explicit go() ensures navigation.
              if (context.mounted) context.go('/account-type');
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Colors.red[50],
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeCard(BuildContext context) => Card(
        color: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: const Icon(Icons.workspace_premium, color: AppColors.gold),
          title: Text(context.l10n.upgradeToPremium,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(context.l10n.premiumSubtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          onTap: () => context.push('/subscription'),
        ),
      );

  Widget _buildSubCard(BuildContext context, String plan, int daysLeft) {
    final l10n = context.l10n;
    final planName = switch (plan) {
      'basic' => l10n.basicPlan,
      'medium' => l10n.mediumPlan,
      'premium' => l10n.premiumPlan,
      _ => l10n.freePlan,
    };
    return Card(
      color: AppColors.gold.withOpacity(0.1),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.gold.withOpacity(0.3))),
      child: ListTile(
        leading: const Icon(Icons.workspace_premium, color: AppColors.gold),
        title: Text(planName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(l10n.daysRemaining(daysLeft)),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String title, String route) =>
      ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          debugPrint('[MyProfileTab] menu "$title" → $route');
          context.push(route);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

/// Tappable profile avatar with a camera badge. Tapping opens View / Change /
/// Remove options. Changing uploads via Cloudinary and writes `profilePhotoUrl`
/// to Firestore (then refreshes the profile); removing clears it. Editing never
/// re-opens onboarding.
class _ProfilePhotoAvatar extends ConsumerStatefulWidget {
  final ProfileModel? profile;
  const _ProfilePhotoAvatar({required this.profile});

  @override
  ConsumerState<_ProfilePhotoAvatar> createState() => _ProfilePhotoAvatarState();
}

class _ProfilePhotoAvatarState extends ConsumerState<_ProfilePhotoAvatar> {
  bool _busy = false;

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _persist(String? url) async {
    final profile = widget.profile!;
    if (kBypassAuth) {
      ref.read(demoProfilesProvider.notifier).upsert(profile.withProfilePhoto(url));
    } else {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(profile.id, {'profilePhotoUrl': url});
      // Keep the denormalized users/{uid}.photoUrl in sync so the new image
      // also shows in the home header, chats and elsewhere that reads it.
      await ref
          .read(firestoreServiceProvider)
          .updateUserPhoto(profile.userId, url);
      // Both providers are one-shot (FutureProvider) — invalidate so every
      // screen re-reads the updated photo immediately.
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
              title: Text(hasPhoto ? context.l10n.changePhoto : context.l10n.uploadPhoto),
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
    // Use the dedicated profile photo (not the gallery list) so removing it
    // always falls back to the placeholder, even if gallery photos exist.
    final photoUrl = profile?.profilePhotoUrl ?? '';
    final hasPhoto = photoUrl.isNotEmpty;
    return GestureDetector(
      onTap: profile == null ? null : _showOptions,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 52,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
            child: hasPhoto
                ? null
                : const Icon(Icons.person, size: 52, color: AppColors.primary),
          ),
          if (_busy)
            const Positioned.fill(
              child: DecoratedBox(
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                child: Center(
                    child: CircularProgressIndicator(color: Colors.white)),
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
