import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/login_identifier.dart';
import '../../core/utils/otp_throttle.dart';
import '../../core/utils/validators.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/account_admin_backend.dart';
import '../../widgets/auth/contact_admin_reset_sheet.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Password recovery.
///
/// **Mobile number + OTP (primary).** Accounts in this app are Firebase
/// e-mail/password credentials — a phone-only member's credential uses a
/// synthesized address — so Firebase has no built-in "reset by SMS". The flow
/// is therefore:
///
///  1. the member enters their registered number; it must be in the phone
///     registry (`login_index`), otherwise they are pointed at the admin;
///  2. Firebase Phone Auth sends the OTP (resend with cooldown, per-number send
///     cap, wrong-code limit — see [OtpThrottle]);
///  3. the OTP signs the device into a short-lived PHONE identity, proving the
///     SIM — never linked to anything;
///  4. the trusted backend (`resetPasswordWithPhone`) says which password
///     account(s) the number may reset — masked, and it refuses outright when
///     the number belongs to more than one matrimony profile;
///  5. new password + confirmation;
///  6. the backend sets it, ends every other session of that account, marks
///     the verification used (it cannot be replayed) and deletes the throwaway
///     phone identity; the device is signed out and the member logs in.
///
/// **E-mail.** Firebase's own reset link, for members with a real address.
///
/// **Contact Admin.** Always offered, and the fallback whenever OTP recovery
/// is unavailable (Phone Auth SMS and Cloud Functions both need the Blaze
/// plan), fails, or cannot safely identify the account.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

enum _Method { phone, email }

