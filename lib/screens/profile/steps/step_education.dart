import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/master_options_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';
import '../../../widgets/common/searchable_field.dart';

/// Step 7 — Education & Career: Education (req), Occupation (req), Employment
/// Type, College, Company, Annual Income and Work Location (optional).
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
  final _college = TextEditingController();
  final _company = TextEditingController();
  final _workLocation = TextEditingController();

  @override
  void initState() {
    super.initState();
    final data = ref.read(profileCreationProvider).data;
    _education = data['education'] as String?;
    _occupation = data['occupation'] as String?;
    _employmentType = data['employmentType'] as String?;
    _annualIncome = data['annualIncome'] as String?;
    _college.text = (data['collegeName'] as String?) ?? '';
    _company.text = (data['companyName'] as String?) ?? '';
    _workLocation.text = (data['workLocation'] as String?) ?? '';
  }

  @override
  void dispose() {
    _college.dispose();
    _company.dispose();
    _workLocation.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    if (_education == null || _education!.isEmpty) {
      _snack('Please select your education');
      return;
    }
    if (_occupation == null || _occupation!.isEmpty) {
      _snack('Please select your occupation');
      return;
    }
    ref.read(profileCreationProvider.notifier).updateData({
      'education': _education,
      'occupation': _occupation,
      'employmentType': _employmentType ?? '',
      'annualIncome': _annualIncome ?? '',
      'collegeName': _college.text.trim(),
      'companyName': _company.text.trim(),
      'workLocation': _workLocation.text.trim(),
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
          // Master list + user-added values; "+" saves permanently to the DB
          // (the old "Others → textbox" flow was removed everywhere).
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
          AppTextField(
            controller: _college,
            label: 'College Name',
            hint: 'Optional',
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
          const SizedBox(height: 16),
          SearchableField(
            label: 'Employment Type',
            items: AppConstants.employmentTypeList,
            selectedItem: _employmentType,
            prefixIcon: Icons.badge_outlined,
            onChanged: (v) => setState(() => _employmentType = v),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _company,
            label: 'Company Name',
            hint: 'Optional',
          ),
          const SizedBox(height: 16),
          SearchableField(
            label: 'Annual Income',
            items: _merged(AppConstants.incomeRanges,
                MasterOptionsService.income, _annualIncome),
            selectedItem: _annualIncome,
            prefixIcon: Icons.currency_rupee,
            onAddNew: (v) => ref
                .read(masterOptionsServiceProvider)
                .add(MasterOptionsService.income, value: v),
            onChanged: (v) => setState(() => _annualIncome = v),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _workLocation,
            label: 'Work Location',
            hint: 'Optional',
          ),
          const SizedBox(height: 36),
          GradientButton(onPressed: _saveAndNext, text: 'Continue'),
        ],
      ),
    );
  }
}
