import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/app_update_config.dart';
import '../../providers/app_update_provider.dart';
import 'force_update_dialog.dart';

/// SharedPreferences key holding the last version CODE the user was prompted
/// about, so the soft dialog appears at most ONCE per published release.
const String _kPromptedVersionKey = 'update_prompted_version_code';

/// Soft (dismissible) "Update Available" prompt.
///
/// Shown when the admin has published a newer version code than the running
/// build but Force Update is OFF — the blocking case is handled by the
/// force-update popup on Home. The prompt is per-release: once shown (or
/// dismissed with "Later") it never reappears until the admin releases again.
Future<void> maybeShowUpdateAvailableDialog(
    BuildContext context, WidgetRef ref) async {
  AppUpdateConfig? config;
  int? installed;
  try {
    // Await the first emission (splash may not have warmed these up yet). A
    // timeout keeps this best-effort: no config → no prompt, never an error.
    config = await ref
        .read(appUpdateConfigProvider.future)
        .timeout(const Duration(seconds: 10));
    installed = await ref
        .read(appVersionCodeProvider.future)
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    return; // unreachable backend / disposed scope — silently skip
  }
  if (config == null || installed <= 0) return;

  // The blocking force-update gate already covers this case — don't double up.
  if (config.forceUpdate) return;
  if (!config.isOutdated(installed)) return;

  // Once per published release.
  final latestCode = config.latestVersionCode;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_kPromptedVersionKey) == latestCode) return;
    await prefs.setInt(_kPromptedVersionKey, latestCode);
  } catch (_) {/* best-effort — still show the dialog */}

  if (!context.mounted) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'update-available',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, __) => _UpdateAvailableDialog(config: config!),
    transitionBuilder: (ctx, anim, _, child) {
      final curved =
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      // Dim + blur the app behind the card while the dialog animates in.
      return BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: 5 * anim.value, sigmaY: 5 * anim.value),
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

/// The soft prompt — the SAME premium card as the blocking popup, in gold, with
/// a "Later" escape.
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
    return Center(
      child: Material(
        color: Colors.transparent,
        child: UpdateDialogCard(
          config: config,
          headline: l10n.updateAvailableTitle,
          fallbackBody: l10n.updateAvailableBody,
          accent: AppColors.goldDark,
          onUpdate: () {
            Navigator.of(context).pop();
            _openStore();
          },
          secondaryAction: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: Text(l10n.later, style: const TextStyle(fontSize: 13.5)),
          ),
        ),
      ),
    );
  }
}
