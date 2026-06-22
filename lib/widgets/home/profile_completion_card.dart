import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/profile_completion.dart';
import '../../providers/profile_provider.dart';

/// Prominent Home "Complete Your Profile" banner. Shows the completion
/// percentage + progress bar and a single "Complete Profile" button that jumps
/// straight to the NEXT incomplete section. Hidden once the profile is 100%.
class ProfileCompletionCard extends ConsumerWidget {
  const ProfileCompletionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final profile = profileAsync.valueOrNull;

    if (profileAsync.isLoading && profile == null) {
      return const SizedBox.shrink();
    }

    final completion = computeProfileCompletion(profile);
    final incomplete =
        profileSections(profile).where((s) => !s.isComplete).toList();

    // Fully complete → nothing to nag about.
    if (incomplete.isEmpty) return const SizedBox.shrink();

    // "Complete Profile" jumps to the first still-incomplete section.
    final nextRoute = incomplete.first.route;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF7E6),
            AppColors.gold.withOpacity(0.16),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Complete Your Profile',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        fontFamily: 'Poppins')),
              ),
              const ProfileStatusBadge(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your profile is ${completion.percent}% complete.',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          const SizedBox(height: 2),
          Text('Complete your profile to get better matches.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (completion.percent / 100).clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: Colors.white,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.push(nextRoute),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('Complete Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => context.push('/complete-profile'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text('View all'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact "Profile Complete" / "Profile Incomplete (X%)" status chip,
/// driven by the live profile-completion percentage. Usable anywhere a
/// persistent status indicator is wanted (e.g. the profile tab header).
class ProfileStatusBadge extends ConsumerWidget {
  final bool showPercent;
  const ProfileStatusBadge({super.key, this.showPercent = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final completion = computeProfileCompletion(profile);
    final complete = completion.isComplete;
    final color = complete ? AppColors.success : AppColors.warning;
    final label = complete
        ? 'Profile Complete'
        : showPercent
            ? 'Incomplete · ${completion.percent}%'
            : 'Profile Incomplete';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(complete ? Icons.verified : Icons.error_outline,
              size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
