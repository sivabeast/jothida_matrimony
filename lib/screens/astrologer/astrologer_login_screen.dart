import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';

/// Login for the **Astrologer** portal — Google Sign-In ONLY.
///
/// Astrologer accounts are provisioned by the admin (by Gmail). On sign-in the
/// account's Gmail is checked against the `astrology_team` registry:
///  • registered & active  → link the uid, flag the `astrologer` role, open the
///    Astrologer Dashboard;
///  • not registered / disabled → sign out + "Unauthorized astrologer account".
///
/// There is intentionally no email/password or phone-OTP path here.
class AstrologerLoginScreen extends ConsumerStatefulWidget {
  const AstrologerLoginScreen({super.key});

  @override
  ConsumerState<AstrologerLoginScreen> createState() =>
      _AstrologerLoginScreenState();
}

class _AstrologerLoginScreenState
    extends ConsumerState<AstrologerLoginScreen> {
  // Covers the whole Google flow including the registry check, so the button
  // shows a spinner the entire time and a `finally` always clears it.
  bool _busy = false;

  /// After a Google sign-in: verify the Gmail is a registered, active astrologer
  /// before allowing entry. Unauthorized accounts are signed straight back out.
  Future<void> _afterAuth(String uid, String? email) async {
    final team = ref.read(astrologyTeamServiceProvider);
    try {
      final member = email == null ? null : await team.getByEmail(email);
      if (!mounted) return;

      if (member == null || !member.active) {
        debugPrint('[AstrologerLogin] $email not a registered/active astrologer '
            '→ denying access.');
        await ref.read(authNotifierProvider.notifier).signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unauthorized astrologer account. '
              'Please contact the admin to be registered.'),
          backgroundColor: Colors.red,
        ));
        return;
      }

      // Registered + active → link the uid (first sign-in) and flag the role.
      final authUser = ref.read(authNotifierProvider).valueOrNull;
      await team.linkUid(
        member.id,
        uid: uid,
        displayName: authUser?.displayName ?? '',
        photoUrl: authUser?.photoUrl ?? '',
      );
      await team.promoteToAstrologerRole(uid);
      // Wait for the user doc (role) to refresh so the router gates correctly.
      ref.invalidate(currentUserProvider);
      await ref.read(currentUserProvider.future);
      if (!mounted) return;
      debugPrint('[AstrologerLogin] $email authorized → /astrologer-dashboard');
      context.go('/astrologer-dashboard');
    } catch (e) {
      debugPrint('[AstrologerLogin] _afterAuth failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not verify your astrologer account. '
              'Please check your connection and try again.')));
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return; // guard against double-taps
    debugPrint('[AstrologerLogin] "Continue with Google" tapped.');
    setState(() => _busy = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      final auth = ref.read(authNotifierProvider);
      if (auth.hasError) {
        final err = auth.error;
        debugPrint('[AstrologerLogin] signInWithGoogle error: $err');
        if (!(err is AuthException && err.cancelled)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(err is AuthException
                  ? err.message
                  : 'Google Sign-In failed. Please try again.')));
        }
        return;
      }
      final user = auth.valueOrNull;
      if (user != null) {
        debugPrint('[AstrologerLogin] Sign-in successful (uid=${user.uid}).');
        await _afterAuth(user.uid, user.email);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);
    final busy = _busy || authAsync.isLoading;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Back to the Role Selection page (Matrimony User / Astrologer).
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => context.go('/account-type'),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold, width: 1.5),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: AppColors.gold, size: 40),
                ),
                const SizedBox(height: 14),
                Text('Astrologer Portal', style: AppTextStyles.appName),
                const SizedBox(height: 4),
                Text(
                  'Jothida Matrimony',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75), fontSize: 14),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.1), blurRadius: 20),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome, Guruji', style: AppTextStyles.heading2),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in with the Google account registered by the admin.',
                        style: AppTextStyles.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      // ── Continue with Google (only auth method) ─────────────
                      OutlinedButton.icon(
                        onPressed: busy ? null : _signInWithGoogle,
                        icon: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Image.network(
                                'https://www.google.com/favicon.ico',
                                width: 20,
                                height: 20,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.g_mobiledata,
                                    size: 24),
                              ),
                        label: const Text('Continue with Google'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      TextButton.icon(
                        onPressed: () => context.go('/account-type'),
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text('Looking for a partner? User login'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
