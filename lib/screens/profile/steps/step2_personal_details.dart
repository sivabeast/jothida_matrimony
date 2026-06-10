import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/data/selection_data.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';

class Step2PersonalDetails extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const Step2PersonalDetails({super.key, required this.onNext});

  @override
  ConsumerState<Step2PersonalDetails> createState() => _Step2State();
}

class _Step2State extends ConsumerState<Step2PersonalDetails> {
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _weightController = TextEditingController();
  final _aboutController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Dependent / searchable selections
  String? _height;
  String? _religion;
  String? _caste;
  String? _subCaste;
  String? _motherTongue;
  String? _maritalStatus;
  String? _education;
  String? _occupation;
  String? _annualIncome;
  String? _country = 'India';
  String? _state;
  String? _city;
  DateTime? _dob;

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _weightController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(1995),
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
    if (_dob == null ||
        _religion == null ||
        _maritalStatus == null ||
        _education == null ||
        _occupation == null ||
        _country == null ||
        _city == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all required fields')));
      return;
    }
    final now = DateTime.now();
    var age = now.year - _dob!.year;
    if (now.month < _dob!.month ||
        (now.month == _dob!.month && now.day < _dob!.day)) {
      age--;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'name': _nameController.text.trim(),
      'dateOfBirth': _dob!.toIso8601String(),
      'age': age,
      'height': _height ?? '',
      'weight': _weightController.text.trim(),
      'religion': _religion,
      'caste': _caste ?? '',
      'subCaste': _subCaste ?? '',
      'motherTongue': _motherTongue ?? 'Tamil',
      'maritalStatus': _maritalStatus,
      'education': _education,
      'occupation': _occupation,
      'annualIncome': _annualIncome ?? '',
      'country': _country,
      'state': _state ?? '',
      'city': _city,
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
            SearchableField(
              label: 'Height',
              items: AppConstants.heightList,
              selectedItem: _height,
              prefixIcon: Icons.height,
              onChanged: (v) => setState(() => _height = v),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _weightController,
              label: 'Weight (kg)',
              hint: '60',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
            ),
            const SizedBox(height: 16),
            // ── Religion → Caste → Sub-caste (dependent) ──
            SearchableField(
              label: 'Religion',
              isRequired: true,
              items: AppConstants.religions,
              selectedItem: _religion,
              prefixIcon: Icons.spa_outlined,
              onChanged: (v) => setState(() {
                _religion = v;
                _caste = null; // reset dependents
                _subCaste = null;
              }),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Caste',
              items: SelectionData.castesFor(_religion),
              selectedItem: _caste,
              enabled: _religion != null,
              onChanged: (v) => setState(() {
                _caste = v;
                _subCaste = null;
              }),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Sub Caste',
              items: SelectionData.subCastesFor(_caste),
              selectedItem: _subCaste,
              enabled: _caste != null,
              onChanged: (v) => setState(() => _subCaste = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Mother Tongue',
              items: AppConstants.motherTongueList,
              selectedItem: _motherTongue,
              onChanged: (v) => setState(() => _motherTongue = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Marital Status',
              isRequired: true,
              items: AppConstants.maritalStatuses,
              selectedItem: _maritalStatus,
              onChanged: (v) => setState(() => _maritalStatus = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Education',
              isRequired: true,
              items: AppConstants.educations,
              selectedItem: _education,
              prefixIcon: Icons.school_outlined,
              onChanged: (v) => setState(() => _education = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Occupation',
              isRequired: true,
              items: AppConstants.occupations,
              selectedItem: _occupation,
              prefixIcon: Icons.work_outline,
              onChanged: (v) => setState(() => _occupation = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Annual Income',
              items: AppConstants.incomeRanges,
              selectedItem: _annualIncome,
              onChanged: (v) => setState(() => _annualIncome = v),
            ),
            const SizedBox(height: 16),
            // ── Country → State → City (dependent) ──
            SearchableField(
              label: 'Country',
              isRequired: true,
              items: SelectionData.countries,
              selectedItem: _country,
              prefixIcon: Icons.public,
              onChanged: (v) => setState(() {
                _country = v;
                _state = null;
                _city = null;
              }),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'State',
              items: _country == 'India'
                  ? SelectionData.indianStates
                  : const ['Other'],
              selectedItem: _state,
              onChanged: (v) => setState(() {
                _state = v;
                _city = null;
              }),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'City',
              isRequired: true,
              items: SelectionData.citiesFor(_state),
              selectedItem: _city,
              enabled: _state != null,
              prefixIcon: Icons.location_city,
              onChanged: (v) => setState(() => _city = v),
            ),
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
}
