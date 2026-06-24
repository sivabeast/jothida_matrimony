import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import 'app_logo.dart';

/// The main navigation Drawer opened from the header menu icon.
///
/// Spec items: My Profile · Edit Profile · Horoscope Profiles · Premium Plans ·
/// Wallet / Payments · Notifications · Support · Privacy Policy · Rate App ·
/// Logout. Profile lives here (it is no longer a bottom-navigation tab).
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final name = (profile?.fullName.trim().isNotEmpty ?? false)
        ? profile!.fullName.trim()
        : (user?.displayName?.trim().isNotEmpty ?? false)
            ? user!.displayName!.trim()
            : 'Guest';
    final photo = (profile?.profilePhotoUrl?.isNotEmpty ?? false)
        ? profile!.profilePhotoUrl!
        : (user?.photoUrl ?? '');

    return Drawer(
      child: Column(
        children: [
          _header(context, name, photo),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _item(context, Icons.person_outline, 'My Profile',
                    () => context.push('/my-profile')),
                _item(context, Icons.edit_outlined, 'Edit Profile', () {
                  final id = profile?.id;
                  context.push(
                      id != null ? '/profile/$id/edit' : '/personal-details');
                }),
                _item(context, Icons.auto_awesome_outlined,
                    'Horoscope Profiles', () => context.push('/horoscope')),
                _item(context, Icons.workspace_premium_outlined,
                    'Premium Plans', () => context.push('/subscription')),
                _item(context, Icons.account_balance_wallet_outlined,
                    'Wallet / Payments', () => context.push('/payments')),
                _item(context, Icons.notifications_none, 'Notifications',
                    () => _openNotifications(context)),
                const Divider(height: 1),
                _item(context, Icons.help_outline, 'Support',
                    () => context.push('/help')),
                _item(context, Icons.privacy_tip_outlined, 'Privacy Policy',
                    () => context.push('/privacy-policy')),
                _item(context, Icons.star_outline, 'Rate App',
                    () => _rateApp(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          _item(context, Icons.logout, 'Logout', () => _logout(context, ref),
              color: AppColors.error),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String name, String photo) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
            20, MediaQuery.of(context).padding.top + 20, 20, 20),
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AppLogo(size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(context.l10n.appTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 16,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white24,
                  backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                  child: photo.isEmpty
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _item(BuildContext context, IconData icon, String label,
          VoidCallback onTap,
          {Color? color}) =>
      ListTile(
        leading: Icon(icon, color: color ?? AppColors.primary),
        title: Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w500, fontSize: 14.5)),
        onTap: () {
          Navigator.of(context).pop(); // close the drawer first
          onTap();
        },
      );

  void _openNotifications(BuildContext context) {
    context.push('/notifications');
  }

  void _rateApp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rate Jothida Matrimony'),
        content: const Text(
            'Enjoying the app? Your rating helps other families find their '
            'perfect match. App-store rating opens here once published.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Maybe later')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Rate'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logout),
        content: Text(l10n.signOutConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authNotifierProvider.notifier).signOut();
    if (context.mounted) context.go('/account-type');
  }
}
