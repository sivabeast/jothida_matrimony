import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/dev_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/profile_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/demo_data_provider.dart';
import '../../../providers/interest_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/service_providers.dart';
import '../../../providers/subscription_provider.dart';

class MyProfileTab extends ConsumerWidget {
  const MyProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authNotifierProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final subAsync = ref.watch(activeSubscriptionProvider);

    // Real interest/match counts from Firestore — never hardcoded. Both
    // providers yield an empty list when signed-out or when there's no data,
    // and we fall back to 0 on loading/error too, so the stats only ever show
    // genuine counts (or 0).
    final receivedAsync = ref.watch(receivedInterestsProvider);
    final sentAsync = ref.watch(sentInterestsProvider);

    // "Interests" = people who expressed interest in this user (received).
    final interestsCount = receivedAsync.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );
    // "Matches" = mutually-accepted connections: accepted interests this user
    // received plus those they sent (the two sets are disjoint, so summing is
    // correct).
    final matchesCount = receivedAsync.maybeWhen(
          data: (list) => list.where((i) => i.isAccepted).length,
          orElse: () => 0,
        ) +
        sentAsync.maybeWhen(
          data: (list) => list.where((i) => i.isAccepted).length,
          orElse: () => 0,
        );

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
                      profile?.name ?? 'Complete your profile',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (profile != null) ...[
                      Text(
                        '${profile.age} yrs • ${profile.city}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      _buildStatusChip(profile.status),
                      if (profile.isMarried) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.gold.withOpacity(0.5)),
                          ),
                          child: const Text('🎉 Married',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStat('Views', profile?.viewCount.toString() ?? '0'),
                        _buildStat('Interests', interestsCount.toString()),
                        _buildStat('Matches', matchesCount.toString()),
                      ],
                    ),
                    if (profile != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/personal-details'),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit Profile'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                    // Profile editing now lives on the Personal Details page
                    // (Edit icon, top-right) — the single, primary place to
                    // manage the profile. Only the "Create Profile" action
                    // appears here, and only when no profile exists yet.
                    if (profile == null) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/profile/create'),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Profile'),
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
                : _buildSubCard(sub.plan, sub.daysRemaining),
          ),
          const SizedBox(height: 16),
          // Menu items
          _buildMenuItem(context, Icons.person_outline, 'Personal Details', '/personal-details'),
          _buildMenuItem(context, Icons.auto_awesome_outlined, 'Horoscope Details', '/horoscope'),
          _buildMenuItem(context, Icons.tune, 'Partner Preferences', '/partner-preferences'),
          // "Porutham Analysis" self-serve removed — astrologer consultation
          // (Match → Compatibility → Connect Astrologer) is the only analysis flow.
          _buildMenuItem(context, Icons.workspace_premium_outlined, 'Subscription Plans', '/subscription'),
          _buildMenuItem(context, Icons.settings_outlined, 'Settings', '/settings'),
          _buildMenuItem(context, Icons.help_outline, 'Help & Support', '/help'),
          _buildMenuItem(context, Icons.privacy_tip_outlined, 'Privacy Policy', '/privacy-policy'),
          _buildMenuItem(context, Icons.description_outlined, 'Terms & Conditions', '/terms'),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              debugPrint('[MyProfileTab] Sign Out tapped — showing confirmation');
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Sign Out'),
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

  Widget _buildStatusChip(String status) {
    // No admin-approval step for normal users: once the profile is complete the
    // account is ACTIVE. Legacy documents saved as 'pending' (before approval
    // was removed) therefore also render as ACTIVE — no Firestore migration
    // needed. Only explicit moderation states stay visually distinct.
    final String label;
    final Color color;
    switch (status) {
      case 'rejected':
        label = 'REJECTED';
        color = Colors.red;
        break;
      case 'blocked':
        label = 'BLOCKED';
        color = Colors.red;
        break;
      default:
        label = 'ACTIVE';
        color = Colors.green;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStat(String label, String value) => Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      );

  Widget _buildUpgradeCard(BuildContext context) => Card(
        color: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: const Icon(Icons.workspace_premium, color: AppColors.gold),
          title: const Text('Upgrade to Premium',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: const Text('Get unlimited access & free astrologer consultations',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          onTap: () => context.push('/subscription'),
        ),
      );

  Widget _buildSubCard(String plan, int daysLeft) => Card(
        color: AppColors.gold.withOpacity(0.1),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.gold.withOpacity(0.3))),
        child: ListTile(
          leading: const Icon(Icons.workspace_premium, color: AppColors.gold),
          title: Text(
            '${plan[0].toUpperCase()}${plan.substring(1)} Plan',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('$daysLeft days remaining'),
        ),
      );

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
      ref.invalidate(myProfileProvider);
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
      if (mounted) _snack('Profile photo updated');
    } catch (_) {
      if (mounted) _snack('Could not update photo. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    if (widget.profile == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Photo'),
        content: const Text('Remove your profile photo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _persist(null);
      if (mounted) _snack('Photo removed');
    } catch (_) {
      if (mounted) _snack('Could not remove photo. Please try again.');
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
    final hasPhoto = profile.photos.isNotEmpty;
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
                title: const Text('View Photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _viewPhoto(profile.photos.first);
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: Text(hasPhoto ? 'Change Photo' : 'Upload Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _changePhoto();
              },
            ),
            if (hasPhoto)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Remove Photo',
                    style: TextStyle(color: AppColors.error)),
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
    final hasPhoto = profile?.photos.isNotEmpty ?? false;
    return GestureDetector(
      onTap: profile == null ? null : _showOptions,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 52,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            backgroundImage:
                hasPhoto ? NetworkImage(profile!.photos.first) : null,
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
