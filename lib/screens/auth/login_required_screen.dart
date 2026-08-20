import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../widgets/common/gradient_button.dart';

/// Where a GUEST lands when they tap anything personalized (§13).
///
/// Guest Mode lets a visitor browse Home and public information; Matches,
/// Profile, Chat, Astrology booking, Horoscope upload and Reports
/// all route here instead. The router decides that — see
/// `resolveAuthRedirect` and `kGuestAllowedRoutes` — so this screen never has
/// to know which feature was blocked.
///
/// Registering or logging in from here LINKS the anonymous account in place
/// (same uid, no duplicate), so nothing about the session is lost.
class LoginRequiredScreen extends ConsumerWidget {
  /// The location the visitor was blocked from. Stashed in
  /// [pendingReturnRouteProvider] so the post-login redirect lands there
  /// instead of Home (spec §15, Case 1).
  final String? returnTo;

  const LoginRequiredScreen({super.key, this.returnTo});

  /// Records [returnTo] (when there is one) and opens [route].
  void _goAuth(BuildContext context, WidgetRef ref, String route) {
    final back = (returnTo ?? '').trim();
    if (back.isNotEmpty) {
      ref.read(pendingReturnRouteProvider.notifier).state = back;
    }
    context.go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.primary,
        // A guest reaching this screen came from somewhere they could not go,
        // so "back" must land on the one page they can always see.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.28),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.lock_outline,
                      size: 44, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.loginRequiredTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.loginRequiredBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    onPressed: () => _goAuth(context, ref, '/register'),
                    text: l10n.createAccount,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _goAuth(context, ref, '/login'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      l10n.login,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home_outlined, size: 19),
                  label: Text(l10n.keepBrowsing),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                ),
                const SizedBox(height: 6),
                // Reassurance that registering does not throw away the session
                // they have been building — it is the same account, upgraded.
                Text(
                  l10n.guestUpgradeNote,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5, height: 1.45, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "you are browsing as a guest" strip shown on Home in Guest Mode, with a
/// one-tap route into registration.
class GuestModeBanner extends ConsumerWidget {
  const GuestModeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isGuestProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined,
              size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.guestModeBanner,
              style: TextStyle(
                  fontSize: 12.5, height: 1.35, color: Colors.grey[800]),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => context.go('/register'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.signUp,
                style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
