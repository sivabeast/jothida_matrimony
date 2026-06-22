import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_text_styles.dart';
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
            items: AppConstants.educations,
            selectedItem: _education,
            prefixIcon: Icons.school_outlined,
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
            items: AppConstants.occupations,
            selectedItem: _occupation,
            prefixIcon: Icons.work_outline,
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
            items: AppConstants.incomeRanges,
            selectedItem: _annualIncome,
            prefixIcon: Icons.currency_rupee,
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
