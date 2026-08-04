import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/app_update_config.dart';
import 'app_logo.dart';

/// Whether the force-update popup is currently on screen — the Home listener
/// fires on every stream emission, and the popup must never stack.
bool _forceDialogVisible = false;

/// Premium NON-dismissible "New Update Available" popup, shown OVER the Home
/// page (the page stays visible behind the dimmed/blurred barrier). The only
/// exit is the Update button, which opens the Play Store.
Future<void> showForceUpdateDialog(
    BuildContext context, AppUpdateConfig config) async {
  if (_forceDialogVisible) return;
  _forceDialogVisible = true;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'update-required',
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, _, __) => _ForceUpdateDialog(config: config),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        // Dim + blur Home behind the card while the dialog animates in.
        return BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: 5 * anim.value, sigmaY: 5 * anim.value),
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
    // Back must not dismiss — updating is the only way forward.
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: UpdateDialogCard(
            config: config,
            headline: context.l10n.updateAvailableTitle,
            fallbackBody: context.l10n.updateRequiredMessage,
            accent: AppColors.primary,
            onUpdate: _openStore,
          ),
        ),
      ),
    );
  }
}

/// The shared Material 3 update card used by BOTH update popups (the blocking
/// force-update one and the soft "Update Available" prompt), so they are one
/// consistent piece of design rather than two look-alikes that drift.
///
/// Layout, top to bottom:
///   app launcher logo → "Jothida Matrimony" → "New Update Available"
///   → version badge → update title → update description → primary button
///   → (optional) secondary action, e.g. "Later".
class UpdateDialogCard extends StatelessWidget {
  final AppUpdateConfig config;

  /// The "New Update Available" headline (localised by the caller).
  final String headline;

  /// Body copy to use when the admin left the description empty.
  final String fallbackBody;

  /// Brand accent for the badge + icon halo (maroon = required, gold = soft).
  final Color accent;

  final VoidCallback onUpdate;

  /// Rendered under the primary button — the soft prompt's "Later".
  final Widget? secondaryAction;

  const UpdateDialogCard({
    super.key,
    required this.config,
    required this.headline,
    required this.fallbackBody,
    required this.accent,
    required this.onUpdate,
    this.secondaryAction,
  });

  static const String _appName = 'Jothida Matrimony';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = config.updateTitle.trim();
    final body = config.updateMessage.trim().isNotEmpty
        ? config.updateMessage.trim()
        : fallbackBody;
    final version = config.versionLabel;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 26),
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // Scrollable so landscape / long admin messages / large fonts can never
      // overflow the dialog viewport.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  if (version.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _versionBadge(l10n.version, version),
                  ],
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onUpdate,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        elevation: 2,
                        shadowColor: AppColors.primary.withValues(alpha: 0.45),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      // Hand-built row rather than FilledButton.icon: the label
                      // must be free to ellipsize inside the dialog's narrow
                      // card, which a long translation would otherwise burst.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.system_update_alt_rounded, size: 21),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              l10n.updateNow,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (secondaryAction != null) ...[
                    const SizedBox(height: 4),
                    secondaryAction!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tinted banner carrying the launcher logo, the app name and a small update
  /// glyph — the "this is Jothida Matrimony, and it has an update" statement.
  Widget _header() => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.10),
              accent.withValues(alpha: 0.02),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                const AppLauncherLogo(size: 84),
                // Update glyph pinned to the logo's corner, like a store badge.
                Positioned(
                  right: -8,
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.arrow_upward_rounded,
                        size: 17, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              _appName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );

  Widget _versionBadge(String label, String version) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.new_releases_outlined, size: 14, color: accent),
            const SizedBox(width: 6),
            // Flexible so a long localised "Version" word can shrink instead
            // of pushing the pill past the card.
            Flexible(
              child: Text(
                '$label $version',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      );
}
