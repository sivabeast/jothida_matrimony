import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import 'app_logo.dart';

/// The main navigation Drawer opened from the header menu icon.
///
/// A single, categorised menu — grouped under PROFILE · MATCHES · ASTROLOGY ·
/// MEMBERSHIP · SETTINGS, with Logout at the very bottom (it lives ONLY here).
/// There is intentionally no "My Profile" / "Edit Profile" item — profile
/// management is reached through the PROFILE group's dedicated pages.
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── 👤 PROFILE ───────────────────────────────────────────────
                _section('👤  PROFILE'),
                _item(context, Icons.person_outline, 'Profile Details',
                    () => context.push('/personal-details')),
                _item(context, Icons.family_restroom_outlined, 'Family Details',
                    () => context.push('/family-details')),
                _item(context, Icons.auto_awesome_outlined, 'Horoscope Details',
                    () => context.push('/horoscope')),
                _item(context, Icons.tune, 'Partner Preferences',
                    () => context.push('/partner-preferences')),

                // ── 💖 MATCHES ───────────────────────────────────────────────
                _section('💖  MATCHES'),
                _item(context, Icons.favorite_border, 'My Matches',
                    () => _openTab(context, ref, 1)),
                _item(context, Icons.send_outlined, 'Interests Sent',
                    () => context.push('/interests?tab=sent')),
                _item(context, Icons.mark_email_unread_outlined,
                    'Interests Received',
                    () => context.push('/interests?tab=received')),
                _item(context, Icons.chat_bubble_outline, 'Messages',
                    () => context.push('/chats')),
                _item(context, Icons.insights_outlined, 'Match Analysis',
                    () => context.push('/my-analysis')),

                // ── 🧿 ASTROLOGY ─────────────────────────────────────────────
                _section('🧿  ASTROLOGY'),
                _item(context, Icons.favorite_outline, 'Horoscope Matching',
                    () => context.push('/horoscope-matching')),
                _item(context, Icons.insights_outlined, 'Match Analysis',
                    () => context.push('/my-analysis')),

                // ── 💳 MEMBERSHIP ────────────────────────────────────────────
                _section('💳  MEMBERSHIP'),
                _item(context, Icons.workspace_premium_outlined,
                    'Subscription Plans', () => context.push('/subscription')),
                _item(context, Icons.account_balance_wallet_outlined,
                    'Wallet / Payments', () => context.push('/payments')),

                const SizedBox(height: 8),
                const Divider(height: 1),
                _item(context, Icons.settings_outlined, 'Settings',
                    () => context.push('/settings')),
              ],
            ),
          ),
          const Divider(height: 1),
          // Logout is deliberately NOT routed through [_item] (which pops the
          // drawer first): popping would deactivate this context before the
          // confirmation dialog and post-logout navigation run. Instead the
          // dialog opens over the still-mounted drawer and we navigate via a
          // router captured before the async gap.
          ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -1),
            leading: const Icon(Icons.logout, size: 22, color: AppColors.error),
            title: const Text('Logout',
                style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                    fontSize: 14.5)),
            onTap: () => _logout(context, ref),
          ),
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

  /// Category heading shown above each group of menu items.
  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppColors.primary,
          ),
        ),
      );

  Widget _item(BuildContext context, IconData icon, String label,
          VoidCallback onTap,
          {Color? color}) =>
      ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        leading: Icon(icon, size: 22, color: color ?? AppColors.primary),
        title: Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w500, fontSize: 14.5)),
        onTap: () {
          Navigator.of(context).pop(); // close the drawer first
          onTap();
        },
      );

  /// Switches the Home shell to [index] (Matches = 1, Astrology = 3) and ensures
  /// we are on the Home route so the selected tab is visible.
  void _openTab(BuildContext context, WidgetRef ref, int index) {
    ref.read(homeTabIndexProvider.notifier).state = index;
    context.go('/home');
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    // Capture the router BEFORE the async gap: signing out tears down the home
    // shell (and this drawer), so `context` may be unmounted by the time we
    // navigate. The captured GoRouter survives that.
    final router = GoRouter.of(context);
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
    // Only logs out when the user explicitly confirms; Cancel / dismiss is a
    // no-op and leaves the session intact.
    if (confirmed != true) return;
    await ref.read(authNotifierProvider.notifier).signOut();
    // Matrimony User → return to the User login page only (never the
    // role-selection page).
    router.go('/login');
  }
}
