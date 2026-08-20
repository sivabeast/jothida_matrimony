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
import '../../../widgets/common/number_stepper_field.dart';
import '../../../widgets/common/searchable_field.dart';

/// Step 1 — Basic Details: Profile For, Full Name (English required, Tamil
/// optional per §1), Gender, Date of Birth, Height, Weight, Marital Status,
/// Physical Status, and the children question.
///
/// Children are asked DIRECTLY (§2) — "உங்களுக்கு குழந்தைகள் உள்ளனவா?" — not
/// inferred from marital status. The old rule only offered the field to
/// divorced/widowed members, which both missed people who have children and
/// forced the question on people who do not.
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
  final _nameFocus = FocusNode();

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

  /// §2 — asked outright, independent of marital status. Null until answered,
  /// which is what makes the question required.
  bool? _hasChildren;

  /// Only meaningful while [_hasChildren] is true. Starts at 1 because that is
  /// the answer for anyone who just said "yes" (§2).
  int _childrenCount = 1;

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
    // Normalised so a profile saved with a legacy value ('Widow', 'Widower',
    // 'Awaiting Divorce') seeds the dropdown on the canonical option instead of
    // coming up blank when the wizard is reopened to edit it.
    _maritalStatus =
        AppConstants.normalizeMaritalStatus(data['maritalStatus'] as String?);
    _physicalStatus = data['physicalStatus'] as String?;
    _childrenLivingStatus = data['childrenLivingStatus'] as String?;
    // `hasChildren` is the new explicit answer; a draft written before it
    // existed is recovered from the count it already stored, so reopening an
    // old draft does not silently re-ask a question the member answered.
    final count = data['childrenCount'];
    final savedHas = data['hasChildren'];
    if (savedHas is bool) {
      _hasChildren = savedHas;
    } else if (count is int) {
      _hasChildren = count > 0;
    }
    if (count is int && count > 0) _childrenCount = count;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameTamilController.dispose();
    _dobController.dispose();
    _weightController.dispose();
    _nameFocus.dispose();
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
    // Only the ENGLISH name is mandatory — the Tamil one is optional (§1).
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
      // §2 — the yes/no answer itself is required…
      FieldCheck(
          id: 'hasChildren',
          valid: _hasChildren != null,
          message: l10n.pleaseSelect(l10n.haveChildren)),
      // …and the living status only matters once the answer is yes.
      if (_hasChildren == true)
        FieldCheck.notEmpty('childrenLivingStatus', _childrenLivingStatus,
            l10n.pleaseSelect(l10n.childrenLivingStatus)),
    ];
    if (!_v.validate(context, checks, onChanged: () => setState(() {}))) return;

    ref.read(profileCreationProvider.notifier).updateData({
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
      'hasChildren': _hasChildren ?? false,
      'childrenCount': _hasChildren == true ? _childrenCount : 0,
      'childrenLivingStatus':
          _hasChildren == true ? _childrenLivingStatus : null,
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
            // Tamil-script name — OPTIONAL (§1): no asterisk and no check, so
            // a member who cannot type Tamil is never blocked. When given it is
            // shown in place of the English name in Tamil mode; the English
            // name stays the canonical one.
            AppTextField(
              controller: _nameTamilController,
              label: '${context.l10n.fullName} (தமிழ்)',
              hint: context.l10n.optional,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),
            Text('${context.l10n.gender} *',
                key: _v.anchor('gender'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < AppConstants.genderList.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(
                    child: _genderCard(
                      AppConstants.genderList[i],
                      AppConstants.genderList[i] == 'Female'
                          ? Icons.female
                          : Icons.male,
                    ),
                  ),
                ],
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
              items: AppConstants.maritalStatusList,
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
            // ── §2 Children — asked directly, never inferred ───────────────
            const SizedBox(height: 20),
            Text('${context.l10n.haveChildren} *',
                key: _v.anchor('hasChildren'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _yesNoCard(true, context.l10n.yes)),
                const SizedBox(width: 16),
                Expanded(child: _yesNoCard(false, context.l10n.no)),
              ],
            ),
            InlineFieldError(_v.errorOf('hasChildren')),
            // "No" hides the count entirely (§2) — the stepper only exists
            // once there is something to count.
            if (_hasChildren == true) ...[
              const SizedBox(height: 16),
              NumberStepperField(
                label: context.l10n.numberOfChildren,
                value: _childrenCount,
                min: 1,
                max: 15,
                prefixIcon: Icons.child_care_outlined,
                onChanged: (v) => setState(() => _childrenCount = v),
              ),
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
            const SizedBox(height: 36),
            GradientButton(
                onPressed: _saveAndNext, text: context.l10n.continueLabel),
          ],
        ),
      ),
    );
  }

  /// One half of the ஆம் / இல்லை pair (§2). Styled like [_genderCard] so the
  /// two choice rows on this step read as the same control.
  Widget _yesNoCard(bool answer, String label) {
    final selected = _hasChildren == answer;
    return GestureDetector(
      onTap: () => setState(() {
        _hasChildren = answer;
        _v.clear('hasChildren');
        if (!answer) {
          // Answering "no" must not leave a stale count or living status
          // behind for the save to pick up.
          _childrenCount = 1;
          _childrenLivingStatus = null;
          _v.clear('childrenLivingStatus');
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(answer ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 20, color: selected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 8),
            Text(label,
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
