import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/profile_completion.dart';
import '../../providers/profile_provider.dart';

/// Shows ONLY the profile sections that are still incomplete, each linking to
/// the right editor — instead of restarting the onboarding wizard. Registered
/// at `/complete-profile`; opened from the "Complete your profile" card.
class CompleteProfileScreen extends ConsumerWidget {
  const CompleteProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[CompleteProfileScreen] build — route /complete-profile');
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Could not load profile: $e')),
        data: (profile) {
          final completion = computeProfileCompletion(profile);

          if (profile == null) {
            return _centered(
              icon: Icons.person_add_alt,
              title: 'Create your profile',
              subtitle: 'Set up your profile to start receiving matches.',
              actionLabel: 'Create Profile',
              onAction: () => context.push('/profile/create'),
            );
          }

          if (completion.missingFields.isEmpty) {
            return _centered(
              icon: Icons.verified,
              title: 'Your profile is complete! 🎉',
              subtitle: 'Nothing left to fill in. You are all set.',
              actionLabel: 'Back',
              onAction: () => Navigator.of(context).maybePop(),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Progress header.
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 54,
                      height: 54,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 54,
                            height: 54,
                            child: CircularProgressIndicator(
                              value: (completion.percent / 100).clamp(0.0, 1.0),
                              strokeWidth: 5,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                            ),
                          ),
                          Text('${completion.percent}%',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Almost there!',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  fontFamily: 'Poppins')),
                          SizedBox(height: 2),
                          Text('Finish the details below to get more responses.',
                              style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('Pending details (${completion.missingFields.length})',
                  style: const TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 8),
              ...completion.missingFields.map((label) => _PendingTile(
                    label: label,
                    onTap: () => context.push(_routeFor(label)),
                  )),
            ],
          );
        },
      ),
    );
  }

  /// Maps an incomplete item to the screen that lets the user fill it.
  static String _routeFor(String label) {
    if (label.contains('Horoscope') || label.contains('Birth')) return '/horoscope';
    if (label.contains('Partner')) return '/partner-preferences';
    // Basic details, Profile photo, About me, Education, Profession, Annual
    // income, Height & weight, Family details, Contact details → the section
    // editors on Personal Details.
    return '/personal-details';
  }

  Widget _centered({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PendingTile({required this.label, required this.onTap});

  IconData get _icon {
    if (label.contains('photo')) return Icons.photo_camera_outlined;
    if (label.contains('About')) return Icons.notes_outlined;
    if (label.contains('Education')) return Icons.school_outlined;
    if (label.contains('Profession')) return Icons.work_outline;
    if (label.contains('income')) return Icons.currency_rupee;
    if (label.contains('Height')) return Icons.straighten;
    if (label.contains('Horoscope') || label.contains('Birth')) {
      return Icons.auto_awesome_outlined;
    }
    if (label.contains('Family')) return Icons.diversity_3_outlined;
    if (label.contains('Partner')) return Icons.favorite_border;
    if (label.contains('Contact')) return Icons.call_outlined;
    return Icons.edit_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Icon(_icon, color: AppColors.primary, size: 20),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Tap to complete'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.primary),
        onTap: onTap,
      ),
    );
  }
}
