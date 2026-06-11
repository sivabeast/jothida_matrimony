import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/profile_completion.dart';
import '../../providers/profile_provider.dart';

/// Home-screen card that shows how complete the user's matrimony profile is,
/// lists what's still missing, and links to the profile editor. Hidden once
/// the profile reaches 100%.
class ProfileCompletionCard extends ConsumerWidget {
  const ProfileCompletionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final profile = profileAsync.valueOrNull;
    final completion = computeProfileCompletion(profile);

    if (profileAsync.isLoading || completion.isComplete) {
      return const SizedBox.shrink();
    }

    final missingPreview = completion.missingFields.take(3).toList();
    final moreCount = completion.missingFields.length - missingPreview.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, AppColors.gold.withOpacity(0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircularPercentIndicator(
                radius: 32,
                lineWidth: 6,
                animation: true,
                animationDuration: 800,
                percent: (completion.percent / 100).clamp(0.0, 1.0),
                center: Text(
                  '${completion.percent}%',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.primary),
                ),
                progressColor: AppColors.primary,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                circularStrokeCap: CircularStrokeCap.round,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Complete your profile',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          fontFamily: 'Poppins'),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Profiles with full details get up to 10× more responses',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[700], height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Missing fields
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final field in missingPreview)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_circle_outline,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(field,
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.primary)),
                    ],
                  ),
                ),
              if (moreCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text('+$moreCount more',
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/profile/create'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Complete Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
