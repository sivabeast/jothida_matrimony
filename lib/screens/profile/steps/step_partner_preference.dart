import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/age_range_wheel.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';
import '../../../widgets/common/searchable_multi_select_field.dart';

/// Partner Preference step. Every field is OPTIONAL. The field set mirrors the
/// website's "Partner Preferences" step exactly: age & height range, preferred
/// education / occupation, religion / caste / sub-caste, income, marital
/// status, mother tongue, physical status, chevvai dosham and the
/// "horoscope match required" toggle. Tapping the button advances to Review.
class StepPartnerPreference extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepPartnerPreference({super.key, required this.onNext});

  @override
  ConsumerState<StepPartnerPreference> createState() =>
      _StepPartnerPreferenceState();
}

class _StepPartnerPreferenceState
    extends ConsumerState<StepPartnerPreference> {
  int _minAge = 21;
  int _maxAge = 35;
  String? _minHeight;
  String? _maxHeight;
  List<String> _education = [];
  List<String> _occupation = [];
  String? _religion;
  String? _caste;
  String? _income;
  String? _maritalStatus;
  String? _motherTongue;
  String? _physicalStatus;
  String? _chevvai;
  bool _horoscopeMatchRequired = true;
  final _subCaste = TextEditingController();

  @override
  void initState() {
    super.initState();
    final pref = ref.read(profileCreationProvider).data['partnerPreferences'];
    if (pref is Map) {
      final minA = (pref['minAge'] as num?)?.toInt() ?? 21;
      final maxA = (pref['maxAge'] as num?)?.toInt() ?? 35;
      _minAge = minA.clamp(18, 60);
      _maxAge = maxA.clamp(18, 60);
      if (_minAge > _maxAge) _maxAge = _minAge;
      _minHeight = pref['minHeight'] as String?;
      _maxHeight = pref['maxHeight'] as String?;
      final edu = pref['education'];
      if (edu is List) _education = edu.map((e) => e.toString()).toList();
      final occ = pref['occupation'];
      if (occ is List) _occupation = occ.map((e) => e.toString()).toList();
      _religion = pref['religion'] as String?;
      _caste = pref['caste'] as String?;
      _income = pref['income'] as String?;
      _maritalStatus = pref['maritalStatus'] as String?;
      _motherTongue = pref['motherTongue'] as String?;
      _physicalStatus = pref['physicalStatus'] as String?;
      _chevvai = pref['chevvaiDosham'] as String?;
      _horoscopeMatchRequired = pref['horoscopeMatchRequired'] as bool? ?? true;
      _subCaste.text = (pref['subCaste'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    _subCaste.dispose();
    super.dispose();
  }

  /// 'Any' / null / empty → 'Any' (no preference).
  String _orAny(String? v) => (v == null || v.isEmpty) ? 'Any' : v;

  void _saveAndNext() {
    ref.read(profileCreationProvider.notifier).updateData({
      'partnerPreferences': {
        'minAge': _minAge,
        'maxAge': _maxAge,
        'minHeight': _minHeight ?? "5'0\"",
        'maxHeight': _maxHeight ?? "6'0\"",
        'education': _education,
        'occupation': _occupation,
        'religion': _orAny(_religion),
        'caste': _orAny(_caste),
        'subCaste': _subCaste.text.trim(),
        'income': _orAny(_income),
        'maritalStatus': _orAny(_maritalStatus),
        'motherTongue': _orAny(_motherTongue),
        'physicalStatus': _orAny(_physicalStatus),
        'chevvaiDosham': _orAny(_chevvai),
        'horoscopeMatchRequired': _horoscopeMatchRequired,
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
          const Text('Age', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          AgeRangeWheel(
            minAge: _minAge,
            maxAge: _maxAge,
            onChanged: (lo, hi) => setState(() {
              _minAge = lo;
              _maxAge = hi;
            }),
          ),
          const SizedBox(height: 8),
          _pref('Min Height', AppConstants.heightList, _minHeight,
              (v) => _minHeight = v),
          _pref('Max Height', AppConstants.heightList, _maxHeight,
              (v) => _maxHeight = v),
          _pref('Marital Status', AppConstants.maritalStatusOptions,
              _maritalStatus, (v) => _maritalStatus = v),
          _pref('Physical Status', AppConstants.physicalStatusList,
              _physicalStatus, (v) => _physicalStatus = v),

          _sectionTitle('Community Preference'),
          _pref('Religion', AppConstants.religionList, _religion,
              (v) => _religion = v),
          _pref('Caste', AppConstants.castList, _caste, (v) => _caste = v),
          AppTextField(
              controller: _subCaste, label: 'Sub Caste', hint: 'Optional'),
          const SizedBox(height: 16),
          _pref('Mother Tongue', AppConstants.motherTongueList, _motherTongue,
              (v) => _motherTongue = v),
          _pref('Chevvai Dosham', const ['Yes', 'No', 'Doesn\'t Matter'],
              _chevvai, (v) => _chevvai = v),

          _sectionTitle('Education & Income Preference'),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SearchableMultiSelectField(
              label: 'Education',
              items: AppConstants.educations,
              selected: _education,
              onChanged: (v) => setState(() => _education = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SearchableMultiSelectField(
              label: 'Occupation',
              items: AppConstants.occupations,
              selected: _occupation,
              onChanged: (v) => setState(() => _occupation = v),
            ),
          ),
          _pref('Annual Income', AppConstants.incomeRanges, _income,
              (v) => _income = v),

          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _horoscopeMatchRequired,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() => _horoscopeMatchRequired = v),
            title: const Text('Horoscope match required',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),

          const SizedBox(height: 20),
          GradientButton(onPressed: _saveAndNext, text: 'Continue'),
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
