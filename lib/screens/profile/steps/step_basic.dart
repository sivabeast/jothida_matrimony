import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/inline_validation.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/value_l10n.dart';
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
  final _v = InlineValidation();
  final _nameController = TextEditingController();
  final _nameTamilController = TextEditingController();
  final _dobController = TextEditingController();
  final _weightController = TextEditingController();
  final _childrenController = TextEditingController();
  final _nameFocus = FocusNode();
  final _nameTamilFocus = FocusNode();

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
  String? _familyType;
  String? _familyStatus;

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
    _nameTamilController.text = (data['nameTamil'] as String?) ?? '';
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
    // Family Type / Family Status live inside the familyDetails map (kept in
    // sync with the Edit Profile → Family section).
    final fam = data['familyDetails'];
    if (fam is Map) {
      final t = (fam['familyType'] as String?)?.trim() ?? '';
      final s = (fam['familyStatus'] as String?)?.trim() ?? '';
      if (t.isNotEmpty) _familyType = t;
      if (s.isNotEmpty) _familyStatus = s;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameTamilController.dispose();
    _dobController.dispose();
    _weightController.dispose();
    _childrenController.dispose();
    _nameFocus.dispose();
    _nameTamilFocus.dispose();
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
    final l10n = context.l10n;
    // One consistent validation style (§10): an inline red message under each
    // invalid field, and the page scrolls to + focuses the FIRST of them.
    // BOTH names are mandatory (§14).
    final nameError = Validators.name(_nameController.text);
    final checks = <FieldCheck>[
      FieldCheck.notEmpty('profileFor', _profileFor,
          l10n.pleaseSelect(l10n.profileCreatedFor)),
      FieldCheck(
        id: 'name',
        valid: nameError == null,
        message: nameError ?? l10n.pleaseEnterField(l10n.fullName),
        focusNode: _nameFocus,
      ),
      FieldCheck.notEmpty('nameTamil', _nameTamilController.text,
          l10n.pleaseEnterField('${l10n.fullName} (தமிழ்)'),
          focusNode: _nameTamilFocus),
      FieldCheck(
          id: 'gender',
          valid: _gender != null,
          message: l10n.pleaseSelect(l10n.gender)),
      FieldCheck(
          id: 'dob',
          valid: _dob != null,
          message: l10n.pleaseSelect(l10n.dateOfBirth)),
      FieldCheck.notEmpty('height', _height, l10n.pleaseSelect(l10n.height)),
      FieldCheck.notEmpty('maritalStatus', _maritalStatus,
          l10n.pleaseSelect(l10n.maritalStatus)),
      FieldCheck.notEmpty('physicalStatus', _physicalStatus,
          l10n.pleaseSelect(l10n.physicalStatus)),
      FieldCheck.notEmpty(
          'familyType', _familyType, l10n.pleaseSelect(l10n.familyType)),
      FieldCheck.notEmpty(
          'familyStatus', _familyStatus, l10n.pleaseSelect(l10n.familyStatus)),
      // Living status is required only when there actually are children.
      if (_showChildren && _childrenCount > 0)
        FieldCheck.notEmpty('childrenLivingStatus', _childrenLivingStatus,
            l10n.pleaseSelect(l10n.childrenLivingStatus)),
    ];
    if (!_v.validate(context, checks, onChanged: () => setState(() {}))) return;

    // Merge into the existing familyDetails map so an edit never wipes the
    // other family fields (father/mother details, siblings…).
    final existingFam = ref.read(profileCreationProvider).data['familyDetails'];
    final fam = existingFam is Map
        ? Map<String, dynamic>.from(existingFam)
        : <String, dynamic>{};
    fam['familyType'] = _familyType;
    fam['familyStatus'] = _familyStatus;

    ref.read(profileCreationProvider.notifier).updateData({
      'familyDetails': fam,
      'profileFor': _profileFor,
      'name': _nameController.text.trim(),
      'nameTamil': _nameTamilController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.basicDetails, style: AppTextStyles.heading2),
            const SizedBox(height: 8),
            Text(context.l10n.letsStartEssentials,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            SearchableField(
              key: _v.anchor('profileFor'),
              label: context.l10n.profileCreatedFor,
              isRequired: true,
              items: _profileForOptions,
              selectedItem: _profileFor,
              prefixIcon: Icons.person_pin_outlined,
              errorText: _v.errorOf('profileFor'),
              onChanged: (v) => setState(() {
                _profileFor = v;
                _v.clear('profileFor');
              }),
            ),
            const SizedBox(height: 16),
            AppTextField(
              key: _v.anchor('name'),
              controller: _nameController,
              focusNode: _nameFocus,
              label: '${context.l10n.fullName} *',
              errorText: _v.errorOf('name'),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) {
                if (_v.errorOf('name') != null) {
                  setState(() => _v.clear('name'));
                }
              },
            ),
            const SizedBox(height: 16),
            // Tamil-script name (§10) — required, mirroring the website's Basic
            // step (which validates fullNameTamil). Shown in place of the
            // English name in Tamil mode; the English name stays canonical.
            AppTextField(
              key: _v.anchor('nameTamil'),
              controller: _nameTamilController,
              focusNode: _nameTamilFocus,
              label: '${context.l10n.fullName} (தமிழ்) *',
              errorText: _v.errorOf('nameTamil'),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) {
                if (_v.errorOf('nameTamil') != null) {
                  setState(() => _v.clear('nameTamil'));
                }
              },
            ),
            const SizedBox(height: 20),
            Text('${context.l10n.gender} *',
                key: _v.anchor('gender'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _genderCard('Male', Icons.male)),
                const SizedBox(width: 16),
                Expanded(child: _genderCard('Female', Icons.female)),
              ],
            ),
            InlineFieldError(_v.errorOf('gender')),
            const SizedBox(height: 20),
            AppTextField(
              key: _v.anchor('dob'),
              controller: _dobController,
              label: '${context.l10n.dateOfBirth} *',
              hint: 'DD-MM-YYYY',
              readOnly: true,
              onTap: _pickDate,
              suffixIcon: const Icon(Icons.calendar_today),
              errorText: _v.errorOf('dob'),
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
                    Expanded(
                      child: Text(context.l10n.ageYears(_age!),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SearchableField(
              key: _v.anchor('height'),
              label: context.l10n.height,
              isRequired: true,
              items: AppConstants.heightList,
              selectedItem: _height,
              prefixIcon: Icons.height,
              errorText: _v.errorOf('height'),
              onChanged: (v) => setState(() {
                _height = v;
                _v.clear('height');
              }),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _weightController,
              label: context.l10n.weightKg,
              hint: context.l10n.optional,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
            ),
            const SizedBox(height: 16),
            SearchableField(
              key: _v.anchor('maritalStatus'),
              label: context.l10n.maritalStatus,
              isRequired: true,
              items: AppConstants.maritalStatusOptions,
              selectedItem: _maritalStatus,
              prefixIcon: Icons.favorite_border,
              errorText: _v.errorOf('maritalStatus'),
              onChanged: (v) => setState(() {
                _maritalStatus = v;
                _v.clear('maritalStatus');
              }),
            ),
            const SizedBox(height: 16),
            SearchableField(
              key: _v.anchor('physicalStatus'),
              label: context.l10n.physicalStatus,
              isRequired: true,
              items: AppConstants.physicalStatusList,
              selectedItem: _physicalStatus,
              prefixIcon: Icons.accessibility_new,
              errorText: _v.errorOf('physicalStatus'),
              onChanged: (v) => setState(() {
                _physicalStatus = v;
                _v.clear('physicalStatus');
              }),
            ),
            const SizedBox(height: 16),
            SearchableField(
              key: _v.anchor('familyType'),
              label: context.l10n.familyType,
              isRequired: true,
              items: AppConstants.familyTypeList,
              selectedItem: _familyType,
              prefixIcon: Icons.family_restroom,
              errorText: _v.errorOf('familyType'),
              onChanged: (v) => setState(() {
                _familyType = v;
                _v.clear('familyType');
              }),
            ),
            const SizedBox(height: 16),
            SearchableField(
              key: _v.anchor('familyStatus'),
              label: context.l10n.familyStatus,
              isRequired: true,
              items: AppConstants.familyStatusList,
              selectedItem: _familyStatus,
              prefixIcon: Icons.diamond_outlined,
              errorText: _v.errorOf('familyStatus'),
              onChanged: (v) => setState(() {
                _familyStatus = v;
                _v.clear('familyStatus');
              }),
            ),
            if (_showChildren) ...[
              const SizedBox(height: 16),
              AppTextField(
                controller: _childrenController,
                label: context.l10n.numberOfChildren,
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
                  key: _v.anchor('childrenLivingStatus'),
                  label: context.l10n.childrenLivingStatus,
                  isRequired: true,
                  items: AppConstants.childrenLivingStatusList,
                  selectedItem: _childrenLivingStatus,
                  prefixIcon: Icons.home_outlined,
                  errorText: _v.errorOf('childrenLivingStatus'),
                  onChanged: (v) => setState(() {
                    _childrenLivingStatus = v;
                    _v.clear('childrenLivingStatus');
                  }),
                ),
              ],
            ],
            const SizedBox(height: 36),
            GradientButton(
                onPressed: _saveAndNext, text: context.l10n.continueLabel),
          ],
        ),
      ),
    );
  }

  Widget _genderCard(String gender, IconData icon) {
    final selected = _gender == gender;
    return GestureDetector(
      onTap: () => setState(() {
        _gender = gender;
        _v.clear('gender');
      }),
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
            Text(context.localizeValue(gender),
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
