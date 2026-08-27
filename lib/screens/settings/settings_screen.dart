import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/account_deletion.dart';
import '../../core/utils/l10n_ext.dart';
import '../../providers/app_update_provider.dart';
import '../../providers/review_provider.dart';

/// Settings hub — groups app preferences and links to legal/support pages.
/// Registered at `/settings`. Reached from Profile → "Settings".
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[SettingsScreen] build — route /settings opened');
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.settings),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      // Application settings only — Logout lives in the side menu, never here.
      // No Change Password / Mobile / Email, 2FA, online-status or block tools:
      // the app uses Google / OTP sign-in, so those are unnecessary.
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── General ──────────────────────────────────────────────────────
          _GroupLabel(l10n.generalSection),
          _SettingsTile(
            icon: Icons.language,
            title: l10n.language,
            route: '/language',
          ),
          const SizedBox(height: 16),
          // ── Privacy ──────────────────────────────────────────────────────
          _GroupLabel(l10n.privacy),
          _SettingsTile(
            icon: Icons.visibility_off_outlined,
            title: l10n.privacySettings,
            route: '/privacy',
          ),
          const SizedBox(height: 16),
          // ── Account ──────────────────────────────────────────────────────
          _GroupLabel(l10n.account),
          _DeleteAccountTile(
            onTap: () => confirmAndDeleteAccount(context, ref),
          ),
          const SizedBox(height: 16),
          // ── About ────────────────────────────────────────────────────────
          _GroupLabel(l10n.aboutSection),
          // Explicit "Rate this app" — the member ASKED, so this opens the
          // Play listing directly and marks the account rated, which also
          // stops the occasional automatic prompt for good (spec §31).
          const _RateAppTile(),
          _SettingsTile(
            icon: Icons.help_outline,
            title: l10n.helpSupport,
            route: '/help',
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: l10n.privacyPolicy,
            route: '/privacy-policy',
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: l10n.termsConditions,
            route: '/terms',
          ),
          // Imported from the website (§14).
          _SettingsTile(
            icon: Icons.child_care_outlined,
            title: l10n.childSafety,
            route: '/child-safety',
          ),
          _SettingsTile(
            icon: Icons.delete_forever_outlined,
            title: l10n.deleteAccountPageTitle,
            route: '/delete-account',
          ),
          const SizedBox(height: 24),
          Center(
            child: Consumer(
              builder: (_, r, __) {
                // The REAL installed version, read from the platform — a
                // hardcoded constant drifts the moment a release ships
                // without someone remembering to edit it.
                final name = r.watch(installedVersionNameProvider).valueOrNull;
                final code = r.watch(installedVersionCodeProvider).valueOrNull;
                final version = (name == null || name.isEmpty)
                    ? AppConstants.appVersion
                    : '$name${(code ?? 0) > 0 ? ' ($code)' : ''}';
                return Text(
                  '${AppConstants.appName}\n${l10n.version} $version',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey[500], fontSize: 12, height: 1.5),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


/// "Rate this app" — an explicit, member-initiated rating.
///
/// Deliberately NOT Play's silent in-app sheet: the member tapped a menu item
/// asking to leave a review, and Play's sheet may decide to show nothing at
/// all, which would look broken. This opens the real listing instead, and
/// records the account as rated so the automatic prompt never fires again
/// (spec §31/§32).
///
/// It disappears once the account has rated, because an action that can only
/// be done once should not keep offering itself.
class _RateAppTile extends ConsumerStatefulWidget {
  const _RateAppTile();

  @override
  ConsumerState<_RateAppTile> createState() => _RateAppTileState();
}

class _RateAppTileState extends ConsumerState<_RateAppTile> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: ref.read(reviewControllerProvider).hasRated(),
      builder: (context, snap) {
        if (snap.data == true) return const SizedBox.shrink();
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.star_outline, color: AppColors.primary),
            title: Text(context.l10n.rateApp),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final l10n = context.l10n;
              final ok =
                  await ref.read(reviewControllerProvider).openStoreListing();
              if (!mounted) return;
              if (ok) {
                setState(() => _hidden = true);
              } else {
                messenger.showSnackBar(
                    SnackBar(content: Text(l10n.couldNotOpenPlayStore)));
              }
            },
          ),
        );
      },
    );
  }
}

class _DeleteAccountTile extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteAccountTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.error.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.error.withOpacity(0.25)),
      ),
      child: ListTile(
        leading: const Icon(Icons.delete_outline, color: AppColors.error),
        title: Text(context.l10n.deleteAccount,
            style: const TextStyle(
                color: AppColors.error, fontWeight: FontWeight.w600)),
        subtitle: Text(context.l10n.deleteAccountSubtitle),
        trailing:
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.error),
        onTap: onTap,
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Colors.grey[600])),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String route;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () {
          debugPrint('[SettingsScreen] navigate → $route');
          context.push(route);
        },
      ),
    );
  }
}
