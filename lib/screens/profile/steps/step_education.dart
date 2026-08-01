import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/data/career_data.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/inline_validation.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';
import '../../../widgets/common/searchable_with_others_field.dart';

/// Career step — now a fully DEPENDENT hierarchy (§5–§7):
///
///   Education Level  →  Course / Degree
///   Employment Status →  Government / Private   →  Occupation
///                     →  Business / Profession  →  Occupation
///
/// Student / Job Seeker / Homemaker / Retired stop at the status: no sector and
/// no occupation field is shown for them (§6). Annual Income is OPTIONAL (§8).
///
/// Every leaf value is one of the website's `EDUCATION` / `OCCUPATION` strings,
/// so both platforms keep storing identical values. The dropdowns still end
/// with **"Others"**, which reveals a custom textbox; a typed value is kept only
/// on this profile.
///
/// Validation follows the app-wide rule (§10): pressing Continue paints an
/// inline red message under each empty required field and scrolls to + focuses
/// the FIRST of them — nothing is reported at the bottom of the page.
class StepEducation extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepEducation({super.key, required this.onNext});

  @override
  ConsumerState<StepEducation> createState() => _StepEducationState();
}

class _StepEducationState extends ConsumerState<StepEducation> {
  final _v = InlineValidation();

  String? _educationLevel;
  String? _education; // course / degree
  String? _employmentStatus;
  String? _sector; // Government | Private | Business | Profession
  String? _occupation;
  String? _annualIncome;
  final _courseDegree = TextEditingController();
  final _courseFocus = FocusNode();

  bool get _needsCourse => CareerData.levelHasCourses(_educationLevel);
  bool get _needsOccupation =>
      CareerData.statusHasOccupation(_employmentStatus);
  bool get _isStudent => _employmentStatus == CareerData.statusStudent;

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _education = data['education'] as String?;
    _occupation = data['occupation'] as String?;
    _annualIncome = data['annualIncome'] as String?;
    _courseDegree.text = (data['courseDegree'] as String?) ?? '';

