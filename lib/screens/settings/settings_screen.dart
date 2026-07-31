import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/account_deletion.dart';
import '../../core/utils/l10n_ext.dart';

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
            child: Text(
              '${AppConstants.appName}\n${l10n.version} ${AppConstants.appVersion}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
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
