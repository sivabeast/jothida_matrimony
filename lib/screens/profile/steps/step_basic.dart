import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';

/// Step 1 — Basic Details. Mirrors the website's "Basic" step exactly:
/// Profile For, Full Name, Gender, Date of Birth, Height, Weight (optional),
/// Marital Status, Physical Status, and — when the marital status implies
/// children — the children count + living status.
class StepBasic extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepBasic({super.key, required this.onNext});

  @override
  ConsumerState<StepBasic> createState() => _StepBasicState();
}

class _StepBasicState extends ConsumerState<StepBasic> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _weightController = TextEditingController();
  final _childrenController = TextEditingController();

  // Who this profile is for — matches the website PROFILE_FOR list.
  static const _profileForOptions = [
    'Myself', 'Son', 'Daughter', 'Brother', 'Sister', 'Relative',
  ];

  String? _profileFor;
  String? _gender;
  DateTime? _dob;
  String? _height;
  String? _maritalStatus;
  String? _physicalStatus;
  String? _childrenLivingStatus;

  bool get _showChildren =>
      _maritalStatus != null &&
      AppConstants.maritalStatusesWithChildren.contains(_maritalStatus);

  int get _childrenCount => int.tryParse(_childrenController.text) ?? 0;

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _profileFor = data['profileFor'] as String?;
    _nameController.text = (data['name'] as String?) ?? '';
    _gender = data['gender'] as String?;
    final dobStr = data['dateOfBirth'] as String?;
    if (dobStr != null) {
      _dob = DateTime.tryParse(dobStr);
      if (_dob != null) _dobController.text = _fmtDate(_dob!);
    }
    _height = data['height'] as String?;
    _weightController.text = (data['weight'] as String?) ?? '';
    _maritalStatus = data['maritalStatus'] as String?;
    _physicalStatus = data['physicalStatus'] as String?;
    _childrenLivingStatus = data['childrenLivingStatus'] as String?;
    final count = data['childrenCount'];
    if (count is int && count > 0) _childrenController.text = '$count';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _weightController.dispose();
    _childrenController.dispose();
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
        _dobController.text = _fmtDate(date);
      });
    }
  }

  void _saveAndNext() {
    if (!_formKey.currentState!.validate()) return;
    if (_profileFor == null || _profileFor!.isEmpty) {
      return _snack('Please select who this profile is for');
    }
    if (_gender == null) return _snack('Please select a gender');
    if (_dob == null) return _snack('Please select your date of birth');
    if (_height == null || _height!.isEmpty) {
      return _snack('Please select your height');
    }
    if (_maritalStatus == null || _maritalStatus!.isEmpty) {
      return _snack('Please select your marital status');
    }
    if (_physicalStatus == null || _physicalStatus!.isEmpty) {
      return _snack('Please select your physical status');
    }
    // Living status is required only when there actually are children.
    if (_showChildren &&
        _childrenCount > 0 &&
        (_childrenLivingStatus == null || _childrenLivingStatus!.isEmpty)) {
      return _snack('Please select the children living status');
    }

    ref.read(profileCreationProvider.notifier).updateData({
      'profileFor': _profileFor,
      'name': _nameController.text.trim(),
      'gender': _gender,
      'dateOfBirth': _dob!.toIso8601String(),
      'age': _age ?? 0,
      'height': _height,
      'weight': _weightController.text.trim(),
      'maritalStatus': _maritalStatus,
      'physicalStatus': _physicalStatus,
      'childrenCount': _showChildren ? _childrenCount : 0,
      'childrenLivingStatus':
          _showChildren && _childrenCount > 0 ? _childrenLivingStatus : null,
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
            Text('Basic Details', style: AppTextStyles.heading2),
            const SizedBox(height: 8),
            const Text('Let’s start with the essentials.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            SearchableField(
              label: 'Profile Created For',
              isRequired: true,
              items: _profileForOptions,
              selectedItem: _profileFor,
              prefixIcon: Icons.person_pin_outlined,
              onChanged: (v) => setState(() => _profileFor = v),
            ),
            const SizedBox(height: 16),
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
              hint: 'DD-MM-YYYY',
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
                  color: AppColors.primary.withValues(alpha: 0.06),
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
            const SizedBox(height: 20),
            SearchableField(
              label: 'Height',
              isRequired: true,
              items: AppConstants.heightList,
              selectedItem: _height,
              prefixIcon: Icons.height,
              onChanged: (v) => setState(() => _height = v),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _weightController,
              label: 'Weight (kg)',
              hint: 'Optional',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Marital Status',
              isRequired: true,
              items: AppConstants.maritalStatusOptions,
              selectedItem: _maritalStatus,
              prefixIcon: Icons.favorite_border,
              onChanged: (v) => setState(() => _maritalStatus = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Physical Status',
              isRequired: true,
              items: AppConstants.physicalStatusList,
              selectedItem: _physicalStatus,
              prefixIcon: Icons.accessibility_new,
              onChanged: (v) => setState(() => _physicalStatus = v),
            ),
            if (_showChildren) ...[
              const SizedBox(height: 16),
              AppTextField(
                controller: _childrenController,
                label: 'Number of Children',
                hint: '0',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                onChanged: (_) => setState(() {}),
              ),
              if (_childrenCount > 0) ...[
                const SizedBox(height: 16),
                SearchableField(
                  label: 'Children Living Status',
                  isRequired: true,
                  items: AppConstants.childrenLivingStatusList,
                  selectedItem: _childrenLivingStatus,
                  prefixIcon: Icons.home_outlined,
                  onChanged: (v) => setState(() => _childrenLivingStatus = v),
                ),
              ],
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

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}
