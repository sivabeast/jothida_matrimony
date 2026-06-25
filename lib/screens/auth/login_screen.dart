import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/auth_routing.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Matrimony **User** login. Two passwordless methods only:
///   • Mobile Number + OTP
///   • Continue with Google
/// (Email / password login was removed — see the spec auth redesign.)
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Covers the *entire* Google flow — credential exchange AND the post-auth
  // routing (which itself does async Firestore work for astrologer accounts) —
  // so the button stays busy until the user actually leaves this screen, and a
  // `finally` always clears it. Without this, the window between sign-in
  // completing and navigation finishing had no loading indicator.
  bool _busy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    debugPrint('[LoginScreen] "Send OTP" tapped for '
        '+91${_phoneController.text.trim()}');
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(otpNotifierProvider.notifier)
        .sendOtp(_phoneController.text.trim());
    if (!mounted) return;
    final otpState = ref.read(otpNotifierProvider);
    if (otpState.codeSent && otpState.verificationId != null) {
      debugPrint('[LoginScreen] OTP sent — opening OTP screen.');
      context.push('/otp', extra: {
        'verificationId': otpState.verificationId!,
        'phone': _phoneController.text.trim(),
      });
    } else if (otpState.error != null) {
      debugPrint('[LoginScreen] sendOtp failed: ${otpState.error}');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(otpState.error!)));
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return; // guard against double-taps
    debugPrint('[LoginScreen] "Continue with Google" tapped.');
    setState(() => _busy = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      final auth = ref.read(authNotifierProvider);

      if (auth.hasError) {
        final err = auth.error;
        final message =
            err is AuthException ? err.message : context.l10n.googleSignInFailed;
        debugPrint('[LoginScreen] signInWithGoogle error: $err');
        if (!(err is AuthException && err.cancelled)) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }

      final user = auth.valueOrNull;
      if (user != null) {
        debugPrint(
            '[LoginScreen] Sign-in successful (uid=${user.uid}). Routing...');
        await routeAuthenticatedUser(context, ref, user, tag: 'LoginScreen');
      } else {
        debugPrint('[LoginScreen] Google picker dismissed — staying on login.');
      }
    } finally {
      // Always clear the spinner — on success (if still mounted), on error, on
      // cancellation, or on an unexpected throw. Never leaves the UI stuck.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpState = ref.watch(otpNotifierProvider);
    final authAsync = ref.watch(authNotifierProvider);
    // `googleBusy` drives the Google button's spinner; `isLoading` disables
    // every action while any auth operation is in flight.
    final googleBusy = _busy || authAsync.isLoading;
    final isLoading = otpState.isLoading || googleBusy;
    final l10n = context.l10n;

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
                const SizedBox(height: 8),
                Image.asset(
                  'assets/images/app_logo.png',
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Column(
                    children: [
                      const Icon(Icons.favorite,
                          color: AppColors.gold, size: 72),
                      const SizedBox(height: 8),
                      Text(l10n.appTitle, style: AppTextStyles.appName),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
                        Text(l10n.welcomeBack, style: AppTextStyles.heading2),
                        const SizedBox(height: 4),
                        Text(l10n.signInToContinue,
                            style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 22),
                        // ── Mobile number + OTP ──────────────────────────────
                        AppTextField(
                          controller: _phoneController,
                          label: l10n.mobileNumber,
                          hint: '9876543210',
                          keyboardType: TextInputType.phone,
                          prefixText: '+91 ',
                          validator: Validators.phone,
                        ),
                        const SizedBox(height: 16),
                        GradientButton(
                          onPressed: isLoading ? null : _sendOtp,
                          isLoading: otpState.isLoading,
                          text: l10n.sendOtp,
                        ),
                        if (otpState.error != null) ...[
                          const SizedBox(height: 8),
                          Text(otpState.error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13)),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(l10n.orLabel,
                                  style: const TextStyle(color: Colors.grey)),
                            ),
                            const Expanded(child: Divider()),
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
                          label: Text(l10n.continueWithGoogle),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        // Entry to the astrologer portal (its own login flow).
                        TextButton.icon(
                          onPressed: () => context.push('/astrologer-login'),
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: Text(l10n.astrologerSignInHere),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.goldDark),
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
