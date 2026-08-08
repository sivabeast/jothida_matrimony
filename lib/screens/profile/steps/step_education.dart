import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/data/education_catalog.dart';
import '../../../core/data/occupation_catalog.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/inline_validation.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';
import '../../../widgets/common/searchable_multi_select_field.dart';
import '../../../widgets/common/searchable_with_others_field.dart';

/// Career step — two dependent hierarchies, both of which hide what does not
/// apply (§3–§6):
///
///   Education Level  →  Degree(s), and only above 12th
///   Employment Status → Employment Type → Occupation
///
/// **§3** Below 10th / 10th / 12th describe the qualification completely, so no
/// degree picker is shown for them at all.
/// **§4** A member may hold several degrees. With one or two both go on the
/// profile card; from three onwards they choose which one or two to show.
/// **§5** Employment Type changes with the status, and disappears entirely for
/// a student, job seeker, homemaker, retiree or "other".
/// **§6** The occupation list is ORDERED by what the member studied — never
/// filtered, so anyone can still find any job by typing it.
///
/// Validation follows the app-wide rule: pressing Continue paints an inline red
/// message under each empty required field and scrolls to + focuses the FIRST
/// of them.
class StepEducation extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepEducation({super.key, required this.onNext});

  @override
  ConsumerState<StepEducation> createState() => _StepEducationState();
}

class _StepEducationState extends ConsumerState<StepEducation> {
  final _v = InlineValidation();

  String? _educationLevel;

  /// Every qualification held (§4).
  final List<String> _degrees = [];

  /// The one or two picked for the card — only asked for at 3+ degrees.
  final List<String> _displayDegrees = [];

  String? _employmentStatus;
  String? _employmentType;
  String? _occupation;
  String? _annualIncome;
  final _courseDegree = TextEditingController();
  final _courseFocus = FocusNode();

  bool get _needsDegrees => EducationCatalog.levelHasDegrees(_educationLevel);
  bool get _needsOccupation =>
      OccupationCatalog.statusHasOccupation(_employmentStatus);
  bool get _isStudent => _employmentStatus == OccupationCatalog.statusStudent;

  /// §4 — the chooser only appears from the third degree onwards.
  bool get _needsDisplayChoice => _degrees.length > 2;

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _occupation = data['occupation'] as String?;
    _annualIncome = data['annualIncome'] as String?;
    _courseDegree.text = (data['courseDegree'] as String?) ?? '';

    // Restore the hierarchy: prefer the saved level/status, otherwise recover
    // them from the flat values a pre-hierarchy draft stored.
    final storedLevel = (data['educationLevel'] as String?)?.trim() ?? '';
    final storedEducation = (data['education'] as String?)?.trim() ?? '';
    _educationLevel = storedLevel.isNotEmpty
        ? EducationCatalog.canonicalLevel(storedLevel)
        : EducationCatalog.levelForDegree(storedEducation);

    // `degrees` is the list; a profile written before §4 only has `education`.
    final saved = data['degrees'];
    if (saved is List && saved.isNotEmpty) {
      _degrees.addAll(saved.map((e) => e.toString()));
    } else if (storedEducation.isNotEmpty) {
      _degrees.add(storedEducation);
    }
    final savedDisplay = data['displayDegrees'];
    if (savedDisplay is List) {
      _displayDegrees.addAll(
        savedDisplay.map((e) => e.toString()).where(_degrees.contains),
      );
    }

