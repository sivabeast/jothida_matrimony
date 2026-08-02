import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/login_identifier.dart';
import '../../core/utils/validators.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/callable_functions_client.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Password recovery for BOTH login identifiers.
///
///  • **Email** — Firebase sends its password-reset link. Nothing else is
///    needed and it works entirely client-side.
///  • **Mobile Number** — a real OTP flow: Firebase Phone Auth sends the SMS
///    code, the member enters it together with their new password, and the
///    `resetPasswordWithPhone` Cloud Function (which verifies the OTP session
///    belongs to that exact number) sets the password on their account.
///
/// The phone path needs the function deployed
/// (`firebase deploy --only functions:resetPasswordWithPhone`); until then it
/// reports that clearly and points the member at the e-mail path instead of
/// failing silently.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

enum _Method { email, phone }

enum _PhoneStage { enterNumber, enterCode, done }

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  _Method _method = _Method.email;

  // ── Email path ──────────────────────────────────────────────────────────
  final _emailFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _emailSent = false;

  // ── Phone path ──────────────────────────────────────────────────────────
  final _phoneFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  _PhoneStage _stage = _PhoneStage.enterNumber;
  String? _verificationId;
  bool _obscureNew = true;

  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Email reset ─────────────────────────────────────────────────────────

  Future<void> _sendResetEmail() async {
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authServiceProvider)
          .sendPasswordReset(_emailController.text.trim());
      if (!mounted) return;
      setState(() => _emailSent = true);
    } catch (e) {
      _snack(e is AuthException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Phone (OTP) reset ───────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    if (!(_phoneFormKey.currentState?.validate() ?? false)) return;
    final mobile = LoginIdentifier.localMobile(_phoneController.text) ?? '';
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).verifyPhone(
            phoneNumber: mobile,
            onCodeSent: (id) {
              if (!mounted) return;
              setState(() {
                _verificationId = id;
                _stage = _PhoneStage.enterCode;
                _busy = false;
              });
            },
            onError: (message) {
              if (!mounted) return;
              setState(() => _busy = false);
              _snack(message);
            },
            // Android may auto-retrieve the SMS. We never auto-submit — the new
            // password still has to be typed — so this only clears the spinner.
            onAutoVerified: (_) {
              if (mounted) setState(() => _busy = false);
            },
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e is AuthException ? e.message : e.toString());
    }
  }

  Future<void> _verifyAndReset() async {
    if (!(_codeFormKey.currentState?.validate() ?? false)) return;
    final verificationId = _verificationId;
    if (verificationId == null) return;
    final mobile = LoginIdentifier.localMobile(_phoneController.text) ?? '';
    final l10n = context.l10n;
    setState(() => _busy = true);
    final repo = ref.read(authRepositoryProvider);
    try {
      // 1. Prove possession of the SIM. This signs the device into a
      //    short-lived PHONE identity — not the member's password account.
      await repo.signInWithOTP(verificationId, _otpController.text.trim());
      // 2. The server matches that verified number to the account and sets the
      //    new password, then disposes of the throwaway phone identity.
      await CallableFunctionsClient().call('resetPasswordWithPhone', data: {
        'mobile': mobile,
        'newPassword': _newPasswordController.text,
      });
      // 3. Never leave the device signed in as the temporary identity.
      await repo.signOut().catchError((Object e) {
        debugPrint('[ForgotPassword] post-reset sign-out skipped: $e');
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _PhoneStage.done;
      });
    } on CallableFunctionException catch (e) {
      await repo.signOut().catchError((Object _) {});
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.isUnavailable ? l10n.phoneResetUnavailable : e.message);
    } catch (e) {
      await repo.signOut().catchError((Object _) {});
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e is AuthException ? e.message : e.toString());
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(l10n.resetPassword),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: Icon(Icons.lock_reset,
                        size: 64, color: AppColors.primary),
                  ),
                  const SizedBox(height: 18),
                  _methodSelector(l10n),
                  const SizedBox(height: 22),
                  if (_method == _Method.email)
                    _emailSent ? _emailSuccess(l10n) : _emailForm(l10n)
                  else
                    _phoneBody(l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Segmented Email | Mobile Number switch.
  Widget _methodSelector(AppLocalizations l10n) {
    Widget tab(_Method value, String label, IconData icon) {
      final selected = _method == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => setState(() => _method = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: selected ? Colors.white : AppColors.textSecondary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color:
                          selected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          tab(_Method.email, l10n.resetViaEmail, Icons.email_outlined),
          tab(_Method.phone, l10n.resetViaPhone,
              Icons.smartphone_outlined),
        ],
      ),
    );
  }

  Widget _emailForm(AppLocalizations l10n) {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.resetPassword, style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(l10n.resetPasswordIntroEmail,
              style: AppTextStyles.bodyMedium),
          const SizedBox(height: 24),
          AppTextField(
            controller: _emailController,
            label: l10n.email,
            hint: 'you@email.com',
            keyboardType: TextInputType.emailAddress,
            validator: Validators.email,
          ),
          const SizedBox(height: 24),
          GradientButton(
            onPressed: _busy ? null : _sendResetEmail,
            isLoading: _busy,
            text: l10n.sendResetLink,
          ),
        ],
      ),
    );
  }

  Widget _emailSuccess(AppLocalizations l10n) => Column(
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.mark_email_read_outlined,
              size: 72, color: AppColors.primary),
          const SizedBox(height: 20),
          Text(l10n.resetPassword, style: AppTextStyles.heading2),
          const SizedBox(height: 12),
          Text(
            l10n.resetLinkSentTo(
                _emailController.text.trim()),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 28),
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text(l10n.backToLogin),
          ),
        ],
      );

  Widget _phoneBody(AppLocalizations l10n) {
    switch (_stage) {
      case _PhoneStage.enterNumber:
        return Form(
          key: _phoneFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.resetPassword, style: AppTextStyles.heading2),
              const SizedBox(height: 8),
              Text(l10n.resetPasswordIntroPhone,
                  style: AppTextStyles.bodyMedium),
              const SizedBox(height: 24),
              AppTextField(
                controller: _phoneController,
                label: l10n.mobileNumber,
                hint: '9876543210',
                keyboardType: TextInputType.phone,
                prefixText: '+91 ',
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: context.validators.mobile,
              ),
              const SizedBox(height: 24),
              GradientButton(
                onPressed: _busy ? null : _sendOtp,
                isLoading: _busy,
                text: l10n.sendVerificationCode,
              ),
            ],
          ),
        );
      case _PhoneStage.enterCode:
        return Form(
          key: _codeFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.otpVerification,
                  style: AppTextStyles.heading2),
              const SizedBox(height: 8),
              Text(
                l10n.enterCodeSentTo(
                    '+91 ${_phoneController.text.trim()}'),
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 24),
              AppTextField(
                controller: _otpController,
                label: l10n.enterOtp,
                hint: '000000',
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                validator: Validators.otp,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _newPasswordController,
                label: l10n.newPassword,
                hint: '••••••',
                obscureText: _obscureNew,
                validator: Validators.password,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureNew ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _confirmPasswordController,
                label: l10n.confirmPassword,
                hint: '••••••',
                obscureText: true,
                validator: (v) => Validators.confirmPassword(
                    v, _newPasswordController.text),
              ),
              const SizedBox(height: 24),
              GradientButton(
                onPressed: _busy ? null : _verifyAndReset,
                isLoading: _busy,
                text: l10n.verifyAndReset,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _stage = _PhoneStage.enterNumber),
                  child: Text(l10n.resendOtp),
                ),
              ),
            ],
          ),
        );
      case _PhoneStage.done:
        return Column(
          children: [
            const SizedBox(height: 12),
            const Icon(Icons.verified_user_outlined,
                size: 72, color: AppColors.success),
            const SizedBox(height: 20),
            Text(l10n.passwordResetSuccess,
                textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 28),
            GradientButton(
              onPressed: () => context.go('/login'),
              text: l10n.backToLogin,
            ),
          ],
        );
    }
  }
}
