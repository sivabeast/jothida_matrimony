import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/guest_login_prompt_provider.dart';
import '../common/app_logo.dart';

/// Hosts the periodic GUEST login prompt (§3).
///
/// Renders nothing of its own — it wraps Home and opens a dialog OVER it, so
/// the page underneath keeps working exactly as before. Behaviour:
///
///   • only for a guest / not-logged-in visitor — a member never sees it;
///   • at most once every [kGuestLoginPromptInterval], enforced by a
///     PERSISTED timestamp rather than by widget rebuilds, so navigating
///     around the app or reopening it cannot bring the prompt back early;
///   • closing it restarts the interval, so it never re-opens immediately;
///   • the moment the guest logs in the ticker stops and the stamp is cleared.
class GuestLoginPromptHost extends ConsumerStatefulWidget {
  final Widget child;
  const GuestLoginPromptHost({super.key, required this.child});

  @override
  ConsumerState<GuestLoginPromptHost> createState() =>
      _GuestLoginPromptHostState();
}

class _GuestLoginPromptHostState extends ConsumerState<GuestLoginPromptHost> {
  /// Re-checks the elapsed time. Deliberately much shorter than the interval
  /// itself so the prompt lands close to the 10-minute mark even when the
  /// guest never navigates.
  static const _tick = Duration(seconds: 30);

  Timer? _timer;

  /// Guards against a second dialog while one is already on screen.
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _restartTimer();
    // First check shortly after Home settles, so the prompt does not fight the
    // app-opening popup or the first frame.
    Future.delayed(const Duration(seconds: 3), _maybeShow);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (!mounted || _open) return;
    // Authentication state is the gate — never "does a profile exist".
    if (!ref.read(isGuestProvider)) {
      _timer?.cancel();
      return;
    }
    // Never stack on top of something else the user is already looking at —
    // the app-opening popup, a required-update gate, a bottom sheet, or a page
    // they navigated to. The next tick will catch them back on Home.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final store = ref.read(guestLoginPromptStoreProvider);
    final last = await store.lastShownMs();
    if (!mounted || _open) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (!shouldShowGuestLoginPrompt(
      isGuest: ref.read(isGuestProvider),
      lastShownMs: last,
      now: DateTime.now(),
    )) {
      return;
    }

    _open = true;
    // Stamped BEFORE the dialog opens so a dismissal (or an unexpected error)
    // can never loop the prompt.
    await store.markShown();
    if (!mounted) {
      _open = false;
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _GuestLoginPromptDialog(),
    );
    _open = false;
  }

  @override
  Widget build(BuildContext context) {
    // Clears the stored stamp as soon as the visitor becomes a member.
    ref.watch(guestLoginPromptResetProvider);
    // Stop ticking the moment the guest logs in; start again if they sign out.
    ref.listen<bool>(isGuestProvider, (_, isGuest) {
      if (isGuest) {
        _restartTimer();
      } else {
        _timer?.cancel();
      }
    });
    return widget.child;
  }
}

/// The prompt itself: a clear Login action plus a "Maybe Later" dismiss.
class _GuestLoginPromptDialog extends StatelessWidget {
  const _GuestLoginPromptDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 64),
            const SizedBox(height: 18),
            Text(
              l10n.guestLoginPromptTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.guestLoginPromptBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5, height: 1.5, color: Colors.grey[700]),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/login');
                },
                icon: const Icon(Icons.login, size: 18),
                label: Text(l10n.login),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/register');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.createAccount),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
              child: Text(l10n.maybeLater),
            ),
          ],
        ),
      ),
    );
  }
}
