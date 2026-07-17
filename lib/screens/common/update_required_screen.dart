import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/app_update_config.dart';

/// Full-screen BLOCKING force-update page. Shown instead of the app when the
/// running version is below the admin's minimum supported version and force
/// update is ON. There is deliberately no Skip / Later action and the back
/// button is swallowed — the only way forward is "Update Now" (Play Store).
class UpdateRequiredScreen extends StatelessWidget {
  final AppUpdateConfig config;
  const UpdateRequiredScreen({super.key, required this.config});

  Future<void> _openStore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final raw = config.playStoreUrl.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(
            SnackBar(content: Text(context.l10n.somethingWentWrong)));
      }
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.somethingWentWrong)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = config.updateTitle.trim().isNotEmpty
        ? config.updateTitle.trim()
        : l10n.updateAvailableTitle;
    final message = config.updateMessage.trim().isNotEmpty
        ? config.updateMessage.trim()
        : l10n.updateRequiredMessage;

    return PopScope(
      canPop: false, // no back-button escape — updating is mandatory
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.system_update,
                      size: 64, color: AppColors.primary),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 21,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5, height: 1.5, color: Colors.grey[700]),
                ),
                if (config.currentVersion.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${l10n.version} ${config.currentVersion.trim()}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.goldDark),
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _openStore(context),
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: Text(l10n.updateNow,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
