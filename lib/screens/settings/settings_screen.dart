import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/l10n_ext.dart';
import '../../providers/account_provider.dart';
import '../../providers/auth_provider.dart';

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GroupLabel(l10n.preferences),
          _SettingsTile(
            icon: Icons.language,
            title: l10n.language,
            route: '/language',
          ),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: l10n.privacySettings,
            route: '/privacy',
          ),
          _SettingsTile(
            icon: Icons.tune,
            title: l10n.partnerPreferences,
            route: '/partner-preferences',
          ),
          const SizedBox(height: 16),
          _GroupLabel(l10n.supportAndLegal),
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
          const SizedBox(height: 16),
          _GroupLabel(l10n.account),
          _DeleteAccountTile(
            onTap: () => _deleteAccount(context, ref),
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

/// Permanently deletes the account immediately (no admin approval) and returns
/// the user to the Login screen with the navigation stack cleared.
Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.deleteAccount),
      content: Text(l10n.deleteAccountWarning),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.deleteAccount),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final isAstrologer =
      ref.read(currentUserProvider).valueOrNull?.isAstrologer ?? false;

  // Blocking progress while we delete.
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await ref
        .read(accountControllerProvider.notifier)
        .deleteAccount(isAstrologer: isAstrologer);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss progress
    // Reset the navigation stack to Login — no back-button return.
    context.go('/login');
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss progress
    messenger.showSnackBar(SnackBar(content: Text(context.l10n.couldNotDeleteAccount)));
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
