import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/gradient_button.dart';

/// Final Review step — a read-only summary of everything entered, grouped by
/// section with an "Edit" jump back to that step, plus the submit button
/// (mirrors the website's Review step). Submitting is wired through [onSubmit]
/// (the wizard treats Review as the last step), and the upload progress bar is
/// driven by [ProfileCreationState].
class StepReview extends ConsumerWidget {
  final VoidCallback onSubmit;
  final void Function(int step) onEditStep;
  final bool isEditMode;

  const StepReview({
    super.key,
    required this.onSubmit,
    required this.onEditStep,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileCreationProvider);
    final d = state.data;

    String s(dynamic v) => (v == null) ? '' : v.toString();
    Map<String, dynamic> group(String key) {
      final g = d[key];
      return g is Map ? Map<String, dynamic>.from(g) : const {};
    }

    final horo = group('horoscopeDetails');
    final contact = group('contactDetails');

    final location = [d['city'], d['district'], d['state'], d['country']]
        .map(s)
        .where((v) => v.isNotEmpty)
        .join(', ');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review & Submit', style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          const Text('Please review your details before submitting.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          _section('Basic Details', 0, [
            ['Name', s(d['name'])],
            ['Gender', s(d['gender'])],
            ['Age', s(d['age'])],
            ['Height', s(d['height'])],
            ['Marital Status', s(d['maritalStatus'])],
            ['Physical Status', s(d['physicalStatus'])],
          ]),
          _section('Location', 1, [
            ['Location', location],
            ['Native Place', s(d['nativePlace'])],
            ['Citizenship', s(d['citizenship'])],
          ]),
          _section('Career', 2, [
            ['Education', s(d['education'])],
            ['Occupation', s(d['occupation'])],
            if (s(d['courseDegree']).isNotEmpty)
              ['Course / Degree', s(d['courseDegree'])],
            if (s(d['employmentType']).isNotEmpty)
              ['Employment', s(d['employmentType'])],
            if (s(d['annualIncome']).isNotEmpty)
              ['Annual Income', s(d['annualIncome'])],
          ]),
          _section('Community', 3, [
            ['Religion', s(d['religion'])],
            ['Caste', s(d['caste'])],
            ['Sub Caste', s(d['subCaste'])],
            ['Mother Tongue', s(d['motherTongue'])],
          ]),
          _section('Horoscope', 4, [
            ['Rasi', s(horo['rasi'])],
            ['Nakshatra', s(horo['nakshatra'])],
            ['Lagnam', s(horo['lagnam'])],
            ['Birth Time', s(horo['birthTime'])],
            ['Birth Place', s(horo['birthPlace'])],
          ]),
          _section('Contact', 8, [
            ['Contact Person', s(contact['contactPersonName'])],
            ['Relationship', s(contact['relationship'])],
            ['Mobile', s(contact['mobileNumber'])],
            ['WhatsApp', s(contact['whatsappNumber'])],
          ]),

          if (state.isLoading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.uploadProgress > 0 ? state.uploadProgress : null,
                minHeight: 6,
                backgroundColor: Colors.grey[200],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.uploadStatus ??
                  (state.uploadProgress > 0
                      ? '${(state.uploadProgress * 100).round()}%'
                      : 'Submitting…'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 24),
          GradientButton(
            onPressed: state.isLoading ? null : onSubmit,
            isLoading: state.isLoading,
            text: isEditMode ? 'Save Changes' : 'Submit Profile',
          ),
        ],
      ),
    );
  }

  Widget _section(String title, int step, List<List<String>> rows) {
    final visible = rows.where((r) => r[1].trim().isNotEmpty).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.primary)),
              TextButton(
                onPressed: () => onEditStep(step),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...visible.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(r[0],
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 6,
                      child: Text(r[1],
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
