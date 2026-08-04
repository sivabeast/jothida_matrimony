import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/app_update_config.dart';
import '../../providers/app_update_provider.dart';

/// SharedPreferences key holding the last version the user was prompted about,
/// so the soft dialog appears at most ONCE per published version.
const String _kPromptedVersionKey = 'update_prompted_version';

/// Soft (dismissible) "Update Available" prompt.
///
/// Shown when the admin's published [AppUpdateConfig.currentVersion] is newer
/// than the running app, but the HARD force-update gate does not apply — that
/// blocking case is handled by the force-update popup on Home. The prompt is
/// per-version: once shown (or dismissed with "Later") it never reappears
/// until the admin publishes a newer version.
Future<void> maybeShowUpdateAvailableDialog(
    BuildContext context, WidgetRef ref) async {
  AppUpdateConfig? config;
  String? running;
  try {
    // Await the first emission (splash may not have warmed these up yet). A
    // timeout keeps this best-effort: no config → no prompt, never an error.
    config = await ref
        .read(appUpdateConfigProvider.future)
        .timeout(const Duration(seconds: 10));
    running = await ref
        .read(appVersionProvider.future)
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    return; // unreachable backend / disposed scope — silently skip
  }
  if (config == null || running.isEmpty) return;

  // The blocking force-update gate already covers this case — don't double up.
  if (config.forceUpdate &&
      config.minSupportedVersion.trim().isNotEmpty &&
      isVersionBelow(running, config.minSupportedVersion)) {
    return;
  }

  final latest = config.currentVersion.trim();
  if (latest.isEmpty || !isVersionBelow(running, latest)) return;

  // Once per published version.
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kPromptedVersionKey) == latest) return;
    await prefs.setString(_kPromptedVersionKey, latest);
  } catch (_) {/* best-effort — still show the dialog */}

  if (!context.mounted) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'update-available',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _UpdateAvailableDialog(config: config!),
    transitionBuilder: (ctx, anim, _, child) {
      final curved =
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      // Dim + blur the app behind the card while the dialog animates in.
      return BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: 4 * anim.value, sigmaY: 4 * anim.value),
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
}

/// The premium rounded update card itself.
class _UpdateAvailableDialog extends StatelessWidget {
  final AppUpdateConfig config;
  const _UpdateAvailableDialog({required this.config});

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
        : l10n.updateAvailableBody;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 14),
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
                  gradient: AppColors.goldGradient,
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
              if (config.currentVersion.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${l10n.version} ${config.currentVersion.trim()}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.goldDark),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openStore();
                  },
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
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[600]),
                child: Text(l10n.later,
                    style: const TextStyle(fontSize: 13.5)),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
