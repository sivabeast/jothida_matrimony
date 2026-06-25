import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Login for the **Astrologer** portal. Same passwordless methods as the user
/// login — Mobile Number + OTP, or Continue with Google. On success the
/// astrologer account is hydrated; a brand-new account is sent to onboarding.
class AstrologerLoginScreen extends ConsumerStatefulWidget {
  const AstrologerLoginScreen({super.key});

  @override
  ConsumerState<AstrologerLoginScreen> createState() =>
      _AstrologerLoginScreenState();
}

class _AstrologerLoginScreenState
    extends ConsumerState<AstrologerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  // Covers the whole Google flow including `_afterAuth` (which loads the
  // astrologer account from Firestore before navigating), so the button shows
  // a spinner the entire time and a `finally` always clears it.
  bool _busy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  /// After a Google sign-in: hydrate the astrologer session. No profile yet →
  /// onboarding form. (Phone OTP routes from the OTP screen via isAstrologer.)
  ///
  /// The Firestore lookup is time-bounded and wrapped so a slow/offline read
  /// surfaces a retry-able message instead of silently leaving the user on the
  /// login screen with no feedback.
  Future<void> _afterAuth(String uid) async {
    try {
      final exists = await ref
          .read(myAstrologerAccountProvider.notifier)
          .loadFromFirestore(uid)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (exists) {
        debugPrint('[AstrologerLogin] account found → /astrologer-dashboard');
        context.go('/astrologer-dashboard');
      } else {
        debugPrint('[AstrologerLogin] no account → /astrologer-register');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Just a few more details — please complete your astrologer profile.')));
        context.go('/astrologer-register');
      }
    } catch (e) {
      debugPrint('[AstrologerLogin] _afterAuth failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not load your astrologer profile. Please check your connection and try again.')));
    }
  }

  Future<void> _sendOtp() async {
    debugPrint('[AstrologerLogin] "Send OTP" tapped for '
        '+91${_phoneController.text.trim()}');
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(otpNotifierProvider.notifier)
        .sendOtp(_phoneController.text.trim());
    if (!mounted) return;
    final otpState = ref.read(otpNotifierProvider);
    if (otpState.codeSent && otpState.verificationId != null) {
      context.push('/otp', extra: {
        'verificationId': otpState.verificationId!,
        'phone': _phoneController.text.trim(),
        'isAstrologer': true,
      });
    } else if (otpState.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(otpState.error!)));
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
        await _afterAuth(user.uid);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpState = ref.watch(otpNotifierProvider);
    final authAsync = ref.watch(authNotifierProvider);
    final googleBusy = _busy || authAsync.isLoading;
    final isLoading = otpState.isLoading || googleBusy;

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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome, Guruji',
                            style: AppTextStyles.heading2),
                        const SizedBox(height: 4),
                        Text('Sign in to manage your consultations',
                            style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 22),
                        // ── Mobile number + OTP ──────────────────────────────
                        AppTextField(
                          controller: _phoneController,
                          label: 'Mobile Number',
                          hint: '9876543210',
                          keyboardType: TextInputType.phone,
                          prefixText: '+91 ',
                          validator: Validators.phone,
                        ),
                        const SizedBox(height: 16),
                        GradientButton(
                          onPressed: isLoading ? null : _sendOtp,
                          isLoading: otpState.isLoading,
                          text: 'Send OTP',
                          gradient: AppColors.goldGradient,
                        ),
                        if (otpState.error != null) ...[
                          const SizedBox(height: 8),
                          Text(otpState.error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13)),
                        ],
                        const SizedBox(height: 20),
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('OR',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // ── Continue with Google ─────────────────────────────
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : _signInWithGoogle,
                          icon: googleBusy
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
                          label:
                              const Text('Looking for a partner? User login'),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary),
                        ),
                      ],
                    ),
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
