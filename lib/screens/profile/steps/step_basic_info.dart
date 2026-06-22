import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';

/// Step 2 — Basic Information: Full Name, Gender, Date of Birth.
/// Age is auto-calculated from the DOB and shown read-only.
class StepBasicInfo extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepBasicInfo({super.key, required this.onNext});

  @override
  ConsumerState<StepBasicInfo> createState() => _StepBasicInfoState();
}

class _StepBasicInfoState extends ConsumerState<StepBasicInfo> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  String? _gender;
  DateTime? _dob;

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _nameController.text = (data['name'] as String?) ?? '';
    _gender = data['gender'] as String?;
    final dobStr = data['dateOfBirth'] as String?;
    if (dobStr != null) {
      _dob = DateTime.tryParse(dobStr);
      if (_dob != null) {
        _dobController.text = '${_dob!.day}/${_dob!.month}/${_dob!.year}';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  int? get _age {
    if (_dob == null) return null;
    final now = DateTime.now();
    var age = now.year - _dob!.year;
    if (now.month < _dob!.month ||
        (now.month == _dob!.month && now.day < _dob!.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1995),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
    );
    if (date != null) {
      setState(() {
        _dob = date;
        _dobController.text = '${date.day}/${date.month}/${date.year}';
      });
    }
  }

  void _saveAndNext() {
    if (!_formKey.currentState!.validate()) return;
    if (_gender == null) {
      _snack('Please select a gender');
      return;
    }
    if (_dob == null) {
      _snack('Please select your date of birth');
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'name': _nameController.text.trim(),
      'gender': _gender,
      'dateOfBirth': _dob!.toIso8601String(),
      'age': _age ?? 0,
    });
    widget.onNext();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Basic Information', style: AppTextStyles.heading2),
            const SizedBox(height: 8),
            const Text('Let’s start with the essentials.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            AppTextField(
              controller: _nameController,
              label: 'Full Name *',
              validator: Validators.name,
            ),
            const SizedBox(height: 20),
            const Text('Gender *',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _genderCard('Male', Icons.male)),
                const SizedBox(width: 16),
                Expanded(child: _genderCard('Female', Icons.female)),
              ],
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _dobController,
              label: 'Date of Birth *',
              hint: 'DD/MM/YYYY',
              readOnly: true,
              onTap: _pickDate,
              suffixIcon: const Icon(Icons.calendar_today),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            if (_age != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cake_outlined,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('Age: $_age years',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 36),
            GradientButton(onPressed: _saveAndNext, text: 'Continue'),
          ],
        ),
      ),
    );
  }

  Widget _genderCard(String gender, IconData icon) {
    final selected = _gender == gender;
    return GestureDetector(
      onTap: () => setState(() => _gender = gender),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 42, color: selected ? Colors.white : Colors.grey[600]),
            const SizedBox(height: 6),
            Text(gender,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 15,
                )),
          ],
        ),
      ),
    );
  }
}
