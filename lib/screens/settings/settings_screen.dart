import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

/// Settings hub — groups app preferences and links to legal/support pages.
/// Registered at `/settings`. Reached from Profile → "Settings".
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[SettingsScreen] build — route /settings opened');
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
