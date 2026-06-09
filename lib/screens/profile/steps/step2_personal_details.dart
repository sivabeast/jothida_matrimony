import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';

class Step2PersonalDetails extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const Step2PersonalDetails({super.key, required this.onNext});

  @override
  ConsumerState<Step2PersonalDetails> createState() => _Step2State();
}

class _Step2State extends ConsumerState<Step2PersonalDetails> {
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _heightController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _aboutController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _religion;
  String? _caste;
  String? _maritalStatus;
  String? _education;
  String? _occupation;
  String? _annualIncome;
  DateTime? _dob;

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _heightController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1960),
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
    if (_dob == null || _religion == null || _maritalStatus == null ||
        _education == null || _occupation == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please fill all required fields')));
      return;
    }
    final age = DateTime.now().year - _dob!.year;
    ref.read(profileCreationProvider.notifier).updateData({
      'name': _nameController.text.trim(),
      'dateOfBirth': _dob!.toIso8601String(),
      'age': age,
      'height': _heightController.text.trim(),
      'religion': _religion,
      'caste': _caste ?? '',
      'maritalStatus': _maritalStatus,
      'education': _education,
      'occupation': _occupation,
      'annualIncome': _annualIncome ?? '',
      'city': _cityController.text.trim(),
      'state': _stateController.text.trim(),
      'about': _aboutController.text.trim(),
    });
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: _nameController,
              label: 'Full Name *',
              validator: Validators.name,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _dobController,
              label: 'Date of Birth *',
              hint: 'DD/MM/YYYY',
              readOnly: true,
              onTap: _pickDate,
              suffixIcon: const Icon(Icons.calendar_today),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _heightController,
              label: 'Height (e.g. 5\'8")',
              hint: "5'6\"",
            ),
            const SizedBox(height: 16),
            _buildDropdown('Religion *', AppConstants.religions, _religion,
                (v) => setState(() => _religion = v)),
            const SizedBox(height: 16),
            _buildDropdown('Caste', AppConstants.castes, _caste,
                (v) => setState(() => _caste = v)),
            const SizedBox(height: 16),
            _buildDropdown('Marital Status *', AppConstants.maritalStatuses, _maritalStatus,
                (v) => setState(() => _maritalStatus = v)),
            const SizedBox(height: 16),
            _buildDropdown('Education *', AppConstants.educations, _education,
                (v) => setState(() => _education = v)),
            const SizedBox(height: 16),
            _buildDropdown('Occupation *', AppConstants.occupations, _occupation,
                (v) => setState(() => _occupation = v)),
            const SizedBox(height: 16),
            _buildDropdown('Annual Income', AppConstants.incomeRanges, _annualIncome,
                (v) => setState(() => _annualIncome = v)),
            const SizedBox(height: 16),
            AppTextField(controller: _cityController, label: 'City *',
                validator: (v) => v == null || v.isEmpty ? 'Required' : null),
            const SizedBox(height: 16),
            AppTextField(controller: _stateController, label: 'State'),
            const SizedBox(height: 16),
            AppTextField(
              controller: _aboutController,
              label: 'About Me',
              hint: 'Tell something about yourself...',
              maxLines: 3,
              validator: Validators.about,
            ),
            const SizedBox(height: 32),
            GradientButton(onPressed: _saveAndNext, text: 'Next'),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> items, String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      hint: Text(label),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
    );
  }
}
