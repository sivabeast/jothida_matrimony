import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/app_update_config.dart';
import '../../providers/app_update_provider.dart';
import '../../services/app_update_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Watches the release config and shows the update prompt when the running
/// build is behind (spec §3).
///
/// Wraps Home rather than living inside it, exactly like the app-opening popup
/// host, so nothing about the Home layout changes. It renders only its child
/// until an update is actually required.
///
/// Throttling rules, so this is never annoying (spec §3/§8):
///   * an OPTIONAL prompt is shown at most once per [UpdatePromptStore.checkInterval]
///     and is silenced for 24h per version once "Later" is tapped;
///   * a FORCED prompt ignores both — it cannot be postponed or dismissed;
///   * a new version code starts a fresh cycle, so a snooze never hides a
///     later release.
class AppUpdateHost extends ConsumerStatefulWidget {
  final Widget child;
  const AppUpdateHost({super.key, required this.child});

  @override
  ConsumerState<AppUpdateHost> createState() => _AppUpdateHostState();
}

class _AppUpdateHostState extends ConsumerState<AppUpdateHost> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    // Record which build this member is running, so the admin's update push
    // can target ONLY those behind the latest release (spec §7). Fire and
    // forget — it never blocks anything and never throws.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportVersion());
  }

  Future<void> _reportVersion() async {
    try {
      final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      if (uid == null) return;
      final code = await AppUpdateService.instance.installedVersionCode();
      await ref.read(firestoreServiceProvider).recordAppVersion(uid, code);
    } catch (e) {
      debugPrint('[AppUpdate] version report skipped: $e');
    }
  }

  Future<void> _maybePrompt(
      AppUpdateRequirement requirement, AppUpdateConfig config) async {
    if (_showing || !mounted) return;
    if (requirement == AppUpdateRequirement.none) return;

    final forced = requirement == AppUpdateRequirement.forced;
    if (!forced) {
      // Optional prompts respect both the throttle and the per-version snooze.
      if (!await UpdatePromptStore.mayCheckNow()) return;
      if (await UpdatePromptStore.isSnoozed(config.latestVersionCode)) return;
    }
    if (!mounted) return;

    _showing = true;
    await UpdatePromptStore.markChecked();
    await showDialog<void>(
      context: context,
      // A forced update cannot be dismissed by tapping outside or Back.
      barrierDismissible: !forced,
      builder: (_) => PopScope(
        canPop: !forced,
        child: AppUpdateDialog(config: config, forced: forced),
      ),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) {
    // Watched so a return to the foreground re-runs this (spec §8); the
    // throttle inside _maybePrompt still decides whether anything is shown.
    ref.watch(updateRecheckTickProvider);
    final requirement = ref.watch(updateRequirementProvider);
    final config = ref.watch(appUpdateConfigProvider).valueOrNull;
    if (config != null && requirement != AppUpdateRequirement.none) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybePrompt(requirement, config));
    }
    return widget.child;
  }
}

/// The prompt itself — same card shape, colours and button style as the rest
/// of the app, so it does not look bolted on.
class AppUpdateDialog extends ConsumerStatefulWidget {
  final AppUpdateConfig config;
  final bool forced;

  const AppUpdateDialog(
      {super.key, required this.config, required this.forced});

  @override
  ConsumerState<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends ConsumerState<AppUpdateDialog> {
  bool _busy = false;

  Future<void> _updateNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    final outcome = await AppUpdateService.instance.startUpdate(
      requirement: widget.forced
          ? AppUpdateRequirement.forced
          : AppUpdateRequirement.optional,
      config: widget.config,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    switch (outcome) {
      case UpdateLaunchOutcome.started:
      case UpdateLaunchOutcome.openedStore:
        // Play (or the store listing) has it now. A forced dialog stays up: if
        // the member comes back without updating they are still blocked.
        if (!widget.forced) Navigator.of(context).maybePop();
        break;
      case UpdateLaunchOutcome.cancelled:
        // They backed out of Play's own dialog — say nothing, leave ours as it
        // was so they can try again.
        break;
      case UpdateLaunchOutcome.failed:
        messenger?.showSnackBar(
            SnackBar(content: Text(l10n.couldNotOpenPlayStore)));
        break;
    }
  }

  Future<void> _later() async {
    await UpdatePromptStore.snoozeVersion(widget.config.latestVersionCode);
    if (mounted) Navigator.of(context).maybePop();
  }

  /// Closes the app from a FORCED prompt (spec §25/§27).
  ///
  /// `SystemNavigator.pop()` is the supported way to leave — it behaves like
  /// the back gesture at the root, so Android finishes the activity normally
  /// instead of the app appearing to crash. It is a no-op on platforms that do
  /// not allow an app to close itself, which is fine: the dialog simply stays,
  /// which is exactly what a blocked build should do.
  Future<void> _exitApp() async {
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = widget.config.updateMessage.trim().isNotEmpty
        ? widget.config.updateMessage.trim()
        : (widget.forced ? l10n.updateRequiredBody : l10n.updateAvailableBody);
    final version = widget.config.latestVersionName.trim();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                      widget.forced
                          ? Icons.lock_clock_outlined
                          : Icons.system_update_alt,
                      size: 30,
                      color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.forced
                    ? l10n.updateRequiredTitle
                    : l10n.updateAvailableTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
              if (version.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(l10n.versionLabel(version),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, height: 1.55)),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: _busy ? null : _updateNow,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download_outlined, size: 19),
                label: Text(l10n.updateNow,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              // A FORCED update offers exactly two ways out (spec §25): go to
              // Play, or leave the app. There is no "Later" and no dismiss —
              // the member cannot reach the app on this build.
              if (widget.forced) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _busy ? null : _exitApp,
                  icon: const Icon(Icons.exit_to_app, size: 18),
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                  label: Text(l10n.exitApp),
                ),
              ] else ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _busy ? null : _later,
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                  child: Text(l10n.later),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
