import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/account_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';

/// Settings hub — groups app preferences and links to legal/support pages.
/// Registered at `/settings`. Reached from Profile → "Settings".
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[SettingsScreen] build — route /settings opened');
    final deletionPending = ref.watch(deletionPendingProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _GroupLabel('Preferences'),
          _SettingsTile(
            icon: Icons.language,
            title: 'Language / மொழி',
            route: '/language',
          ),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: 'Privacy Settings',
            route: '/privacy',
          ),
          _SettingsTile(
            icon: Icons.tune,
            title: 'Partner Preferences',
            route: '/partner-preferences',
          ),
          const SizedBox(height: 16),
          const _GroupLabel('Support & Legal'),
          _SettingsTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            route: '/help',
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            route: '/privacy-policy',
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            route: '/terms',
          ),
          const SizedBox(height: 16),
          const _GroupLabel('Account'),
          _DeleteAccountTile(
            pending: deletionPending,
            onTap: () => _requestDeletion(context, ref),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${AppConstants.appName}\nVersion ${AppConstants.appVersion}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sends an account deletion request to the admin (nothing is deleted now).
Future<void> _requestDeletion(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Request Account Deletion'),
      content: const Text(
        'Your account deletion request will be sent to the administrator for '
        'review. Your account will remain active until the request is approved.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Submit Request'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final messenger = ScaffoldMessenger.of(context);
  final user = ref.read(currentUserProvider).valueOrNull;
  final profile = ref.read(myProfileProvider).valueOrNull;
  final userId = user?.uid ?? profile?.userId ?? 'demo-user';
  final userName = user?.displayName ?? profile?.name ?? 'User';
  final email = user?.email ?? 'demo@jothida.app';

  await ref.read(accountControllerProvider.notifier).submitDeletionRequest(
        userId: userId,
        userName: userName,
        email: email,
      );
  messenger.showSnackBar(const SnackBar(
      content: Text('Deletion request submitted. An admin will review it.')));
}

class _DeleteAccountTile extends StatelessWidget {
  final bool pending;
  final VoidCallback onTap;
  const _DeleteAccountTile({required this.pending, required this.onTap});

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
        title: const Text('Delete Account',
            style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
        subtitle: Text(pending
            ? 'Deletion request pending admin review'
            : 'Request account deletion'),
        trailing: pending
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Pending',
                    style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              )
            : const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.error),
        onTap: pending ? null : onTap,
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