    _employmentStatus =
        (data['employmentStatus'] as String?)?.trim().isNotEmpty == true
            ? data['employmentStatus'] as String
            : OccupationCatalog.statusForOccupation(_occupation,
                employmentType: data['employmentType'] as String?);
    _employmentType = OccupationCatalog.typeForOccupation(_occupation,
        employmentType: data['employmentType'] as String?);
  }

  @override
  void dispose() {
    _courseDegree.dispose();
    _courseFocus.dispose();
    super.dispose();
  }

  // ── Dependent-picker resets ────────────────────────────────────────────────

  void _onLevelChanged(String? level) {
    setState(() {
      _educationLevel = level;
      _v.clear('educationLevel');
      _v.clear('degrees');
      _degrees.clear();
      _displayDegrees.clear();
      // A schooling level IS the qualification, so it is filled in silently
      // and the degree picker never appears (§3).
      final implicit = EducationCatalog.implicitDegreeFor(level);
      if (implicit != null) _degrees.add(implicit);
    });
  }

  void _onDegreesChanged(List<String> picked) {
    setState(() {
      _degrees
        ..clear()
        ..addAll(picked);
      // Drop any card choice that is no longer held, and stop asking the
      // question once the member is back down to two.
      _displayDegrees.removeWhere((d) => !_degrees.contains(d));
      if (!_needsDisplayChoice) _displayDegrees.clear();
      _v.clear('degrees');
    });
  }

  void _onStatusChanged(String? status) {
    setState(() {
      _employmentStatus = status;
      _v.clear('employmentStatus');
      _v.clear('employmentType');
      _v.clear('occupation');
      _employmentType = null;
      _occupation = null;
      if (!OccupationCatalog.statusHasOccupation(status)) _annualIncome = null;
      if (status != OccupationCatalog.statusStudent) _courseDegree.clear();
    });
  }

  void _onTypeChanged(String? type) {
    setState(() {
      _employmentType = type;
      _v.clear('employmentType');
      _v.clear('occupation');
      _occupation = null; // the occupation list depends on the type
    });
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  /// What actually goes on the card (§4): the member's pick at 3+, otherwise
  /// simply everything they hold.
  List<String> get _effectiveDisplayDegrees =>
      _needsDisplayChoice && _displayDegrees.isNotEmpty
          ? _displayDegrees
          : _degrees.take(2).toList();

  void _saveAndNext() {
    final l10n = context.l10n;
    final checks = <FieldCheck>[
      FieldCheck.notEmpty('educationLevel', _educationLevel,
          l10n.pleaseEnterField(l10n.educationLevel)),
      if (_needsDegrees)
        FieldCheck(
            id: 'degrees',
            valid: _degrees.isNotEmpty,
            message: l10n.pleaseSelect(l10n.degreesLabel)),
      FieldCheck.notEmpty('employmentStatus', _employmentStatus,
          l10n.pleaseEnterField(l10n.employmentStatus)),
      if (_needsOccupation)
        FieldCheck.notEmpty('employmentType', _employmentType,
            l10n.pleaseSelect(l10n.employmentType)),
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
    final display = _effectiveDisplayDegrees;
    ref.read(profileCreationProvider.notifier).updateData({
      'educationLevel': _educationLevel,
      'degrees': _degrees,
      'displayDegrees': display,
      // `education` stays the single primary qualification the website and
      // every existing filter read.
      'education': display.isNotEmpty
          ? display.first
          : (_degrees.isNotEmpty ? _degrees.first : ''),
      'employmentStatus': _employmentStatus,
      'employmentType': _needsOccupation ? (_employmentType ?? '') : '',
      'occupation':
          OccupationCatalog.occupationValueFor(_employmentStatus, _occupation),
      // Annual income is OPTIONAL — stored when given, blank otherwise.
      'annualIncome': _needsOccupation ? (_annualIncome ?? '') : '',
      'courseDegree': _isStudent ? _courseDegree.text.trim() : '',
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
          Text(l10n.educationCareer, style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(l10n.educationCareerSubtitle,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),

          // ── 1. Education Level ────────────────────────────────────────────
          SearchableField.fromOptions(
            key: _v.anchor('educationLevel'),
            label: l10n.educationLevel,
            isRequired: true,
            options: EducationCatalog.levels,
            selectedItem: _educationLevel,
            prefixIcon: Icons.school_outlined,
            errorText: _v.errorOf('educationLevel'),
            onChanged: _onLevelChanged,
          ),

          // ── 2. Degrees — hidden for schooling levels (§3), multi-select (§4)
          if (_needsDegrees) ...[
            const SizedBox(height: 16),
            SearchableMultiSelectField.fromOptions(
              key: _v.anchor('degrees'),
              label: l10n.degreesLabel,
              options: EducationCatalog.degreesFor(_educationLevel),
              selected: _degrees,
              prefixIcon: Icons.menu_book_outlined,
              showEnglishInBrackets: true,
              hint: l10n.degreesHint,
              onChanged: _onDegreesChanged,
            ),
            InlineFieldError(_v.errorOf('degrees')),

            // ── 3. Which one or two go on the card — only from 3 degrees (§4)
            if (_needsDisplayChoice) ...[
              const SizedBox(height: 16),
              SearchableMultiSelectField.fromOptions(
                label: l10n.profileDisplayQualification,
                options: EducationCatalog.degreesFor(_educationLevel)
                    .where((o) => _degrees.contains(o.en))
                    .toList(),
                selected: _displayDegrees,
                prefixIcon: Icons.star_outline,
                showEnglishInBrackets: true,
                maxSelection: 2,
                hint: l10n.profileDisplayQualificationHelp,
                onChanged: (v) => setState(() {
                  _displayDegrees
                    ..clear()
                    ..addAll(v);
                }),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(l10n.profileDisplayQualificationHelp,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
            ],
          ],

          const SizedBox(height: 24),

          // ── 4. Employment Status (§5, field 1) ────────────────────────────
          SearchableField.fromOptions(
            key: _v.anchor('employmentStatus'),
            label: l10n.employmentStatus,
            isRequired: true,
            options: OccupationCatalog.statuses,
            selectedItem: _employmentStatus,
            prefixIcon: Icons.badge_outlined,
            errorText: _v.errorOf('employmentStatus'),
            onChanged: _onStatusChanged,
          ),

          // ── 5. Employment Type · 6. Occupation (§5, fields 2 and 3) ───────
          // Both vanish for a student, job seeker, homemaker, retiree or
          // "other" — there is no sector to ask about.
          if (_needsOccupation) ...[
            const SizedBox(height: 16),
            SearchableField.fromOptions(
              key: _v.anchor('employmentType'),
              label: l10n.employmentType,
              isRequired: true,
              options: OccupationCatalog.typesFor(_employmentStatus),
              selectedItem: _employmentType,
              prefixIcon: Icons.account_balance_outlined,
              errorText: _v.errorOf('employmentType'),
              onChanged: _onTypeChanged,
            ),
            const SizedBox(height: 16),
            SearchableWithOthersField.fromOptions(
              key: _v.anchor('occupation'),
              label: l10n.occupation,
              isRequired: true,
              enabled: (_employmentType ?? '').isNotEmpty,
              // Ordered by education (§6), never filtered by it.
              options: OccupationCatalog.occupationsFor(
                status: _employmentStatus,
                type: _employmentType,
                educationLevel: _educationLevel,
              ),
              value: _occupation,
              prefixIcon: Icons.work_outline,
              showEnglishInBrackets: true,
              errorText: _v.errorOf('occupation'),
              onChanged: (v) => setState(() {
                _occupation = v;
                _v.clear('occupation');
              }),
            ),
            const SizedBox(height: 16),
            // Annual Income is OPTIONAL — no asterisk, no validation.
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
