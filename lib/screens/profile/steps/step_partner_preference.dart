import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';

/// Step 11 — Partner Preference. Every field is OPTIONAL. Tapping the button
/// triggers profile submission (the wizard treats this as the final step).
class StepPartnerPreference extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final bool isLoading;
  const StepPartnerPreference({
    super.key,
    required this.onNext,
    this.isLoading = false,
  });

  @override
  ConsumerState<StepPartnerPreference> createState() =>
      _StepPartnerPreferenceState();
}

class _StepPartnerPreferenceState
    extends ConsumerState<StepPartnerPreference> {
  RangeValues _age = const RangeValues(21, 35);
  String? _minHeight;
  String? _maxHeight;
  String? _maritalStatus;
  String? _physicalStatus;
  String? _religion;
  String? _caste;
  String? _star;
  String? _raasi;
  String? _chevvai;
  String? _education;
  String? _occupation;
  String? _employmentType;
  String? _income;
  String? _country;
  String? _state;
  String? _eating;
  String? _smoking;
  String? _drinking;
  final _subCaste = TextEditingController();
  final _city = TextEditingController();

  @override
  void initState() {
    super.initState();
    final pref =
        ref.read(profileCreationProvider).data['partnerPreferences'];
    if (pref is Map) {
      final minA = (pref['minAge'] as num?)?.toDouble() ?? 21;
      final maxA = (pref['maxAge'] as num?)?.toDouble() ?? 35;
      _age = RangeValues(minA.clamp(18, 60), maxA.clamp(18, 60));
      _minHeight = pref['minHeight'] as String?;
      _maxHeight = pref['maxHeight'] as String?;
      _maritalStatus = pref['maritalStatus'] as String?;
      _physicalStatus = pref['physicalStatus'] as String?;
      _religion = pref['religion'] as String?;
      _caste = pref['caste'] as String?;
      _star = pref['nakshatra'] as String?;
      _raasi = pref['rasi'] as String?;
      _chevvai = pref['chevvaiDosham'] as String?;
      _employmentType = pref['employmentType'] as String?;
      _income = pref['income'] as String?;
      _country = pref['country'] as String?;
      _state = pref['state'] as String?;
      _eating = pref['eatingHabit'] as String?;
      _smoking = pref['smokingHabit'] as String?;
      _drinking = pref['drinkingHabit'] as String?;
      _subCaste.text = (pref['subCaste'] as String?) ?? '';
      _city.text = (pref['city'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    _subCaste.dispose();
    _city.dispose();
    super.dispose();
  }

  /// 'Any' / null / empty → omit (no preference).
  String _orAny(String? v) => (v == null || v.isEmpty) ? 'Any' : v;

  void _saveAndFinish() {
    ref.read(profileCreationProvider.notifier).updateData({
      'partnerPreferences': {
        'minAge': _age.start.round(),
        'maxAge': _age.end.round(),
        'minHeight': _minHeight ?? "5'0\"",
        'maxHeight': _maxHeight ?? "6'0\"",
        'maritalStatus': _orAny(_maritalStatus),
        'physicalStatus': _orAny(_physicalStatus),
        'religion': _orAny(_religion),
        'caste': _orAny(_caste),
        'subCaste': _subCaste.text.trim(),
        'nakshatra': _orAny(_star),
        'rasi': _orAny(_raasi),
        'chevvaiDosham': _orAny(_chevvai),
        'education': _orAny(_education),
        'occupation': _orAny(_occupation),
        'employmentType': _orAny(_employmentType),
        'income': _orAny(_income),
        'country': _orAny(_country),
        'state': _orAny(_state),
        'city': _city.text.trim(),
        'eatingHabit': _orAny(_eating),
        'smokingHabit': _orAny(_smoking),
        'drinkingHabit': _orAny(_drinking),
      },
    });
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Partner Preference', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text(
              'All optional — set what matters, skip the rest. You can refine '
              'these anytime.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          _sectionTitle('Basic Preference'),
          Text('Age: ${_age.start.round()} – ${_age.end.round()} yrs',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          RangeSlider(
            values: _age,
            min: 18,
            max: 60,
            divisions: 42,
            activeColor: AppColors.primary,
            labels: RangeLabels(
                '${_age.start.round()}', '${_age.end.round()}'),
            onChanged: (v) => setState(() => _age = v),
          ),
          _pref('Min Height', AppConstants.heightList, _minHeight,
              (v) => _minHeight = v),
          _pref('Max Height', AppConstants.heightList, _maxHeight,
              (v) => _maxHeight = v),
          _pref('Marital Status', AppConstants.maritalStatusOptions,
              _maritalStatus, (v) => _maritalStatus = v),
          _pref('Physical Status', AppConstants.physicalStatusList,
              _physicalStatus, (v) => _physicalStatus = v),

          _sectionTitle('Religious Preference'),
          _pref('Religion', AppConstants.religionList, _religion,
              (v) => _religion = v),
          _pref('Caste', AppConstants.castList, _caste, (v) => _caste = v),
          AppTextField(
              controller: _subCaste, label: 'Sub Caste', hint: 'Optional'),
          const SizedBox(height: 16),
          _pref('Star (Nakshatra)', AppConstants.nakshatraList, _star,
              (v) => _star = v),
          _pref('Raasi', AppConstants.rasiEnList, _raasi, (v) => _raasi = v),
          _pref('Chevvai Dosham', const ['Yes', 'No', 'Doesn\'t Matter'],
              _chevvai, (v) => _chevvai = v),

          _sectionTitle('Education Preference'),
          _pref('Education', AppConstants.educations, _education,
              (v) => _education = v),
          _pref('Occupation', AppConstants.occupations, _occupation,
              (v) => _occupation = v),
          _pref('Employment Type', AppConstants.employmentTypeList,
              _employmentType, (v) => _employmentType = v),
          _pref('Annual Income', AppConstants.incomeRanges, _income,
              (v) => _income = v),

          _sectionTitle('Location Preference'),
          _pref('Country', AppConstants.countryList, _country,
              (v) => _country = v),
          _pref('State', AppConstants.indianStates, _state, (v) => _state = v),
          AppTextField(controller: _city, label: 'City', hint: 'Optional'),
          const SizedBox(height: 16),

          _sectionTitle('Lifestyle Preference'),
          _pref('Eating Habit', AppConstants.eatingHabitList, _eating,
              (v) => _eating = v),
          _pref('Smoking Habit', AppConstants.smokingHabitList, _smoking,
              (v) => _smoking = v),
          _pref('Drinking Habit', AppConstants.drinkingHabitList, _drinking,
              (v) => _drinking = v),

          const SizedBox(height: 28),
          GradientButton(
            onPressed: widget.isLoading ? null : _saveAndFinish,
            text: widget.isLoading ? 'Creating Profile…' : 'Create Profile',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(t,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
      );

  Widget _pref(String label, List<String> items, String? value,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SearchableField(
        label: label,
        items: items,
        selectedItem: value,
        onChanged: (v) => setState(() => onChanged(v)),
      ),
    );
  }
}
