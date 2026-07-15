import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import 'steps/step_basic.dart';
import 'steps/step_location.dart';
import 'steps/step_education.dart';
import 'steps/step_religious.dart';
import 'steps/step3_horoscope.dart';
import 'steps/step_partner_preference.dart';
import 'steps/step6_photos.dart';
import 'steps/step_horoscope_upload.dart';
import 'steps/step7_contact.dart';
import 'steps/step_review.dart';

/// Multi-step onboarding wizard (12 steps incl. the success screen).
///
/// Each input step is a focused page so the form never feels overwhelming.
/// Required fields are validated per step. Progress is auto-saved as a draft
/// so a signed-out user can resume on the next sign-in. There is NO
/// "Save & Exit" — navigation is Next/Continue only, with a Skip action on
/// the OPTIONAL sections (About Me / Lifestyle, Partner Preference).
///
/// EDIT MODE ([editProfileId] non-null, opened via Menu → Profile → Edit
/// Profile): the wizard is seeded with the EXISTING profile so every field —
/// personal details, horoscope, location, education, occupation, photo,
/// Aadhaar, partner preferences — is editable, and submitting UPDATES the
/// same document in place (never a duplicate).
class ProfileCreationScreen extends ConsumerStatefulWidget {
  /// When non-null, the wizard was opened to edit an existing profile via
  /// Profile → "Edit Profile" (route `/profile/:id/edit`).
  final String? editProfileId;
  const ProfileCreationScreen({super.key, this.editProfileId});

  @override
  ConsumerState<ProfileCreationScreen> createState() =>
      _ProfileCreationScreenState();
}

class _ProfileCreationScreenState extends ConsumerState<ProfileCreationScreen> {
  static const String _draftKey = 'profile_draft_v1';
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _ready = false; // draft/profile loaded → safe to build steps that prefill

  bool get _isEditMode => widget.editProfileId != null;

  static const int _totalSteps = 10;

  /// Steps the user may SKIP — only the optional sections, matching the website
  /// (Partner Preferences, Photos, Upload Horoscope). Mandatory steps never
  /// show Skip.
  static const Set<int> _skippableSteps = {5, 6, 7};

  /// The 10 website profile-creation steps, in the same order as the website.
  final List<String> _stepTitles = const [
    'Basic Details',
    'Location',
    'Career',
    'Community',
    'Horoscope',
    'Partner Preferences',
    'Photos',
    'Upload Horoscope',
    'Contact',
    'Review',
  ];

  @override
  void initState() {
    super.initState();
    _prepareThenReady();
  }

  /// CREATE mode → restore the local draft. EDIT mode → seed the wizard with
  /// the EXISTING profile (flattened via toWizardData) so every step shows
  /// the current values and saving updates in place.
  Future<void> _prepareThenReady() async {
    // Always start from a clean slate — a previous edit/creation session must
    // never leak values into this one.
    ref.read(profileCreationProvider.notifier).reset();
    if (_isEditMode) {
      try {
        final profile = await ref
            .read(profileRepositoryProvider)
            .getProfile(widget.editProfileId!);
        if (profile != null) {
          ref
              .read(profileCreationProvider.notifier)
              .updateData(profile.toWizardData());
        }
      } catch (e) {
        debugPrint('[ProfileCreation] edit prefill failed: $e');
      }
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_draftKey);
        if (raw != null) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          if (map.isNotEmpty) {
            ref.read(profileCreationProvider.notifier).updateData(map);
          }
        }
      } catch (e) {
        debugPrint('[ProfileCreation] draft restore failed: $e');
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _saveDraft() async {
    if (_isEditMode) return;
    try {
      final data = ref.read(profileCreationProvider).data;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, jsonEncode(data));
    } catch (e) {
      debugPrint('[ProfileCreation] draft save failed: $e');
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    _saveDraft();
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

  /// Jump directly to [step] — used by the Review step's "Edit" actions.
  void _goToStep(int step) {
    if (step < 0 || step >= _totalSteps) return;
    setState(() => _currentStep = step);
    _pageController.animateToPage(step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout'),
        content: const Text(
            'Are you sure you want to logout? Unsaved progress will be kept as '
            'a draft.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (shouldLogout == true) {
      await _saveDraft();
      await ref.read(authNotifierProvider.notifier).signOut();
      if (!mounted) return;
      context.go('/login');
    }
  }

  Future<void> _submitProfile() async {
    final userId = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You must be signed in to create a profile.')));
      return;
    }
    final profileId = await ref
        .read(profileCreationProvider.notifier)
        .submitProfile(userId, editProfileId: widget.editProfileId);
    if (!mounted) return;
    if (profileId != null) {
      if (_isEditMode) {
        // Updated in place — the live profile stream refreshes everything.
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully.')));
        context.pop();
        return;
      }
      await _clearDraft();
      // Profile is now complete in Firestore; refresh the auth/profile state so
      // the gate opens and the Success screen reads the fresh completion %.
      ref.invalidate(authNotifierProvider);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      context.go('/profile/success');
    } else {
      final error = ref.read(profileCreationProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Failed to create profile')));
    }
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
        automaticallyImplyLeading: false,
        // Back button once past the first step; otherwise Logout (registration)
        // or Close (edit mode).
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: _prevStep)
            : _isEditMode
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => context.pop())
                : IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Logout',
                    onPressed: _confirmLogout,
                  ),
        // No "Save & Exit" (removed per spec) — only a Skip action on the
        // OPTIONAL sections, plus the submit spinner.
        actions: [
          if (creationState.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
              ),
            )
          else if (_skippableSteps.contains(_currentStep))
            TextButton(
              onPressed: _nextStep,
              child: const Text('Skip',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
            ),
        ],
      ),
      body: !_ready
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                // Progress bar
                Container(
                  color: AppColors.primary.withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Step ${_currentStep + 1} of $_totalSteps',
                              style: AppTextStyles.bodySmall),
                          Text(
                              '${((_currentStep + 1) / _totalSteps * 100).round()}% Complete',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.primary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (_currentStep + 1) / _totalSteps,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
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
                      StepBasic(onNext: _nextStep),
                      StepLocation(onNext: _nextStep),
                      StepEducation(onNext: _nextStep),
                      StepReligious(onNext: _nextStep),
                      Step3Horoscope(onNext: _nextStep),
                      StepPartnerPreference(onNext: _nextStep),
                      Step6Photos(onNext: _nextStep),
                      StepHoroscopeUpload(onNext: _nextStep),
                      Step7Contact(onNext: _nextStep),
                      StepReview(
                        onSubmit: _nextStep,
                        onEditStep: _goToStep,
                        isEditMode: _isEditMode,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
