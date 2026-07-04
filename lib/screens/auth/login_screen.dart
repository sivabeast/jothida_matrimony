import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/auth_routing.dart';
import '../../core/utils/l10n_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wedding_provider.dart';

/// App entry — ROLE-BASED. Instead of a classic login form, the user first
/// picks WHO they are with two large cards:
///   • Matrimony User  → looking for a life partner (matrimony experience);
///   • Family Member   → invited (by gmail) into a couple's Wedding Workspace.
///
/// Both roles sign in the SAME way: Continue with Google only (mobile-number
/// OTP login was removed). One Gmail may hold BOTH roles — the selected card
/// (not the account) decides which interface opens.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _EntryRole { matrimony, family }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// null = the two role cards; otherwise the Google sign-in step for that role.
  _EntryRole? _role;

  // Covers the *entire* Google flow — credential exchange AND the post-auth
  // routing — so the button stays busy until the user actually leaves this
  // screen, and a `finally` always clears it.
  bool _busy = false;

  // ── Matrimony User sign-in ──────────────────────────────────────────────

  Future<void> _signInAsMatrimony() async {
    if (_busy) return; // guard against double-taps
    debugPrint('[LoginScreen] Matrimony User → Continue with Google tapped.');
    setState(() => _busy = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      final auth = ref.read(authNotifierProvider);

      if (auth.hasError) {
        _showAuthError(auth.error);
        return;
      }

      final user = auth.valueOrNull;
      if (user == null) {
        debugPrint('[LoginScreen] Google picker dismissed — staying on login.');
        return;
      }

      // The Matrimony card was chosen → matrimony interface on next open too.
      ref.read(entryModeProvider.notifier).state = WeddingEntryMode.matrimony;
      await WeddingEntryMode.save(WeddingEntryMode.matrimony);
      if (!mounted) return;
      debugPrint(
          '[LoginScreen] Sign-in successful (uid=${user.uid}). Routing...');
      await routeAuthenticatedUser(context, ref, user, tag: 'LoginScreen');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Family Member sign-in ───────────────────────────────────────────────

  /// FAMILY entry. Signs in with Google, then verifies the Gmail is invited
  /// to a Wedding Workspace:
  ///   • invited → opens the Family Workspace (the same Gmail may ALSO be a
  ///     matrimony user — the card, not the account, picks the interface);
  ///   • not invited → "You have not been invited to any Wedding Workspace
  ///     yet. Please contact the Bride or Groom." and signed out again.
  Future<void> _signInAsFamily() async {
    if (_busy) return;
    debugPrint('[LoginScreen] Family Member → Continue with Google tapped.');
    setState(() => _busy = true);
    // Holds the router redirect on /login while the invite check runs, so a
    // brand-new family Gmail is never raced into matrimony onboarding.
    ref.read(familyLoginInProgressProvider.notifier).state = true;
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      final auth = ref.read(authNotifierProvider);

      if (auth.hasError) {
        _showAuthError(auth.error);
        return;
      }

      final user = auth.valueOrNull;
      if (user == null) return; // picker dismissed

      final email = user.email?.toLowerCase() ?? '';
      final wedding = email.isEmpty
          ? null
          : await ref
              .read(weddingServiceProvider)
              .getWeddingByMemberEmail(email);

      if (wedding == null) {
        // Not invited → no Family Workspace access. Sign back out so the
        // account can't wander into matrimony onboarding from this card.
        debugPrint('[LoginScreen] family entry: $email is NOT invited.');
        await ref.read(authNotifierProvider.notifier).signOut();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Not Invited Yet'),
            content: const Text(
                'You have not been invited to any Wedding Workspace yet. '
                'Please contact the Bride or Groom.'),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      debugPrint('[LoginScreen] family entry: $email invited to wedding '
          '${wedding.id} — opening the Family Workspace.');
      final weddingService = ref.read(weddingServiceProvider);
      // Only a Gmail with NO other account type becomes a dedicated 'family'
      // account. A dual-role Gmail (also a matrimony user / admin) keeps its
      // role — the persisted entry mode opens the workspace instead.
      if (!user.isFamily &&
          !user.isAdmin &&
          !user.isAstrologer &&
          !user.isProfileComplete) {
        await weddingService.promoteToFamilyRole(user.uid);
      }
      await weddingService.markMemberJoined(wedding.id, email);
      ref.read(entryModeProvider.notifier).state = WeddingEntryMode.family;
      await WeddingEntryMode.save(WeddingEntryMode.family);
      ref.invalidate(currentUserProvider);
      await ref.read(currentUserProvider.future);
      if (!mounted) return;
      context.go('/wedding-workspace');
    } finally {
      ref.read(familyLoginInProgressProvider.notifier).state = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showAuthError(Object? err) {
    final message =
        err is AuthException ? err.message : context.l10n.googleSignInFailed;
    debugPrint('[LoginScreen] signInWithGoogle error: $err');
    if (!(err is AuthException && err.cancelled)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);
    final googleBusy = _busy || authAsync.isLoading;
    final l10n = context.l10n;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Image.asset(
                  'assets/images/app_logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Column(
                    children: [
                      const Icon(Icons.favorite,
                          color: AppColors.gold, size: 64),
                      const SizedBox(height: 8),
                      Text(l10n.appTitle, style: AppTextStyles.appName),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_role == null)
                  _buildRoleCards()
                else
                  _buildGoogleStep(googleBusy),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Step 1 — the two large role cards.
  Widget _buildRoleCards() {
    return Column(
      children: [
        const Text(
          'How would you like to continue?',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        _roleCard(
          role: _EntryRole.matrimony,
          emoji: '💍',
          title: 'Matrimony User',
          description:
              'Looking for a life partner? Continue as a Matrimony User.',
          color: AppColors.primary,
        ),
        const SizedBox(height: 16),
        _roleCard(
          role: _EntryRole.family,
          emoji: '👨‍👩‍👧‍👦',
          title: 'Family Member',
          description: 'Join an existing Wedding Workspace using your '
              'invited Google account.',
          color: AppColors.goldDark,
        ),
      ],
    );
  }

  Widget _roleCard({
    required _EntryRole role,
    required String emoji,
    required String title,
    required String description,
    required Color color,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _role = role),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.25), width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: TextStyle(
                      fontSize: 17,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      color: color)),
              const SizedBox(height: 6),
              Text(description,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              const SizedBox(height: 12),
              Icon(Icons.arrow_forward_rounded, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// Step 2 — the selected role's ONLY sign-in method: Continue with Google.
  Widget _buildGoogleStep(bool googleBusy) {
    final isFamily = _role == _EntryRole.family;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                visualDensity: VisualDensity.compact,
                onPressed:
                    googleBusy ? null : () => setState(() => _role = null),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isFamily ? 'Family Member' : 'Matrimony User',
                  style: AppTextStyles.heading2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isFamily
                ? 'Sign in with the Google account the Bride or Groom '
                    'invited to their Wedding Workspace.'
                : 'Sign in with your Google account to find your life partner.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: googleBusy
                ? null
                : (isFamily ? _signInAsFamily : _signInAsMatrimony),
            icon: googleBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Image.network(
                    'https://www.google.com/favicon.ico',
                    width: 20,
                    height: 20,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.g_mobiledata, size: 24),
                  ),
            label: Text(context.l10n.continueWithGoogle),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (isFamily) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Only Gmail addresses invited by the Bride or Groom can '
                'open the Wedding Workspace.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
