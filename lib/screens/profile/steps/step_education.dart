import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/master_options_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';

/// Career step — Education (req) and Occupation (req). The occupation then
/// drives the rest, mirroring the website's Career step exactly:
///   • Student     → Course / Degree (req)
///   • Working     → Employment Type (opt) + Annual Income (req)
///   • Not Working → nothing further
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
    if (_education == null || _education!.isEmpty) {
      return _snack('Please select your education');
    }
    if (_occupation == null || _occupation!.isEmpty) {
      return _snack('Please select your occupation');
    }
    if (_occCase == 'student' && _courseDegree.text.trim().isEmpty) {
      return _snack('Please enter your course / degree');
    }
    if (_occCase == 'working' &&
        (_annualIncome == null || _annualIncome!.isEmpty)) {
      return _snack('Please select your annual income');
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

  /// Base constants + live user-added values (+ the current selection so a
  /// custom value saved earlier still shows).
  List<String> _merged(List<String> base, String type, String? selected) {
    final items = mergeOptions(base, customValues(ref, type));
    if ((selected ?? '').isNotEmpty && !items.contains(selected)) {
      items.insert(0, selected!);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Education & Career', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text('Your qualifications and work.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          SearchableField(
            label: 'Highest Education',
            isRequired: true,
            items: _merged(AppConstants.educations,
                MasterOptionsService.education, _education),
            selectedItem: _education,
            prefixIcon: Icons.school_outlined,
            onAddNew: (v) => ref
                .read(masterOptionsServiceProvider)
                .add(MasterOptionsService.education, value: v),
            onChanged: (v) => setState(() => _education = v),
          ),
          const SizedBox(height: 16),
          SearchableField(
            label: 'Occupation',
            isRequired: true,
            items: _merged(AppConstants.occupations,
                MasterOptionsService.occupation, _occupation),
            selectedItem: _occupation,
            prefixIcon: Icons.work_outline,
            onAddNew: (v) => ref
                .read(masterOptionsServiceProvider)
                .add(MasterOptionsService.occupation, value: v),
            onChanged: (v) => setState(() => _occupation = v),
          ),
          // Student → Course / Degree.
          if (_occCase == 'student') ...[
            const SizedBox(height: 16),
            AppTextField(
              controller: _courseDegree,
              label: 'Course / Degree *',
              hint: 'e.g. B.E Computer Science',
            ),
          ],
          // Working → Employment Type (optional) + Annual Income (required).
          if (_occCase == 'working') ...[
            const SizedBox(height: 16),
            SearchableField(
              label: 'Employment Type',
              items: AppConstants.employmentTypeList,
              selectedItem: _employmentType,
              prefixIcon: Icons.badge_outlined,
              onChanged: (v) => setState(() => _employmentType = v),
            ),
            const SizedBox(height: 16),
            SearchableField(
              label: 'Annual Income',
              isRequired: true,
              items: _merged(AppConstants.incomeRanges,
                  MasterOptionsService.income, _annualIncome),
              selectedItem: _annualIncome,
              prefixIcon: Icons.currency_rupee,
              onAddNew: (v) => ref
                  .read(masterOptionsServiceProvider)
                  .add(MasterOptionsService.income, value: v),
              onChanged: (v) => setState(() => _annualIncome = v),
            ),
          ],
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: 'Continue'),
        ],
      ),
    );
  }
}
