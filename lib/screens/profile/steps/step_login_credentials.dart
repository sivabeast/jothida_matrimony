import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/login_identifier.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/service_providers.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';

/// FINAL step of the ADMIN "Create Matrimony Profile" flow: the login the
/// member will use.
///
/// The mobile number and e-mail are pre-filled from the Contact Details step of
/// the very same wizard, and the admin can edit either of them. Uniqueness is
/// checked before anything is created, so a duplicate account can never be
/// produced: the mobile number is looked up in the login index here, and a
/// duplicate e-mail is rejected by Firebase itself with a clear message.
///
/// This step exists ONLY in admin mode — a member creating their own profile
/// already has a login.
class StepLoginCredentials extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const StepLoginCredentials({super.key, required this.onNext});

  @override
  ConsumerState<StepLoginCredentials> createState() =>
      _StepLoginCredentialsState();
}

class _StepLoginCredentialsState extends ConsumerState<StepLoginCredentials> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _checking = false;
  String? _mobileError;

  @override
  void initState() {
    super.initState();
    _prefillFromProfile();
  }

  /// Auto-fills from the Contact Details step, so the admin normally only has to
  /// type a password. Anything already entered on this step wins (the admin may
  /// have edited it and stepped back).
  void _prefillFromProfile() {
    final data = ref.read(profileCreationProvider).data;
    final saved = data['loginCredentials'];
    if (saved is Map) {
      _mobileController.text = (saved['mobile'] as String?) ?? '';
      _emailController.text = (saved['email'] as String?) ?? '';
      _passwordController.text = (saved['password'] as String?) ?? '';
      _confirmController.text = _passwordController.text;
    }
    final contact = data['contactDetails'];
    if (contact is Map) {
      if (_mobileController.text.trim().isEmpty) {
        _mobileController.text = (contact['mobileNumber'] as String?) ?? '';
      }
      if (_emailController.text.trim().isEmpty) {
        _emailController.text = (contact['email'] as String?) ?? '';
      }
    }
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _saveAndSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final mobile = LoginIdentifier.localMobile(_mobileController.text) ?? '';

    setState(() {
      _checking = true;
      _mobileError = null;
    });
    try {
      // Uniqueness FIRST — never create a duplicate account.
      final taken = await ref
          .read(loginDirectoryServiceProvider)
          .isPhoneRegistered(mobile);
      if (!mounted) return;
      if (taken) {
        setState(() => _mobileError = l10n.mobileAlreadyRegistered);
        return;
      }
    } catch (e) {
      // A failed lookup must not block the admin: Firebase still rejects a
      // duplicate e-mail, and the mobile index is re-checked server-side by
      // the provisioning step.
      debugPrint('[LoginCredentials] mobile availability check skipped: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted || _mobileError != null) return;

    ref.read(profileCreationProvider.notifier).updateData({
      'loginCredentials': {
        'mobile': mobile,
        'email': _emailController.text.trim().toLowerCase(),
        'password': _passwordController.text,
      },
    });
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final v = context.validators;
    final busy = _checking || ref.watch(profileCreationProvider).isLoading;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.loginCredentials,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(l10n.loginCredentialsHint,
                style: TextStyle(color: Colors.grey.shade600, height: 1.4)),
            const SizedBox(height: 24),
            AppTextField(
              controller: _mobileController,
              label: '${l10n.mobileNumber} *',
              hint: '9876543210',
              keyboardType: TextInputType.phone,
              prefixText: '+91 ',
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              errorText: _mobileError,
              onChanged: (_) {
                if (_mobileError != null) setState(() => _mobileError = null);
              },
              validator: v.mobile,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _emailController,
              label: l10n.email,
              hint: 'name@example.com',
              keyboardType: TextInputType.emailAddress,
              // Optional: a member with no e-mail signs in with their mobile
              // number and password.
              validator: (val) =>
                  (val == null || val.trim().isEmpty) ? null : v.email(val),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _passwordController,
              label: '${l10n.password} *',
              hint: context.l10n.minSixCharacters,
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
            const SizedBox(height: 16),
            AppTextField(
              controller: _confirmController,
              label: '${l10n.confirmPassword} *',
              hint: context.l10n.reEnterPassword,
              obscureText: true,
              validator: (val) =>
                  Validators.confirmPassword(val, _passwordController.text),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The member can sign in with either their mobile number '
                      'or their email address and this password.',
                      style:
                          TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            GradientButton(
              onPressed: busy ? null : _saveAndSubmit,
              isLoading: busy,
              text: l10n.createAccountAndProfile,
            ),
          ],
        ),
      ),
    );
  }
}
