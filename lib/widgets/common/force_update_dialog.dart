import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/app_update_config.dart';

/// Whether the force-update popup is currently on screen — the Home listener
/// fires on every stream emission, and the popup must never stack.
bool _forceDialogVisible = false;

/// Premium NON-dismissible "Update Required" popup, shown OVER the Home page
/// (the page stays visible behind the dimmed/blurred barrier — spec §3
/// replaced the old fullscreen blocking screen with this). The only exit is
/// the Update button, which opens the Play Store.
Future<void> showForceUpdateDialog(
    BuildContext context, AppUpdateConfig config) async {
  if (_forceDialogVisible) return;
  _forceDialogVisible = true;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'update-required',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) => _ForceUpdateDialog(config: config),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        // Dim + blur Home behind the card while the dialog animates in.
        return BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: 4 * anim.value, sigmaY: 4 * anim.value),
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  } finally {
    _forceDialogVisible = false;
  }
}

class _ForceUpdateDialog extends StatelessWidget {
  final AppUpdateConfig config;
  const _ForceUpdateDialog({required this.config});

  Future<void> _openStore() async {
    final raw = config.playStoreUrl.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* best-effort — the user can still update manually */}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = config.updateTitle.trim().isNotEmpty
        ? config.updateTitle.trim()
        : l10n.updateAvailableTitle;
    final body = config.updateMessage.trim().isNotEmpty
        ? config.updateMessage.trim()
        : l10n.updateRequiredMessage;

    // Back must not dismiss — updating is the only way forward.
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            // Scrollable so landscape / long admin messages / large fonts can
            // never overflow the dialog viewport.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.system_update,
                        size: 38, color: Colors.white),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13.5, height: 1.5, color: Colors.grey[700]),
                  ),
                  if (config.minSupportedVersion.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${l10n.version} ${config.minSupportedVersion.trim()}+',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      // The dialog stays up — coming back from the store
                      // without updating keeps the app gated.
                      onPressed: _openStore,
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: Text(l10n.updateNow,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
