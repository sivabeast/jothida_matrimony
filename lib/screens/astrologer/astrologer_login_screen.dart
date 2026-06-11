import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/dev_config.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Login for the **Astrologer** portal (separate from the matrimony-user
/// login). Email/password + Google; on success the astrologer account is
/// loaded from Firestore and the dashboard opens.
class AstrologerLoginScreen extends ConsumerStatefulWidget {
  const AstrologerLoginScreen({super.key});

  @override
  ConsumerState<AstrologerLoginScreen> createState() =>
      _AstrologerLoginScreenState();
}

class _AstrologerLoginScreenState
    extends ConsumerState<AstrologerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// After Firebase auth: hydrate the astrologer session. If this account has
  /// no astrologer profile yet, send them to the astrologer signup form.
  Future<void> _afterAuth(String uid) async {
    final exists = await ref
        .read(myAstrologerAccountProvider.notifier)
        .loadFromFirestore(uid);
    if (!mounted) return;
    if (exists) {
      context.go('/astrologer-dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No astrologer profile found — please complete registration.')));
      context.go('/astrologer-register');
    }
  }

  Future<void> _signIn() async {
    // Demo bypass: no backend — go to the demo signup/onboarding flow.
    if (kBypassAuth) {
      final onboarded = ref.read(isAstrologerOnboardedProvider);
      context.go(onboarded ? '/astrologer-dashboard' : '/astrologer-register');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authNotifierProvider.notifier).signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
    final auth = ref.read(authNotifierProvider);
    if (!mounted) return;
    if (auth.hasError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(auth.error.toString())));
    } else if (auth.valueOrNull != null) {
      await _afterAuth(auth.valueOrNull!.uid);
    }
  }

  Future<void> _signInWithGoogle() async {
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    final auth = ref.read(authNotifierProvider);
    if (auth.hasError) {
      final err = auth.error;
      if (!(err is AuthException && err.cancelled)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(err is AuthException
                ? err.message
                : 'Google Sign-In failed. Please try again.')));
      }
      return;
    }
    final user = auth.valueOrNull;
    if (user != null) await _afterAuth(user.uid);
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);
    final isLoading = authAsync.isLoading;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 32),
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
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back, Guruji',
                            style: AppTextStyles.heading2),
                        const SizedBox(height: 4),
                        Text('Sign in to manage your consultations',
                            style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 22),
                        AppTextField(
                          controller: _emailController,
                          label: 'Email',
                          hint: 'astrologer@email.com',
                          keyboardType: TextInputType.emailAddress,
                          validator: Validators.email,
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hint: '••••••••',
                          obscureText: _obscurePassword,
                          validator: Validators.password,
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context.push('/forgot-password'),
                            child: const Text('Forgot Password?'),
                          ),
                        ),
                        GradientButton(
                          onPressed: isLoading ? null : _signIn,
                          isLoading: isLoading,
                          text: 'Sign In',
                          gradient: AppColors.goldGradient,
                        ),
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
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : _signInWithGoogle,
                          icon: Image.network(
                            'https://www.google.com/favicon.ico',
                            width: 20,
                            height: 20,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.g_mobiledata, size: 24),
                          ),
                          label: const Text('Continue with Google'),
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
                            const Text('New astrologer? '),
                            GestureDetector(
                              onTap: () => context.push('/astrologer-register'),
                              child: Text(
                                'Register',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.goldDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
