import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/auth_routing.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/app_text_field.dart';

/// User signup — collects only the essentials: name, mobile, gender, date of
/// birth and location, plus email/password credentials. The full matrimony
/// profile is completed later from the Home screen.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _locationController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _gender = '';
  DateTime? _dob;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _locationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 80),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Select your date of birth',
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobController.text = DateFormat('dd MMM yyyy').format(picked);
      });
    }
  }

  Future<void> _register() async {
    debugPrint('[RegisterScreen] "Create Account" tapped for '
        '${_emailController.text.trim()}');
    if (!_formKey.currentState!.validate()) return;
    if (_gender.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select your gender')));
      return;
    }
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select your date of birth')));
      return;
    }

    await ref.read(authNotifierProvider.notifier).registerUser(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          gender: _gender,
          dateOfBirth: _dob!,
          location: _locationController.text.trim(),
        );
    final auth = ref.read(authNotifierProvider);
    if (!mounted) return;
    if (auth.hasError) {
      final err = auth.error;
      final message = err is AuthException
          ? err.message
          : 'Registration failed. Please try again.';
      debugPrint('[RegisterScreen] registerUser error: $err');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } else if (auth.valueOrNull != null) {
      final user = auth.valueOrNull!;
      debugPrint('[RegisterScreen] Registration successful (uid=${user.uid}, '
          'isProfileComplete=${user.isProfileComplete}). Routing...');
      await routeAuthenticatedUser(context, ref, user, tag: 'RegisterScreen');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
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
              Center(
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 100,
                  height: 100,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.favorite,
                          color: AppColors.primary, size: 48),
                ),
              ),
              const SizedBox(height: 12),
              Text('Find your perfect match', style: AppTextStyles.heading2),
              const SizedBox(height: 4),
              Text('A few details to get you started',
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
              // Gender
              Text('Gender',
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _genderChip('Male', Icons.male),
                  const SizedBox(width: 12),
                  _genderChip('Female', Icons.female),
                ],
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _dobController,
                label: 'Date of Birth',
                hint: 'Select date',
                readOnly: true,
                onTap: _pickDob,
                suffixIcon: const Icon(Icons.calendar_today, size: 18),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Date of birth is required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _locationController,
                label: 'Location',
                hint: 'City, State (e.g. Chennai, Tamil Nadu)',
                validator: (v) =>
                    Validators.required(v, fieldName: 'Location'),
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
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
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
                onPressed: authAsync.isLoading ? null : _register,
                isLoading: authAsync.isLoading,
                text: 'Create Account',
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? '),
                  GestureDetector(
                    onTap: () => context.pop(),
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

  Widget _genderChip(String value, IconData icon) {
    final selected = _gender == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _gender = value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withOpacity(0.08)
                : Colors.transparent,
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
                  color:
                      selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                value,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