    // Restore the hierarchy: use the saved level/status when present, otherwise
    // recover them from the flat values a pre-hierarchy draft stored.
    _educationLevel = (data['educationLevel'] as String?)?.trim().isNotEmpty ==
            true
        ? data['educationLevel'] as String
        : CareerData.levelForDegree(_education);
    _employmentStatus =
        (data['employmentStatus'] as String?)?.trim().isNotEmpty == true
            ? data['employmentStatus'] as String
            : CareerData.statusForOccupation(_occupation,
                employmentType: data['employmentType'] as String?);
    _sector = CareerData.sectorForOccupation(_occupation,
        employmentType: data['employmentType'] as String?);
  }

  @override
  void dispose() {
    _courseDegree.dispose();
    _courseFocus.dispose();
    super.dispose();
  }

  // ── Dependent-dropdown resets ───────────────────────────────────────────────

  void _onLevelChanged(String? level) {
    setState(() {
      _educationLevel = level;
      _v.clear('educationLevel');
      _v.clear('education');
      // A single-qualification level fills the degree in for the member.
      _education = CareerData.defaultCourseFor(level);
    });
  }

  void _onStatusChanged(String? status) {
    setState(() {
      _employmentStatus = status;
      _v.clear('employmentStatus');
      _v.clear('sector');
      _v.clear('occupation');
      _sector = null;
      _occupation = null;
      if (!CareerData.statusHasOccupation(status)) _annualIncome = null;
      if (status != CareerData.statusStudent) _courseDegree.clear();
    });
  }

  void _onSectorChanged(String? sector) {
    setState(() {
      _sector = sector;
      _v.clear('sector');
      _v.clear('occupation');
      _occupation = null; // the occupation list depends on the sector
    });
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  void _saveAndNext() {
    final l10n = context.l10n;
    final checks = <FieldCheck>[
      FieldCheck.notEmpty('educationLevel', _educationLevel,
          l10n.pleaseEnterField(l10n.educationLevel)),
      if (_needsCourse)
        FieldCheck.notEmpty(
            'education', _education, l10n.pleaseEnterField(l10n.courseDegree)),
      FieldCheck.notEmpty('employmentStatus', _employmentStatus,
          l10n.pleaseEnterField(l10n.employmentStatus)),
      if (_needsOccupation)
        FieldCheck.notEmpty(
            'sector', _sector, l10n.pleaseEnterField(_sectorLabel)),
      if (_needsOccupation)
        FieldCheck.notEmpty(
            'occupation', _occupation, l10n.pleaseEnterField(l10n.occupation)),
      if (_isStudent)
        FieldCheck.notEmpty('courseDegree', _courseDegree.text,
            l10n.pleaseEnterField(l10n.courseDegree),
            focusNode: _courseFocus),
    ];
    if (!_v.validate(context, checks, onChanged: () => setState(() {}))) return;

    // Persist only what the current branch actually shows, so a hidden value
    // from an earlier choice is never carried over.
    ref.read(profileCreationProvider.notifier).updateData({
      'educationLevel': _educationLevel,
      'education': _education ?? '',
      'employmentStatus': _employmentStatus,
      'employmentType': _needsOccupation ? (_sector ?? '') : '',
      'occupation':
          CareerData.occupationValueFor(_employmentStatus, _occupation),
      // Annual income is OPTIONAL (§8) — stored when given, blank otherwise.
      'annualIncome': _needsOccupation ? (_annualIncome ?? '') : '',
      'courseDegree': _isStudent ? _courseDegree.text.trim() : '',
    });
    widget.onNext();
  }

  /// Label of the sector picker — it asks a different question depending on the
  /// employment status (§6).
  String get _sectorLabel => _employmentStatus == CareerData.statusSelfEmployed
      ? context.l10n.businessOrProfession
      : context.l10n.governmentOrPrivate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.educationCareer, style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(l10n.educationCareerSubtitle,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),

          // ── 1. Education Level ────────────────────────────────────────────
          SearchableField(
            key: _v.anchor('educationLevel'),
            label: l10n.educationLevel,
            isRequired: true,
            items: CareerData.educationLevels,
            selectedItem: _educationLevel,
            prefixIcon: Icons.school_outlined,
            errorText: _v.errorOf('educationLevel'),
            onChanged: _onLevelChanged,
          ),

          // ── 2. Course / Degree (only when the level offers a choice) ──────
          if (_needsCourse) ...[
            const SizedBox(height: 16),
            SearchableWithOthersField(
              key: _v.anchor('education'),
              label: l10n.courseDegree,
              isRequired: true,
              items: CareerData.coursesFor(_educationLevel),
              value: _education,
              prefixIcon: Icons.menu_book_outlined,
              errorText: _v.errorOf('education'),
              onChanged: (v) => setState(() {
                _education = v;
                _v.clear('education');
              }),
            ),
          ],

          const SizedBox(height: 24),

          // ── 3. Employment Status ──────────────────────────────────────────
          SearchableField(
            key: _v.anchor('employmentStatus'),
            label: l10n.employmentStatus,
            isRequired: true,
            items: CareerData.employmentStatuses,
            selectedItem: _employmentStatus,
            prefixIcon: Icons.badge_outlined,
            errorText: _v.errorOf('employmentStatus'),
            onChanged: _onStatusChanged,
          ),

          // ── 4. Sector · 5. Occupation (Employed / Self Employed only) ─────
          if (_needsOccupation) ...[
            const SizedBox(height: 16),
            SearchableField(
              key: _v.anchor('sector'),
              label: _sectorLabel,
              isRequired: true,
              items: CareerData.sectorsFor(_employmentStatus),
              selectedItem: _sector,
              prefixIcon: Icons.account_balance_outlined,
              errorText: _v.errorOf('sector'),
              onChanged: _onSectorChanged,
            ),
            const SizedBox(height: 16),
            SearchableWithOthersField(
              key: _v.anchor('occupation'),
              label: l10n.occupation,
              isRequired: true,
              enabled: (_sector ?? '').isNotEmpty,
              items: CareerData.occupationsFor(
                  status: _employmentStatus, sector: _sector),
              value: _occupation,
              prefixIcon: Icons.work_outline,
              errorText: _v.errorOf('occupation'),
              onChanged: (v) => setState(() {
                _occupation = v;
                _v.clear('occupation');
              }),
            ),
            const SizedBox(height: 16),
            // Annual Income is OPTIONAL (§8) — no asterisk, no validation.
            SearchableWithOthersField(
              label: l10n.annualIncome,
              items: AppConstants.incomeRanges,
              value: _annualIncome,
              prefixIcon: Icons.currency_rupee,
              onChanged: (v) => setState(() => _annualIncome = v),
            ),
          ],

          // Student → what they are currently studying.
          if (_isStudent) ...[
            const SizedBox(height: 16),
            AppTextField(
              key: _v.anchor('courseDegree'),
              controller: _courseDegree,
              focusNode: _courseFocus,
              label: '${l10n.courseDegree} *',
              hint: l10n.courseDegreeHint,
              errorText: _v.errorOf('courseDegree'),
              onChanged: (_) {
                if (_v.errorOf('courseDegree') != null) {
                  setState(() => _v.clear('courseDegree'));
                }
              },
            ),
          ],

          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: l10n.continueLabel),
        ],
      ),
    );
  }
}
