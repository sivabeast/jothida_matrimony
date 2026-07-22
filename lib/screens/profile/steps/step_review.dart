import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/value_l10n.dart';
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
    final l10n = context.l10n;
    final d = state.data;

    // Stored values stay English; the review renders them in the app language.
    String s(dynamic v) =>
        (v == null) ? '' : context.localizeValue(v.toString());
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
          Text(l10n.reviewSubmit, style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(l10n.reviewSubtitle,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          _section(context, l10n.basicDetails, 0, [
            [l10n.name, s(d['name'])],
            [l10n.gender, s(d['gender'])],
            [l10n.age, s(d['age'])],
            [l10n.height, s(d['height'])],
            [l10n.maritalStatus, s(d['maritalStatus'])],
            [l10n.physicalStatus, s(d['physicalStatus'])],
          ]),
          _section(context, l10n.location, 1, [
            [l10n.location, location],
            [l10n.nativePlace, s(d['nativePlace'])],
            [l10n.citizenship, s(d['citizenship'])],
          ]),
          _section(context, l10n.career, 2, [
            [l10n.education, s(d['education'])],
            [l10n.occupation, s(d['occupation'])],
            if (s(d['courseDegree']).isNotEmpty)
              [l10n.courseDegree, s(d['courseDegree'])],
            if (s(d['employmentType']).isNotEmpty)
              [l10n.employmentLabel, s(d['employmentType'])],
            if (s(d['annualIncome']).isNotEmpty)
              [l10n.annualIncome, s(d['annualIncome'])],
          ]),
          _section(context, l10n.community, 3, [
            [l10n.religion, s(d['religion'])],
            [l10n.caste, s(d['caste'])],
            [l10n.subCaste, s(d['subCaste'])],
            [l10n.motherTongue, s(d['motherTongue'])],
          ]),
          _section(context, l10n.horoscope, 4, [
            [l10n.rasi, s(horo['rasi'])],
            [l10n.nakshatra, s(horo['nakshatra'])],
            [l10n.lagnam, s(horo['lagnam'])],
            [l10n.birthTime, s(horo['birthTime'])],
            [l10n.birthPlace, s(horo['birthPlace'])],
          ]),
          _section(context, l10n.contact, 8, [
            [l10n.contactPerson, s(contact['contactPersonName'])],
            [l10n.relationship, s(contact['relationship'])],
            [l10n.mobileLabel, s(contact['mobileNumber'])],
            [l10n.whatsapp, s(contact['whatsappNumber'])],
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
                      : l10n.submittingLabel),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 24),
          GradientButton(
            onPressed: state.isLoading ? null : onSubmit,
            isLoading: state.isLoading,
            text: isEditMode ? l10n.saveChanges : l10n.submitProfile,
          ),
        ],
      ),
    );
  }

  Widget _section(
      BuildContext context, String title, int step, List<List<String>> rows) {
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
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.primary)),
              ),
              TextButton(
                onPressed: () => onEditStep(step),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(context.l10n.edit),
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
