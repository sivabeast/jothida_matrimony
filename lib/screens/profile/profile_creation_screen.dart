import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import 'steps/step1_who_are_you.dart';
import 'steps/step2_personal_details.dart';
import 'steps/step3_horoscope.dart';
import 'steps/step4_family.dart';
import 'steps/step5_partner_prefs.dart';
import 'steps/step6_photos.dart';
import 'steps/step7_contact.dart';

class ProfileCreationScreen extends ConsumerStatefulWidget {
  /// When non-null, the wizard was opened to edit an existing profile via
  /// Profile → "Edit Profile" (route `/profile/:id/edit`).
  final String? editProfileId;
  const ProfileCreationScreen({super.key, this.editProfileId});

  @override
  ConsumerState<ProfileCreationScreen> createState() => _ProfileCreationScreenState();
}

class _ProfileCreationScreenState extends ConsumerState<ProfileCreationScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 7;

  bool get _isEditMode => widget.editProfileId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      debugPrint(
          '[ProfileCreation] opened in EDIT mode for profile ${widget.editProfileId}');
    }
  }

  final List<String> _stepTitles = [
    'Who Are You',
    'Personal Details',
    'Horoscope',
    'Family',
    'Partner Preferences',
    'Photos',
    'Contact Details',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _submitProfile();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Future<void> _submitProfile() async {
    final userId = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    debugPrint('[ProfileCreation] _submitProfile: userId=$userId');
    if (userId == null) {
      debugPrint('[ProfileCreation] _submitProfile: no authenticated user — aborting.');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You must be signed in to create a profile.')));
      return;
    }
    final profileId =
        await ref.read(profileCreationProvider.notifier).submitProfile(userId);
    if (!mounted) return;
    if (profileId != null) {
      debugPrint('[ProfileCreation] _submitProfile: success (profileId=$profileId). '
          'Profile marked complete.');
      // The currently signed-in user's profile is now marked complete in
      // Firestore (profile_provider.submitProfile -> markProfileCompleted +
      // currentUserProvider invalidated). Refresh the auth-derived user too.
      ref.invalidate(authNotifierProvider);
      _showSuccessDialog();
    } else {
      final error = ref.read(profileCreationProvider).error;
      debugPrint('[ProfileCreation] _submitProfile: failed: $error');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error ?? 'Failed to create profile')));
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 72),
            const SizedBox(height: 16),
            Text('Profile Submitted!', style: AppTextStyles.heading2),
            const SizedBox(height: 8),
            Text(
              'Your profile is under review. We will notify you once it is approved.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/home');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continue', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creationState = ref.watch(profileCreationProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode
            ? 'Edit Profile · ${_stepTitles[_currentStep]}'
            : _stepTitles[_currentStep]),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: _currentStep > 0
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _prevStep)
            : null,
      ),
      body: Column(
        children: [
          // Progress bar
          Container(
            color: AppColors.primary.withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Step ${_currentStep + 1} of $_totalSteps',
                        style: AppTextStyles.bodySmall),
                    Text('${((_currentStep + 1) / _totalSteps * 100).round()}% Complete',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (_currentStep + 1) / _totalSteps,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
          ),
          // Steps
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                Step1WhoAreYou(onNext: _nextStep),
                Step2PersonalDetails(onNext: _nextStep),
                Step3Horoscope(onNext: _nextStep),
                Step4Family(onNext: _nextStep),
                Step5PartnerPrefs(onNext: _nextStep),
                Step6Photos(onNext: _nextStep),
                Step7Contact(
                  onNext: _nextStep,
                  isLoading: creationState.isLoading,
                  uploadProgress: creationState.uploadProgress,
                  uploadStatus: creationState.uploadStatus,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
