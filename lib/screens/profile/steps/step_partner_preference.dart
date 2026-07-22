import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/dual_range_slider_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_multi_select_field.dart';
import '../../../widgets/common/searchable_with_others_field.dart';

/// Partner Preference step. Every field is OPTIONAL. The field set mirrors the
/// website's "Partner Preferences" step exactly: age & height range, preferred
/// education / occupation, religion / caste / sub-caste, income, marital
/// status, mother tongue, physical status, chevvai dosham and the
/// "horoscope match required" toggle. Tapping the button advances to Review.
///
/// Age and Height are **dual range sliders** (spec §9–§11) — there is no wheel
/// picker and no separate Minimum/Maximum dropdown pair any more.
class StepPartnerPreference extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepPartnerPreference({super.key, required this.onNext});

  @override
  ConsumerState<StepPartnerPreference> createState() =>
      _StepPartnerPreferenceState();
}

class _StepPartnerPreferenceState
    extends ConsumerState<StepPartnerPreference> {
  static const int _minAgeBound = 18;
  static const int _maxAgeBound = 60;

  int _minAge = 21;
  int _maxAge = 35;

  /// Height is kept as an INDEX into [AppConstants.heightList] so the same
  /// range slider can drive it; it is converted back to `5'6"` on save.
  int _minHeightIdx = 0;
  int _maxHeightIdx = AppConstants.heightList.length - 1;

  List<String> _education = [];
  List<String> _occupation = [];
  String? _religion;
  String? _caste;
  final _subCasteController = TextEditingController();
  String? _income;
  String? _maritalStatus;
  String? _motherTongue;
  String? _physicalStatus;
  String? _chevvai;
  bool _horoscopeMatchRequired = true;

  List<String> get _heights => AppConstants.heightList;

  @override
  void initState() {
    super.initState();
    final pref = ref.read(profileCreationProvider).data['partnerPreferences'];
    if (pref is Map) {
      final minA = (pref['minAge'] as num?)?.toInt() ?? 21;
      final maxA = (pref['maxAge'] as num?)?.toInt() ?? 35;
      _minAge = minA.clamp(_minAgeBound, _maxAgeBound);
      _maxAge = maxA.clamp(_minAgeBound, _maxAgeBound);
      if (_minAge > _maxAge) _maxAge = _minAge;
      _minHeightIdx = _heightIndex(pref['minHeight'] as String?, 0);
      _maxHeightIdx =
          _heightIndex(pref['maxHeight'] as String?, _heights.length - 1);
      if (_minHeightIdx > _maxHeightIdx) _maxHeightIdx = _minHeightIdx;
      final edu = pref['education'];
      if (edu is List) _education = edu.map((e) => e.toString()).toList();
      final occ = pref['occupation'];
      if (occ is List) _occupation = occ.map((e) => e.toString()).toList();
      _religion = _orNull(pref['religion'] as String?);
      _caste = _orNull(pref['caste'] as String?);
      _subCasteController.text = _orNull(pref['subCaste'] as String?) ?? '';
      _income = _orNull(pref['income'] as String?);
      _maritalStatus = _orNull(pref['maritalStatus'] as String?);
      _motherTongue = _orNull(pref['motherTongue'] as String?);
      _physicalStatus = _orNull(pref['physicalStatus'] as String?);
      _chevvai = _orNull(pref['chevvaiDosham'] as String?);
      _horoscopeMatchRequired = pref['horoscopeMatchRequired'] as bool? ?? true;
    }
  }

  @override
  void dispose() {
    _subCasteController.dispose();
    super.dispose();
  }

  /// Stored 'Any' (or empty) means "no preference" → nothing selected.
  String? _orNull(String? v) =>
      (v == null || v.isEmpty || v == 'Any') ? null : v;

  /// 'Any' / null / empty → 'Any' (no preference).
  String _orAny(String? v) => (v == null || v.trim().isEmpty) ? 'Any' : v.trim();

  int _heightIndex(String? value, int fallback) {
    final i = _heights.indexOf(value ?? '');
    return i >= 0 ? i : fallback;
  }

  void _saveAndNext() {
    ref.read(profileCreationProvider.notifier).updateData({
      'partnerPreferences': {
        'minAge': _minAge,
        'maxAge': _maxAge,
        'minHeight': _heights[_minHeightIdx],
        'maxHeight': _heights[_maxHeightIdx],
        'education': _education,
        'occupation': _occupation,
        'religion': _orAny(_religion),
        'caste': _orAny(_caste),
        'subCaste': _subCasteController.text.trim(),
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
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.partnerPreferenceTitle, style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(l10n.partnerPrefSubtitle,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          _sectionTitle(l10n.basicPreference),
          // ── Age — dual range slider ──
          DualRangeSliderField(
            label: l10n.ageRangeLabel,
            min: _minAgeBound,
            max: _maxAgeBound,
            startValue: _minAge,
            endValue: _maxAge,
            startCaption: l10n.minimumAge,
            endCaption: l10n.maximumAge,
            formatRange: (lo, hi) => l10n.ageRangeValue(lo, hi),
            onChanged: (lo, hi) => setState(() {
              _minAge = lo;
              _maxAge = hi;
            }),
          ),
          const SizedBox(height: 16),
          // ── Height — dual range slider over the height list ──
          DualRangeSliderField(
            label: l10n.heightRangeLabel,
            min: 0,
            max: _heights.length - 1,
            startValue: _minHeightIdx,
            endValue: _maxHeightIdx,
            startCaption: l10n.minimumHeight,
            endCaption: l10n.maximumHeight,
            formatValue: (i) => _heights[i.clamp(0, _heights.length - 1)],
            formatRange: (lo, hi) => l10n.rangeValue(_heights[lo], _heights[hi]),
            onChanged: (lo, hi) => setState(() {
              _minHeightIdx = lo;
              _maxHeightIdx = hi;
            }),
          ),
          const SizedBox(height: 16),
          _pref(l10n.maritalStatus, AppConstants.maritalStatusOptions,
              _maritalStatus, (v) => _maritalStatus = v),
          _pref(l10n.physicalStatus, AppConstants.physicalStatusList,
              _physicalStatus, (v) => _physicalStatus = v),

          _sectionTitle(l10n.communityPreference),
          _pref(l10n.religion, AppConstants.religionList, _religion,
              (v) => _religion = v),
          _pref(l10n.caste, AppConstants.castList, _caste, (v) => _caste = v),
          // Sub Caste stays free text here — there is no cascaded master list
          // at preference level.
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppTextField(
              controller: _subCasteController,
              label: l10n.subCaste,
              hint: l10n.optional,
            ),
          ),
          _pref(l10n.motherTongue, AppConstants.motherTongueList, _motherTongue,
              (v) => _motherTongue = v),
          // Items stay canonical English — only the DISPLAY is localized.
          _pref(l10n.chevvaiDosham, const ['Yes', 'No', "Doesn't Matter"],
              _chevvai, (v) => _chevvai = v),

          _sectionTitle(l10n.educationIncomePreference),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SearchableMultiSelectField(
              label: l10n.education,
              items: AppConstants.educations,
              selected: _education,
              onChanged: (v) => setState(() => _education = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SearchableMultiSelectField(
              label: l10n.occupation,
              items: AppConstants.occupations,
              selected: _occupation,
              onChanged: (v) => setState(() => _occupation = v),
            ),
          ),
          _pref(l10n.annualIncome, AppConstants.incomeRanges, _income,
              (v) => _income = v),

          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _horoscopeMatchRequired,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() => _horoscopeMatchRequired = v),
            title: Text(l10n.horoscopeMatchRequired,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),

          const SizedBox(height: 20),
          GradientButton(onPressed: _saveAndNext, text: l10n.continueLabel),
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

  /// Every preference dropdown offers "Others" → custom textbox, exactly like
  /// the mandatory profile fields.
  Widget _pref(String label, List<String> items, String? value,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SearchableWithOthersField(
        label: label,
        items: items,
        value: value,
        onChanged: (v) => setState(() => onChanged(v)),
      ),
    );
  }
}
