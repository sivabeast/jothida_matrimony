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

enum LoginMode { phone, email }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  LoginMode _mode = LoginMode.phone;
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    debugPrint('[LoginScreen] "Send OTP" tapped for '
        '+91${_phoneController.text.trim()}');
    if (!_formKey.currentState!.validate()) return;
    await ref.read(otpNotifierProvider.notifier).sendOtp(_phoneController.text.trim());
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

  Future<void> _signInWithEmail() async {
    debugPrint('[LoginScreen] "Sign In" (email) tapped for '
        '${_emailController.text.trim()}');
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authNotifierProvider.notifier).signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
    if (!mounted) return;
    final auth = ref.read(authNotifierProvider);
    if (auth.hasError) {
      final err = auth.error;
      final message = err is AuthException ? err.message : context.l10n.signInFailed;
      debugPrint('[LoginScreen] signInWithEmail error: $err');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } else if (auth.valueOrNull != null) {
      final user = auth.valueOrNull!;
      debugPrint('[LoginScreen] Email sign-in successful (uid=${user.uid}, '
          'isProfileComplete=${user.isProfileComplete}). Routing...');
      await routeAuthenticatedUser(context, ref, user, tag: 'LoginScreen');
    }
  }

  Future<void> _signInWithGoogle() async {
    debugPrint('[LoginScreen] "Continue with Google" tapped.');
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (!mounted) {
      debugPrint('[LoginScreen] Widget unmounted after signInWithGoogle — '
          'navigation handled elsewhere (e.g. splash).');
      return;
    }
    final auth = ref.read(authNotifierProvider);

    if (auth.hasError) {
      // AuthException already carries a friendly, localisable message
      // (covers cancellation, no-network, misconfigured SHA-1/OAuth client,
      // account-exists-with-different-credential, etc.).
      final err = auth.error;
      final message =
          err is AuthException ? err.message : context.l10n.googleSignInFailed;
      debugPrint('[LoginScreen] signInWithGoogle error: $err');
      // Silently ignore a user-cancelled picker.
      if (!(err is AuthException && err.cancelled)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }

    // signInWithGoogle() returns null only when the user dismissed the
    // account picker — in that case stay on the login screen.
    final user = auth.valueOrNull;
    if (user != null) {
      debugPrint('[LoginScreen] Sign-in successful (uid=${user.uid}, '
          'isProfileComplete=${user.isProfileComplete}). Routing...');
      await routeAuthenticatedUser(context, ref, user, tag: 'LoginScreen');
    } else {
      debugPrint('[LoginScreen] signInWithGoogle returned null '
          '(picker dismissed) — staying on login screen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpState = ref.watch(otpNotifierProvider);
    final authAsync = ref.watch(authNotifierProvider);
    final isLoading = otpState.isLoading || authAsync.isLoading;
    final l10n = context.l10n;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 24),
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
                      Text(l10n.appTitle,
                          style: AppTextStyles.appName),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.welcomeBack, style: AppTextStyles.heading2),
                        const SizedBox(height: 4),
                        Text(l10n.signInToContinue, style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 20),
                        // Toggle
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _buildTab(l10n.phone, LoginMode.phone),
                              _buildTab(l10n.email, LoginMode.email),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_mode == LoginMode.phone) ...[
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
                        ] else ...[
                          AppTextField(
                            controller: _emailController,
                            label: l10n.email,
                            hint: 'example@email.com',
                            keyboardType: TextInputType.emailAddress,
                            validator: Validators.email,
                          ),
                          const SizedBox(height: 12),
                          AppTextField(
                            controller: _passwordController,
                            label: l10n.password,
                            hint: '••••••••',
                            obscureText: _obscurePassword,
                            validator: Validators.password,
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.push('/forgot-password'),
                              child: Text(l10n.forgotPassword),
                            ),
                          ),
                          GradientButton(
                            onPressed: isLoading ? null : _signInWithEmail,
                            isLoading: authAsync.isLoading,
                            text: l10n.signIn,
                          ),
                        ],
                        if (otpState.error != null) ...[
                          const SizedBox(height: 8),
                          Text(otpState.error!,
                              style: const TextStyle(color: Colors.red, fontSize: 13)),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(l10n.orLabel,
                                  style: const TextStyle(color: Colors.grey)),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Google sign in
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : _signInWithGoogle,
                          icon: Image.network(
                            'https://www.google.com/favicon.ico',
                            width: 20,
                            height: 20,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.g_mobiledata, size: 24),
                          ),
                          label: Text(l10n.continueWithGoogle),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(l10n.dontHaveAccount),
                            GestureDetector(
                              onTap: () => context.push('/register'),
                              child: Text(
                                l10n.register,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        // Separate entry for the astrologer portal (its own
                        // login / signup / dashboard).
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

  Widget _buildTab(String label, LoginMode mode) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
