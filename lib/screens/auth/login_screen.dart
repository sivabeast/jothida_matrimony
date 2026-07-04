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
import '../../providers/wedding_provider.dart';
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

  /// FAMILY user login (spec: two user types). Signs in with Google, then
  /// verifies the Gmail is invited to a Wedding Workspace:
  ///   • invited → role becomes 'family' (no matrimony profile ever) and they
  ///     enter the Wedding Workspace directly;
  ///   • not invited → signed out again with "You don't have access.".
  /// A Gmail that already belongs to a matrimony / staff / admin account is
  /// routed through the normal flow instead of being converted.
  Future<void> _signInAsFamily() async {
    if (_busy) return;
    debugPrint('[LoginScreen] "Family Member Login" tapped.');
    setState(() => _busy = true);
    // Holds the router redirect on /login while the invite check runs, so a
    // brand-new family Gmail is never raced into matrimony onboarding.
    ref.read(familyLoginInProgressProvider.notifier).state = true;
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      final auth = ref.read(authNotifierProvider);

      if (auth.hasError) {
        final err = auth.error;
        final message =
            err is AuthException ? err.message : context.l10n.googleSignInFailed;
        if (!(err is AuthException && err.cancelled)) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }

      final user = auth.valueOrNull;
      if (user == null) return; // picker dismissed

      // Staff / admin / existing matrimony accounts keep their normal flow.
      if (user.isAdmin || user.isAstrologer || user.isProfileComplete) {
        debugPrint('[LoginScreen] family login: ${user.email} is an existing '
            '${user.role} account — routing normally.');
        if (!mounted) return;
        await routeAuthenticatedUser(context, ref, user, tag: 'LoginScreen');
        return;
      }

      final email = user.email?.toLowerCase() ?? '';
      final wedding = email.isEmpty
          ? null
          : await ref
              .read(weddingServiceProvider)
              .getWeddingByMemberEmail(email);

      if (wedding == null) {
        // Not invited → no access. Sign back out so the incomplete account
        // can't wander into matrimony onboarding.
        debugPrint('[LoginScreen] family login: $email is NOT invited.');
        await ref.read(authNotifierProvider.notifier).signOut();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No Access'),
            content: const Text(
                "You don't have access.\n\nOnly Gmail addresses invited by "
                'the bride or groom can log in as a Family User.'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      debugPrint('[LoginScreen] family login: $email invited to wedding '
          '${wedding.id} — promoting to family role.');
      final weddingService = ref.read(weddingServiceProvider);
      if (!user.isFamily) {
        await weddingService.promoteToFamilyRole(user.uid);
      }
      await weddingService.markMemberJoined(wedding.id, email);
      ref.invalidate(currentUserProvider);
      await ref.read(currentUserProvider.future);
      if (!mounted) return;
      context.go('/wedding-workspace');
    } finally {
      ref.read(familyLoginInProgressProvider.notifier).state = false;
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
                        const SizedBox(height: 14),
                        // ── Family Member Login ─────────────────────────────
                        // For invited family members (Wedding Workspace).
                        // Only Gmails invited by the bride/groom get access.
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : _signInAsFamily,
                          icon: const Icon(Icons.family_restroom,
                              size: 20, color: AppColors.primary),
                          label: const Text('Family Member Login'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(
                                color: AppColors.primary.withOpacity(0.5)),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            'Invited to a Wedding Workspace? Log in here '
                            'with your invited Gmail.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 11.5),
                          ),
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
