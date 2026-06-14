import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/religion_caste_fields.dart';
import '../../../widgets/common/searchable_field.dart';
import '../../../widgets/common/location_picker_section.dart';

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
  String? _religionId;
  String? _caste;
  String? _casteId;
  String? _subCaste;
  String? _subCasteId;
  String? _motherTongue;
  String? _maritalStatus;
  String? _education;
  String? _occupation;
  String? _annualIncome;
  String? _country = 'India';
  String? _state;
  String? _stateId;
  String? _district;
  String? _districtId;
  String? _city;
  String? _cityId;
  double? _lat;
  double? _lng;
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
      'religionId': _religionId,
      'caste': _caste ?? '',
      'casteId': _casteId,
      'subCaste': _subCaste ?? '',
      'subCasteId': _subCasteId,
      'motherTongue': _motherTongue ?? 'Tamil',
      'maritalStatus': _maritalStatus,
      'education': _education,
      'occupation': _occupation,
      'annualIncome': _annualIncome ?? '',
      'country': _country,
      'state': _state ?? '',
      'stateId': _stateId ?? '',
      'stateName': _state ?? '',
      'district': _district ?? '',
      'districtId': _districtId ?? '',
      'districtName': _district ?? '',
      'city': _city,
      'cityId': _cityId ?? '',
      'cityName': _city ?? '',
      'latitude': _lat,
      'longitude': _lng,
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
            // ── Religion → Caste → Sub-caste (Firestore master data) ──
            ReligionCasteFields(
              religionId: _religionId,
              religionName: _religion,
              casteId: _casteId,
              casteName: _caste,
              subCasteId: _subCasteId,
              subCasteName: _subCaste,
              onReligionChanged: (id, name) => setState(() {
                _religionId = id;
                _religion = name;
                _casteId = null;
                _caste = null;
                _subCasteId = null;
                _subCaste = null;
              }),
              onCasteChanged: (id, name) => setState(() {
                _casteId = id;
                _caste = name;
                _subCasteId = null;
                _subCaste = null;
              }),
              onSubcasteChanged: (id, name) => setState(() {
                _subCasteId = id;
                _subCaste = name;
              }),
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
            // ── Country → State → District → City (bundled JSON master data) +
            // a "📍 Use My Location" button that GPS-detects and auto-fills. ──
            LocationPickerSection(
              initialCountry: _country,
              initialState: _state,
              initialDistrict: _district,
              initialCity: _city,
              initialLatitude: _lat,
              initialLongitude: _lng,
              onChanged: (loc) => setState(() {
                _country = loc.country.isEmpty ? 'India' : loc.country;
                _state = loc.state.isEmpty ? null : loc.state;
                _stateId = loc.stateId.isEmpty ? null : loc.stateId;
                _district = loc.district.isEmpty ? null : loc.district;
                _districtId = loc.districtId.isEmpty ? null : loc.districtId;
                _city = loc.city.isEmpty ? null : loc.city;
                _cityId = loc.cityId.isEmpty ? null : loc.cityId;
                _lat = loc.latitude;
                _lng = loc.longitude;
              }),
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
