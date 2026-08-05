import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../widgets/common/app_logo.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/validators.dart';
import '../../core/utils/value_l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wedding_provider.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

/// **Account creation** — deliberately NOT profile creation.
///
/// This page only opens a login for the member: Full Name, Mobile Number,
/// Email Address, Password, Confirm Password, Gender, Date of Birth and the
/// Terms & Conditions acceptance. Nothing matrimony-specific is asked here.
///
/// On success the account is created, the member is signed in automatically and
/// sent straight to the **Home page**. The matrimony profile is created later,
/// only when they tap "Create Profile" on Home.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _gender = '';
  DateTime? _dob;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 80),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: context.l10n.dateOfBirth,
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobController.text = DateFormat('dd MMM yyyy').format(picked);
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _register() async {
    final l10n = context.l10n;
    debugPrint('[RegisterScreen] "Create Account" tapped.');
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_gender.isEmpty) {
      _snack(l10n.pleaseSelectGender);
      return;
    }
    if (_dob == null) {
      _snack(l10n.pleaseSelectDob);
      return;
    }
    if (!_acceptedTerms) {
      _snack(l10n.pleaseAcceptTerms);
      return;
    }

    await ref.read(authNotifierProvider.notifier).registerUser(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          gender: _gender,
          dateOfBirth: _dob!,
        );
    final auth = ref.read(authNotifierProvider);
    if (!mounted) return;
    if (auth.hasError) {
      final err = auth.error;
      final message =
          err is AuthException ? err.message : l10n.registrationFailed;
      debugPrint('[RegisterScreen] registerUser error: $err');
      _snack(message);
      return;
    }
    final user = auth.valueOrNull;
    if (user == null) {
      _snack(l10n.registrationFailed);
      return;
    }
    debugPrint('[RegisterScreen] account created (uid=${user.uid}) — '
        'signed in automatically, going straight to Home.');
    // The member is already authenticated by `createUserWithEmailAndPassword`.
    // Profile creation is NEVER forced: Home shows the "Create Profile" card.
    ref.read(entryModeProvider.notifier).state = WeddingEntryMode.matrimony;
    await WeddingEntryMode.save(WeddingEntryMode.matrimony);
    if (!mounted) return;
    _snack(l10n.accountCreatedWelcome);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final v = context.validators;
    final busy = ref.watch(authNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        // English "Create Account" / Tamil "புதிய கணக்கை உருவாக்கு" — this page
        // is ONLY about opening an account, never a marriage registration.
        title: Text(l10n.createAccount),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: AppLauncherLogo(size: 88)),
                    const SizedBox(height: 14),
                    Text(
                      l10n.createAccount,
                      style: const TextStyle(
                          fontFamily: 'serif',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.createAccountSubtitle,
                        style:
                            TextStyle(color: Colors.grey.shade600, fontSize: 13.5)),
                    const SizedBox(height: 24),
                    AppTextField(
                      controller: _nameController,
                      label: '${l10n.fullName} *',
                      hint: l10n.fullName,
                      textCapitalization: TextCapitalization.words,
                      validator: v.name,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _phoneController,
                      label: '${l10n.mobileNumber} *',
                      hint: '9876543210',
                      keyboardType: TextInputType.phone,
                      prefixText: '+91 ',
                      maxLength: 10,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      validator: v.mobile,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _emailController,
                      label: '${l10n.email} *',
                      hint: 'you@email.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: v.email,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _passwordController,
                      label: '${l10n.password} *',
                      hint: '••••••',
                      obscureText: _obscurePass,
                      validator: Validators.password,
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePass
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _confirmPasswordController,
                      label: '${l10n.confirmPassword} *',
                      hint: '••••••',
                      obscureText: _obscureConfirm,
                      validator: (val) => Validators.confirmPassword(
                          val, _passwordController.text),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('${l10n.gender} *',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _genderChip(context.localizeValue('Male'), 'Male', Icons.male),
                        const SizedBox(width: 12),
                        _genderChip(context.localizeValue('Female'), 'Female', Icons.female),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _dobController,
                      label: '${l10n.dateOfBirth} *',
                      hint: 'dd mmm yyyy',
                      readOnly: true,
                      onTap: _pickDob,
                      suffixIcon: const Icon(Icons.calendar_today, size: 18),
                      validator: (val) => (val == null || val.isEmpty)
                          ? context.l10n.pleaseSelectDob
                          : null,
                    ),
                    const SizedBox(height: 18),
                    // Terms & Conditions acceptance — mandatory.
                    InkWell(
                      onTap: () =>
                          setState(() => _acceptedTerms = !_acceptedTerms),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _acceptedTerms,
                              activeColor: AppColors.primary,
                              onChanged: (val) =>
                                  setState(() => _acceptedTerms = val ?? false),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  l10n.acceptTermsLabel,
                                  // Long Tamil sentence: wraps between whole
                                  // words, never clipped.
                                  softWrap: true,
                                  style: const TextStyle(
                                      fontSize: 13, height: 1.35),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    GradientButton(
                      onPressed: busy ? null : _register,
                      isLoading: busy,
                      text: l10n.createAccount,
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(l10n.alreadyHaveAccount,
                              style: TextStyle(
                                  color: Colors.grey.shade700, fontSize: 13.5)),
                          GestureDetector(
                            onTap: busy
                                ? null
                                : () => context.canPop()
                                    ? context.pop()
                                    : context.go('/login'),
                            child: Text(
                              l10n.signIn,
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Gender selector. The stored value stays English ('Male'/'Female') so the
  /// matching rules keep working; only the label follows the app language.
  Widget _genderChip(String label, String value, IconData icon) {
    final selected = _gender == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _gender = value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
