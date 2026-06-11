import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/dev_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Astrologer signup — collects name, mobile, experience, specialization and
/// location (plus email/password credentials), saves the account to Firestore
/// `astrologers/{uid}` and opens the dashboard.
class AstrologerRegisterScreen extends ConsumerStatefulWidget {
  const AstrologerRegisterScreen({super.key});

  @override
  ConsumerState<AstrologerRegisterScreen> createState() =>
      _AstrologerRegisterScreenState();
}

class _AstrologerRegisterScreenState
    extends ConsumerState<AstrologerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _experienceController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final Set<String> _specializations = {};
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _experienceController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  AstrologerAccount _buildAccount(String id) => AstrologerAccount(
        id: id,
        fullName: _nameController.text.trim(),
        gender: '',
        dob: null,
        mobile: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        country: 'India',
        experienceYears: int.tryParse(_experienceController.text.trim()) ?? 0,
        expertise: _specializations.toList(),
        languages: const ['Tamil', 'English'],
        about: '',
        consultationModes: const ['Chat', 'Audio Call', 'Video Call'],
        certName: '',
        certOrg: '',
        certNumber: '',
        certFileName: '',
      );

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_specializations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select at least one specialization')));
      return;
    }

    // Demo bypass: create the session locally and open the dashboard.
    if (kBypassAuth) {
      ref
          .read(myAstrologerAccountProvider.notifier)
          .completeOnboarding(_buildAccount('demo-astrologer'));
      context.go('/astrologer-dashboard');
      return;
    }

    setState(() => _submitting = true);
    try {
      // 1. Create (or reuse) the Firebase Auth account.
      final notifier = ref.read(authNotifierProvider.notifier);
      await notifier.registerWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
      final auth = ref.read(authNotifierProvider);
      if (auth.hasError) throw auth.error!;
      final uid = auth.valueOrNull!.uid;

      // 2. Save the astrologer account + role to Firestore.
      final account = _buildAccount(uid);
      await ref.read(astrologerServiceProvider).createAccount(uid, account);

      // 3. Hydrate the session and open the dashboard.
      ref
          .read(myAstrologerAccountProvider.notifier)
          .completeOnboarding(account);
      if (mounted) context.go('/astrologer-dashboard');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Astrologer Registration'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Join as an Astrologer', style: AppTextStyles.heading2),
              const SizedBox(height: 4),
              Text('Offer consultations & horoscope matching to thousands',
                  style: AppTextStyles.bodyMedium),
              const SizedBox(height: 28),
              AppTextField(
                controller: _nameController,
                label: 'Full Name',
                hint: 'Your name',
                validator: Validators.name,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _phoneController,
                label: 'Mobile Number',
                hint: '9876543210',
                keyboardType: TextInputType.phone,
                prefixText: '+91 ',
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: Validators.phone,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _experienceController,
                label: 'Experience (years)',
                hint: 'e.g. 8',
                keyboardType: TextInputType.number,
                maxLength: 2,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Experience is required';
                  final years = int.tryParse(v);
                  if (years == null || years < 0 || years > 70) {
                    return 'Enter valid years of experience';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('Specialization',
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in AppConstants.astrologerSpecializations)
                    FilterChip(
                      label: Text(s, style: const TextStyle(fontSize: 12.5)),
                      selected: _specializations.contains(s),
                      selectedColor: AppColors.primary.withOpacity(0.12),
                      checkmarkColor: AppColors.primary,
                      onSelected: (sel) => setState(() {
                        sel
                            ? _specializations.add(s)
                            : _specializations.remove(s);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _cityController,
                      label: 'City',
                      hint: 'Chennai',
                      validator: (v) =>
                          Validators.required(v, fieldName: 'City'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: _stateController,
                      label: 'State',
                      hint: 'Tamil Nadu',
                      validator: (v) =>
                          Validators.required(v, fieldName: 'State'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              Text('Login credentials',
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              AppTextField(
                controller: _emailController,
                label: 'Email Address',
                hint: 'your@email.com',
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _passwordController,
                label: 'Password',
                hint: 'Min. 6 characters',
                obscureText: _obscurePass,
                validator: Validators.password,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _confirmPasswordController,
                label: 'Confirm Password',
                hint: 'Re-enter password',
                obscureText: _obscureConfirm,
                validator: (val) =>
                    Validators.confirmPassword(val, _passwordController.text),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              const SizedBox(height: 32),
              GradientButton(
                onPressed: _submitting ? null : _register,
                isLoading: _submitting,
                text: 'Create Astrologer Account',
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already registered? '),
                  GestureDetector(
                    onTap: () => context.go('/astrologer-login'),
                    child: Text(
                      'Sign In',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