enum _PhoneStage { enterNumber, enterCode, chooseAccount, newPassword, done }

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  _Method _method = _Method.phone;

  // ── Email path ──────────────────────────────────────────────────────────
  final _emailFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _emailSent = false;

  // ── Phone path ──────────────────────────────────────────────────────────
  final _phoneFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  _PhoneStage _stage = _PhoneStage.enterNumber;
  String _mobile = '';
  String? _verificationId;
  int? _resendToken;
  int _wrongCodes = 0;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  /// Seconds until the OTP may be re-sent.
  int _resendIn = 0;
  Timer? _resendTimer;

  /// The verified phone identity, and whether Firebase created it just now
  /// (only then is it a throwaway this screen may delete).
  User? _session;
  bool _sessionIsNew = false;

  List<RecoveryAccountOption> _accounts = const [];
  String _accountRef = '';

  /// An inline explanation under the current step, plus whether to offer the
  /// admin path right there.
  String? _notice;
  bool _noticeIsError = true;
  bool _offerAdmin = false;

  bool _busy = false;

  AccountAdminBackend get _backend => ref.read(accountAdminBackendProvider);

  @override
  void dispose() {
    _resendTimer?.cancel();
    // Leaving mid-recovery must not leave the device signed in to the OTP
    // identity. Detached: the widget is going away.
    if (_session != null && _stage != _PhoneStage.done) {
      unawaited(_endRecoverySession());
    }
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _say(String? message, {bool error = true, bool offerAdmin = false}) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _noticeIsError = error;
      _offerAdmin = offerAdmin;
    });
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
      _say(e is AuthException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Phone: 1-2. number → OTP ────────────────────────────────────────────

  void _startResendCountdown(Duration wait) {
    _resendTimer?.cancel();
    setState(() => _resendIn = wait.inSeconds.clamp(0, 3600));
    if (_resendIn == 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = (_resendIn - 1).clamp(0, 3600));
      if (_resendIn == 0) t.cancel();
    });
  }

  Future<void> _sendOtp({bool resend = false}) async {
    final l10n = context.l10n;
    if (!resend && !(_phoneFormKey.currentState?.validate() ?? false)) return;
    final mobile = resend
        ? _mobile
        : (LoginIdentifier.localMobile(_phoneController.text) ?? '');
    if (mobile.isEmpty) return;

    final wait = OtpThrottle.waitBeforeSend(
        await OtpThrottle.loadSends(mobile), DateTime.now());
    if (!mounted) return;
    if (wait > Duration.zero) {
      if (OtpThrottle.isLockout(wait)) {
        _say(l10n.recoveryTooManyRequests((wait.inMinutes + 1).clamp(1, 60)),
            offerAdmin: true);
      } else if (resend) {
        _startResendCountdown(wait);
      } else {
        _say(l10n.recoveryResendIn(wait.inSeconds.clamp(1, 60)), error: false);
      }
      return;
    }

    setState(() => _busy = true);
    _say(null);
    if (!resend) {
      // 1. The number must belong to an account. The registry is readable
      //    before sign-in, so this reveals nothing the login screen does not.
      try {
        final entry = await ref.read(loginDirectoryServiceProvider).lookup(mobile);
        if (entry == null) {
          if (mounted) setState(() => _busy = false);
          _say(l10n.recoveryNoAccountFound, offerAdmin: true);
          return;
        }
      } catch (e) {
        debugPrint('[ForgotPassword] registry lookup failed: $e');
        if (mounted) setState(() => _busy = false);
        _say(l10n.recoveryCheckFailed);
        return;
      }
    }

    // 2. Send (or re-send) the OTP.
    await ref.read(authServiceProvider).sendRecoveryOtp(
          mobile: mobile,
          forceResendingToken: resend ? _resendToken : null,
          onCodeSent: (verificationId, resendToken) {
            if (!mounted) return;
            unawaited(OtpThrottle.recordSend(mobile));
            _otpController.clear();
            setState(() {
              _mobile = mobile;
              _verificationId = verificationId;
              _resendToken = resendToken;
              _wrongCodes = 0;
              _stage = _PhoneStage.enterCode;
              _busy = false;
            });
            _startResendCountdown(OtpThrottle.resendCooldown);
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _busy = false);
            final unavailable = error.code == 'otp-unavailable' ||
                error.code == 'operation-not-allowed';
            _say(unavailable ? l10n.recoveryOtpUnavailable : error.message,
                offerAdmin: true);
          },
          // Android can read the SMS itself — verify with it straight away.
          onAutoVerified: (credential) {
            if (!mounted || _stage != _PhoneStage.enterCode) return;
            unawaited(_verifyCode(credential: credential));
          },
        );
  }

  // ── Phone: 3-4. OTP → verified identity → which account ─────────────────

  Future<void> _verifyCode({PhoneAuthCredential? credential}) async {
    final l10n = context.l10n;
    if (credential == null &&
        !(_codeFormKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_wrongCodes >= OtpThrottle.maxWrongCodes) {
      _say(l10n.recoveryTooManyWrongCodes);
      return;
    }
    setState(() => _busy = true);
    _say(null);
    try {
      final result = await ref.read(authServiceProvider).signInForRecovery(
            verificationId: _verificationId,
            smsCode: _otpController.text.trim(),
            credential: credential,
          );
      _session = result.user;
      _sessionIsNew = result.isNew;
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'invalid-verification-code') {
        _wrongCodes++;
        _say(_wrongCodes >= OtpThrottle.maxWrongCodes
            ? l10n.recoveryTooManyWrongCodes
            : e.message);
      } else if (e.code == 'session-expired') {
        _say(l10n.recoveryCodeExpired);
      } else {
        _say(e.message, offerAdmin: true);
      }
      return;
    }

    try {
      final lookup = await _backend.recoveryLookup(_mobile);
      if (!mounted) return;
      if (lookup.accounts.isEmpty) {
        await _abandon(l10n.recoveryNoAccountFound);
        return;
      }
      setState(() {
        _busy = false;
        _accounts = lookup.accounts;
        _accountRef = lookup.accounts.length == 1 ? lookup.accounts.first.ref : '';
        _stage = lookup.status == 'select' && lookup.accounts.length > 1
            ? _PhoneStage.chooseAccount
            : _PhoneStage.newPassword;
      });
    } on AccountBackendException catch (e) {
      await _handleBackendError(e);
    }
  }

  Future<void> _handleBackendError(AccountBackendException e) async {
    final l10n = context.l10n;
    if (e.isUnavailable) {
      await _abandon(l10n.phoneResetUnavailable);
      return;
    }
    switch (e.reason) {
      case 'multiple-profiles':
        await _abandon(l10n.recoveryMultipleProfiles);
      case 'no-account':
        await _abandon(l10n.recoveryNoAccountFound);
      case 'otp-expired':
      case 'otp-already-used':
        await _abandon(l10n.recoveryCodeExpired, offerAdmin: false);
      default:
        await _abandon(e.message);
    }
  }

  /// Ends the OTP session and returns to the number step with [message].
  Future<void> _abandon(String message, {bool offerAdmin = true}) async {
    await _endRecoverySession();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _stage = _PhoneStage.enterNumber;
      _accounts = const [];
      _accountRef = '';
    });
    _say(message, offerAdmin: offerAdmin);
  }

  /// Signs the verified phone identity out — deleting it first when Firebase
  /// created it just for this recovery, so abandoned attempts leave no orphan
  /// logins — and puts the device back into Guest Mode.
  Future<void> _endRecoverySession() async {
    final session = _session;
    _session = null;
    // Read up front: this also runs from dispose(), after which `ref` may no
    // longer be used.
    final auth = ref.read(authServiceProvider);
    final repo = ref.read(authRepositoryProvider);
    if (session != null && _sessionIsNew && auth.currentUserId == session.uid) {
      try {
        await session.delete();
      } catch (e) {
        debugPrint('[ForgotPassword] throwaway identity delete skipped: $e');
      }
    }
    try {
      await auth.signOut();
    } catch (_) {}
    try {
      await repo.signInAsGuest();
    } catch (e) {
      debugPrint('[ForgotPassword] guest session not restored: $e');
    }
  }

  // ── Phone: 5-6. new password → reset ────────────────────────────────────

  Future<void> _resetPassword() async {
    if (!(_passwordFormKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    _say(null);
    try {
      await _backend.resetPasswordWithOtp(
        mobile: _mobile,
        newPassword: _newPasswordController.text,
        accountRef: _accounts.length > 1 ? _accountRef : '',
      );
      // The backend already deleted the throwaway identity; never try again.
      _sessionIsNew = false;
      await _endRecoverySession();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _PhoneStage.done;
      });
    } on AccountBackendException catch (e) {
      if (!mounted) return;
      if (e.code == 'invalid-argument') {
        setState(() => _busy = false);
        _say(e.message);
        return;
      }
      await _handleBackendError(e);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
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
                    if (_stage == _PhoneStage.enterNumber) ...[
                      _methodSelector(l10n),
                      const SizedBox(height: 22),
                    ],
                    if (_method == _Method.email)
                      _emailSent ? _emailSuccess(l10n) : _emailForm(l10n)
                    else
                      _phoneBody(l10n),
                    if (_notice != null) _noticeBox(l10n),
                    if (_stage != _PhoneStage.done) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => showContactAdminResetSheet(context,
                                  mobile: _mobile.isNotEmpty
                                      ? _mobile
                                      : _phoneController.text),
                          icon: const Icon(Icons.support_agent_outlined,
                              size: 18),
                          label: Text(l10n.contactAdminToReset),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _noticeBox(AppLocalizations l10n) {
    final color = _noticeIsError ? AppColors.error : AppColors.success;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_notice!, style: TextStyle(color: color, height: 1.35)),
          if (_offerAdmin) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showContactAdminResetSheet(context,
                  mobile: _mobile.isNotEmpty ? _mobile : _phoneController.text),
              icon: const Icon(Icons.support_agent_outlined, size: 18),
              label: Text(l10n.contactAdminToReset),
            ),
          ],
        ],
      ),
    );
  }

  /// Segmented Mobile Number | Email switch — mobile first, it is primary.
  Widget _methodSelector(AppLocalizations l10n) {
    Widget tab(_Method value, String label, IconData icon) {
      final selected = _method == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy
              ? null
              : () => setState(() {
                    _method = value;
                    _notice = null;
                  }),
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
                      color: selected ? Colors.white : AppColors.textSecondary,
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
          tab(_Method.phone, l10n.resetViaPhone, Icons.smartphone_outlined),
          tab(_Method.email, l10n.resetViaEmail, Icons.email_outlined),
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
          Text(l10n.resetPasswordIntroEmail, style: AppTextStyles.bodyMedium),
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
            l10n.resetLinkSentTo(_emailController.text.trim()),
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

  Widget _passwordToggle(bool obscure, VoidCallback onTap) => IconButton(
        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
        onPressed: onTap,
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
              Text(l10n.recoveryEnterRegisteredMobile,
                  style: AppTextStyles.bodyMedium),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(l10n.recoveryCountryIndia,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextField(
                      controller: _phoneController,
                      label: l10n.mobileNumber,
                      hint: '9876543210',
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      validator: context.validators.mobile,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              GradientButton(
                onPressed: _busy ? null : () => _sendOtp(),
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
              Text(l10n.otpVerification, style: AppTextStyles.heading2),
              const SizedBox(height: 8),
              Text(l10n.enterCodeSentTo('+91 $_mobile'),
                  style: AppTextStyles.bodyMedium),
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
              const SizedBox(height: 24),
              GradientButton(
                onPressed: _busy || _wrongCodes >= OtpThrottle.maxWrongCodes
                    ? null
                    : () => _verifyCode(),
                isLoading: _busy,
                text: l10n.recoveryVerifyOtp,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _stage = _PhoneStage.enterNumber;
                              _notice = null;
                            }),
                    child: Text(l10n.mobileNumber),
                  ),
                  TextButton(
                    onPressed: _busy || _resendIn > 0
                        ? null
                        : () => _sendOtp(resend: true),
                    child: Text(_resendIn > 0
                        ? l10n.recoveryResendIn(_resendIn)
                        : l10n.resendOtp),
                  ),
                ],
              ),
            ],
          ),
        );
      case _PhoneStage.chooseAccount:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.recoveryChooseAccount, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 12),
            for (final a in _accounts)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: _accountRef == a.ref
                          ? AppColors.primary
                          : AppColors.divider),
                ),
                child: ListTile(
                  leading: Icon(
                    _accountRef == a.ref
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: AppColors.primary,
                  ),
                  title: Text(a.label == 'Mobile number login'
                      ? l10n.recoveryMobileLogin
                      : a.label),
                  subtitle: a.name.isEmpty ? null : Text(a.name),
                  onTap: () => setState(() => _accountRef = a.ref),
                ),
              ),
            const SizedBox(height: 16),
            GradientButton(
              onPressed: _accountRef.isEmpty
                  ? null
                  : () => setState(() => _stage = _PhoneStage.newPassword),
              text: l10n.recoverySetNewPassword,
            ),
          ],
        );
      case _PhoneStage.newPassword:
        return Form(
          key: _passwordFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.recoverySetNewPassword, style: AppTextStyles.heading2),
              const SizedBox(height: 8),
              Text(l10n.recoverySetNewPasswordIntro,
                  style: AppTextStyles.bodyMedium),
              const SizedBox(height: 24),
              AppTextField(
                controller: _newPasswordController,
                label: l10n.newPassword,
                hint: '••••••',
                obscureText: _obscureNew,
                validator: Validators.password,
                suffixIcon: _passwordToggle(
                    _obscureNew, () => setState(() => _obscureNew = !_obscureNew)),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _confirmPasswordController,
                label: l10n.confirmPassword,
                hint: '••••••',
                obscureText: _obscureConfirm,
                validator: (v) =>
                    Validators.confirmPassword(v, _newPasswordController.text),
                suffixIcon: _passwordToggle(_obscureConfirm,
                    () => setState(() => _obscureConfirm = !_obscureConfirm)),
              ),
              const SizedBox(height: 24),
              GradientButton(
                onPressed: _busy ? null : _resetPassword,
                isLoading: _busy,
                text: l10n.recoveryResetButton,
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
            Text(l10n.recoveryNewPasswordWorks,
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
