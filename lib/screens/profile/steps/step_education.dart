import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_with_others_field.dart';

/// Career step — Education (req) and Occupation (req). The occupation then
/// drives the rest, mirroring the website's Career step exactly:
///   • Student     → Course / Degree (req)
///   • Working     → Employment Type (opt) + Annual Income (req)
///   • Not Working → nothing further
///
/// Every dropdown ends with **"Others"**, which reveals a custom textbox below
/// it — there is no "+" Add button (spec §2–§5). A typed value is kept ONLY on
/// this profile and is never written back to the shared master data.
class StepEducation extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const StepEducation({super.key, required this.onNext});

  @override
  ConsumerState<StepEducation> createState() => _StepEducationState();
}

class _StepEducationState extends ConsumerState<StepEducation> {
  String? _education;
  String? _occupation;
  String? _employmentType;
  String? _annualIncome;
  final _courseDegree = TextEditingController();

  /// 'student' | 'notWorking' | 'working' | 'none' — matches the website's
  /// `occupationCase` so the same conditional fields appear.
  String get _occCase {
    final o = _occupation;
    if (o == null || o.isEmpty) return 'none';
    if (o == 'Not Working') return 'notWorking';
    if (o == 'Student') return 'student';
    return 'working';
  }

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _education = data['education'] as String?;
    _occupation = data['occupation'] as String?;
    _employmentType = data['employmentType'] as String?;
    _annualIncome = data['annualIncome'] as String?;
    _courseDegree.text = (data['courseDegree'] as String?) ?? '';
  }

  @override
  void dispose() {
    _courseDegree.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    final l10n = context.l10n;
    if (_education == null || _education!.isEmpty) {
      return _snack(l10n.pleaseEnterField(l10n.education));
    }
    if (_occupation == null || _occupation!.isEmpty) {
      return _snack(l10n.pleaseEnterField(l10n.occupation));
    }
    if (_occCase == 'student' && _courseDegree.text.trim().isEmpty) {
      return _snack(l10n.pleaseEnterField(l10n.courseDegree));
    }
    if (_occCase == 'working' &&
        (_annualIncome == null || _annualIncome!.isEmpty)) {
      return _snack(l10n.pleaseEnterField(l10n.annualIncome));
    }

    // Persist only the fields the current occupation case actually shows, so
    // hidden values are never carried over.
    ref.read(profileCreationProvider.notifier).updateData({
      'education': _education,
      'occupation': _occupation,
      'employmentType': _occCase == 'working' ? (_employmentType ?? '') : '',
      'annualIncome': _occCase == 'working' ? (_annualIncome ?? '') : '',
      'courseDegree':
          _occCase == 'student' ? _courseDegree.text.trim() : '',
    });
    widget.onNext();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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
          SearchableWithOthersField(
            label: l10n.highestEducation,
            isRequired: true,
            items: AppConstants.educations,
            value: _education,
            prefixIcon: Icons.school_outlined,
            onChanged: (v) => setState(() => _education = v),
          ),
          const SizedBox(height: 16),
          SearchableWithOthersField(
            label: l10n.occupation,
            isRequired: true,
            items: AppConstants.occupations,
            value: _occupation,
            prefixIcon: Icons.work_outline,
            onChanged: (v) => setState(() => _occupation = v),
          ),
          // Student → Course / Degree.
          if (_occCase == 'student') ...[
            const SizedBox(height: 16),
            AppTextField(
              controller: _courseDegree,
              label: '${l10n.courseDegree} *',
              hint: l10n.courseDegreeHint,
            ),
          ],
          // Working → Employment Type (optional) + Annual Income (required).
          if (_occCase == 'working') ...[
            const SizedBox(height: 16),
            SearchableWithOthersField(
              label: l10n.employmentType,
              items: AppConstants.employmentTypeList,
              value: _employmentType,
              prefixIcon: Icons.badge_outlined,
              onChanged: (v) => setState(() => _employmentType = v),
            ),
            const SizedBox(height: 16),
            SearchableWithOthersField(
              label: l10n.annualIncome,
              isRequired: true,
              items: AppConstants.incomeRanges,
              value: _annualIncome,
              prefixIcon: Icons.currency_rupee,
              onChanged: (v) => setState(() => _annualIncome = v),
            ),
          ],
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: l10n.continueLabel),
        ],
      ),
    );
  }
}
