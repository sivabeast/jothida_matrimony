import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/l10n_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/admin_account_service.dart';
import '../../widgets/profile/share_login_details_dialog.dart';
import 'steps/step_basic.dart';
import 'steps/step_location.dart';
import 'steps/step_education.dart';
import 'steps/step_lifestyle.dart';
import 'steps/step_religious.dart';
import 'steps/step3_horoscope.dart';
import 'steps/step_partner_preference.dart';
import 'steps/step6_photos.dart';
import 'steps/step_horoscope_upload.dart';
import 'steps/step7_contact.dart';
import 'steps/step_login_credentials.dart';
import 'steps/step_review.dart';

/// Multi-step onboarding wizard (13 steps incl. the success screen).
///
/// Each input step is a focused page so the form never feels overwhelming.
/// Required fields are validated per step. Progress is auto-saved as a draft
/// so a signed-out user can resume on the next sign-in. There is NO
/// "Save & Exit" — navigation is Next/Continue only.
///
/// The OPTIONAL sections (Lifestyle, Photos, Upload Horoscope) carry their Skip
/// where the member is already looking: a full-width **Skip** button directly
/// under **Continue**, at the bottom of the page. There is no Skip in the app
/// bar — a destructive-looking action tucked into the header is easy to hit by
/// accident and easy to miss when you actually want it.
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

  /// SECTION-EDIT mode (My Profile → a category's Edit action, route
  /// `/profile/:id/edit-section/:step`): shows ONLY this one step — no
  /// progress bar, no step list — and the step's Continue button saves the
  /// whole profile in place (only that section's values changed) and pops.
  /// Requires [editProfileId].
  final int? sectionStep;

  /// ADMIN mode (route `/admin/create-profile`): the admin fills in the SAME
  /// wizard on a member's behalf, then a final "Login Credentials" step creates
  /// the member's login. Nothing about the form, validation or structure
  /// changes — this is one shared profile-creation flow, not a second one.
  final bool adminMode;

  /// Whose profile this is. Normally null — the signed-in member is editing
  /// their own profile — but the ADMIN editor (`/admin/user/:uid/edit`) passes
  /// the MEMBER's uid, because the save writes photos, the `userId` field and
  /// the gated contact record under the profile's owner, never under whoever
  /// happens to be signed in. Without it an admin edit would re-home the
  /// profile onto the admin's own account.
  final String? ownerUserId;

  const ProfileCreationScreen({
    super.key,
    this.editProfileId,
    this.sectionStep,
    this.adminMode = false,
    this.ownerUserId,
  });

  @override
  ConsumerState<ProfileCreationScreen> createState() =>
      _ProfileCreationScreenState();
}

class _ProfileCreationScreenState extends ConsumerState<ProfileCreationScreen> {
  static const String _draftKey = 'profile_draft_v1';
  late final PageController _pageController =
      PageController(initialPage: _currentStep);
  late int _currentStep = widget.sectionStep?.clamp(0, _totalSteps - 1) ?? 0;
  bool _ready = false; // draft/profile loaded → safe to build steps that prefill

  /// True while the member's Firebase Auth account is being created (admin
  /// mode). Keeps the app-bar spinner up across that step too.
  bool _provisioning = false;

  bool get _isEditMode => widget.editProfileId != null;

  /// Single-section editing (from My Profile). Implies [_isEditMode].
  bool get _isSectionMode => _isEditMode && widget.sectionStep != null;

  /// Admin-on-behalf creation — adds ONE extra step (Login Credentials) at the
  /// very end. Never combined with edit/section mode.
  bool get _isAdminMode => widget.adminMode && !_isEditMode;

  /// The 11 shared profile steps, plus the admin-only Login Credentials step.
  static const int _memberSteps = 11;
  int get _totalSteps => _isAdminMode ? _memberSteps + 1 : _memberSteps;

  /// The 11 profile-creation steps, in wizard order.
  /// Titles are ALWAYS read from the l10n dictionary so they follow the
  /// selected language — there is no English fallback list.
  List<String> _stepTitles(BuildContext context) {
    final l = context.l10n;
    return [
      l.basicDetails,
      l.location,
      l.career,
      l.community,
      l.horoscope,
      l.lifestyleDetails,
      l.partnerPreferences,
      l.photos,
      l.uploadHoroscope,
      l.contact,
      l.review,
      if (_isAdminMode) l.loginCredentials,
    ];
  }

  @override
  void initState() {
    super.initState();
    _prepareThenReady();
  }

  /// CREATE mode → restore the local draft. EDIT mode → seed the wizard with
  /// the EXISTING profile (flattened via toWizardData) so every step shows
  /// the current values and saving updates in place.
  Future<void> _prepareThenReady() async {
    // The loading indicator (`_ready == false`) MUST always be dismissed once
    // initialization finishes — every path clears it in `finally`, so the
    // wizard can never get stuck in an infinite loading state.
    try {
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
            // Contact lives in the access-gated `contacts/{uid}` record, NOT
            // on the public profile doc — seed it separately so the Contact
            // step shows the saved values (and a save can never blank them).
            try {
              final contact = await ref
                  .read(firestoreServiceProvider)
                  .getContact(profile.userId);
              if (contact != null) {
                ref.read(profileCreationProvider.notifier).updateData({
                  'contactDetails': contact.toMap(),
                });
              }
            } catch (e) {
              debugPrint('[ProfileCreation] contact prefill skipped: $e');
            }
          }
        } catch (e) {
          debugPrint('[ProfileCreation] edit prefill failed: $e');
        }
      } else if (!_isAdminMode) {
        // Admin mode always starts blank: the admin's OWN abandoned draft must
        // never leak into a profile they are creating for someone else.
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
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _saveDraft() async {
    // Never persist an edit, and never persist a profile the admin is creating
    // for someone else (it would resurface as the admin's own draft).
    if (_isEditMode || _isAdminMode) return;
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
    // Section mode: the one step's Continue saves the profile immediately —
    // there is no next page.
    if (_isSectionMode) {
      _submitProfile();
      return;
    }
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

  /// Skipping an optional step is simply "move on without saving anything".
  /// Null in section-edit mode, which hides the Skip button entirely.
  VoidCallback? get _skipAction => _isSectionMode ? null : _nextStep;

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
        title: Text(context.l10n.logout),
        content: Text(context.l10n.logoutDraftMessage),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: Text(context.l10n.logout),
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

  /// ADMIN mode save: provision the member's login FIRST, then write the very
  /// same profile the member would have created themselves — under the new
  /// member's uid, so it is genuinely THEIR profile and they are never asked to
  /// create one again.
  ///
  /// The account is created before the profile deliberately: if account
  /// creation fails (duplicate mobile/e-mail, weak password) nothing is written
  /// at all, so a half-created member can't be left behind.
  Future<void> _submitAsAdmin() async {
    final l10n = context.l10n;
    final data = ref.read(profileCreationProvider).data;
    final creds = data['loginCredentials'];
    if (creds is! Map) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.loginCredentials)));
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _provisioning = true);
    final ProvisionedAccount account;
    try {
      account = await AdminAccountService().provisionMemberAccount(
        name: (data['name'] ?? '').toString().trim(),
        mobile: (creds['mobile'] ?? '').toString(),
        email: (creds['email'] ?? '').toString(),
        password: (creds['password'] ?? '').toString(),
        gender: (data['gender'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('[ProfileCreation] admin account provisioning failed: $e');
      if (!mounted) return;
      setState(() => _provisioning = false);
      final message = e is AuthException ? e.message : e.toString();
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!mounted) return;
    setState(() => _provisioning = false);

    // Same submit path as a member creating their own profile — one shared
    // flow, one shared validation, one shared document shape.
    final profileId = await ref
        .read(profileCreationProvider.notifier)
        .submitProfile(account.uid, adminCreated: true);
    if (!mounted) return;
    if (profileId == null) {
      final error = ref.read(profileCreationProvider).error;
      messenger.showSnackBar(SnackBar(
          content: Text(error ?? context.l10n.failedToCreateProfile)));
      return;
    }
    await _clearDraft();
    // Audit trail (best-effort): profile created by admin + credentials
    // handed over.
    unawaited(ref.read(firestoreServiceProvider).logAdminAction(
          adminUid:
              ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '',
          action: 'profile_created',
          targetUid: account.uid,
          targetProfileId: profileId,
          details: 'Admin-created member (mobile ${account.mobile})',
        ));
    if (!mounted) return;
    messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.profileCreatedForMember)));
    // Hand the member their login — including the one-tap WhatsApp share.
    await showShareLoginDetailsDialog(
      context,
      memberName: (data['name'] ?? '').toString().trim(),
      mobile: account.mobile,
      email: account.email,
      password: (creds['password'] ?? '').toString(),
    );
    unawaited(ref.read(firestoreServiceProvider).logAdminAction(
          adminUid:
              ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '',
          action: 'credentials_shared',
          targetUid: account.uid,
          details: 'Login details dialog shown (WhatsApp share offered)',
        ));
    if (!mounted) return;
    context.pop();
  }

  Future<void> _submitProfile() async {
    if (_isAdminMode) {
      await _submitAsAdmin();
      return;
    }
    // The profile's OWNER, not the signed-in account: an admin editing a
    // member's profile must keep writing it under that member's uid.
    final userId = widget.ownerUserId?.trim().isNotEmpty == true
        ? widget.ownerUserId!.trim()
        : ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.mustBeSignedInToCreateProfile)));
      return;
    }
    final profileId = await ref
        .read(profileCreationProvider.notifier)
        .submitProfile(userId, editProfileId: widget.editProfileId);
    if (!mounted) return;
    if (profileId != null) {
      if (_isEditMode) {
        // An ADMIN edit (ownerUserId set, and it is not the admin's own
        // profile) tells the member their profile changed — the same
        // best-effort notification the old admin-only editor sent.
        final signedInUid =
            ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
        if (userId != signedInUid) {
          unawaited(ref
              .read(notificationNotifierProvider.notifier)
              .notify(
                toUid: userId,
                event: AppNotificationEvent.adminProfileUpdate,
              )
              .catchError((Object e) => debugPrint(
                  '[ProfileCreation] admin update notice skipped: $e')));
        }
        // Updated in place — the live profile stream refreshes everything.
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.profileUpdatedSuccess)));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error ?? context.l10n.failedToCreateProfile)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final creationState = ref.watch(profileCreationProvider);

    final steps = <Widget>[
      StepBasic(onNext: _nextStep),
      StepLocation(onNext: _nextStep),
      StepEducation(onNext: _nextStep),
      StepReligious(onNext: _nextStep),
      Step3Horoscope(onNext: _nextStep),
      // Lifestyle — fully OPTIONAL (no validation, and skippable). The three
      // optional steps render their own Continue + Skip pair at the bottom;
      // `onSkip` is null in section-edit mode, where there is nothing to skip
      // to.
      StepLifestyle(onNext: _nextStep, onSkip: _skipAction),
      StepPartnerPreference(onNext: _nextStep),
      Step6Photos(onNext: _nextStep, onSkip: _skipAction),
      StepHoroscopeUpload(onNext: _nextStep, onSkip: _skipAction),
      Step7Contact(onNext: _nextStep),
      StepReview(
        onSubmit: _nextStep,
        onEditStep: _goToStep,
        isEditMode: _isEditMode,
      ),
      // Admin only — the final Login Credentials step, which is what actually
      // triggers the save (account + profile) in that mode.
      if (_isAdminMode) StepLoginCredentials(onNext: _nextStep),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSectionMode
            ? context.l10n.editSection(_stepTitles(context)[_currentStep])
            : _isEditMode
                ? context.l10n
                    .editProfileSection(_stepTitles(context)[_currentStep])
                : _stepTitles(context)[_currentStep]),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        // Section mode: always a Close action. Otherwise: Back once past the
        // first step, else Logout (registration) or Close (edit mode).
        leading: _isSectionMode
            ? IconButton(
                icon: const Icon(Icons.close), onPressed: () => context.pop())
            : _currentStep > 0
                ? IconButton(
                    icon: const Icon(Icons.arrow_back), onPressed: _prevStep)
                : (_isEditMode || _isAdminMode)
                    // Admin mode is a normal admin page — closing it just
                    // leaves; it must never sign the admin out.
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => context.pop())
                    : IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: context.l10n.logout,
                        onPressed: _confirmLogout,
                      ),
        // No "Save & Exit" and no Skip: the only thing the app bar carries is
        // the submit spinner. Skip lives at the bottom of the optional steps,
        // beneath Continue.
        actions: [
          if (creationState.isLoading || _provisioning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
              ),
            ),
        ],
      ),
      body: !_ready
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _isSectionMode
              // Single-section editor: just the one step, no progress chrome.
              ? steps[_currentStep]
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
                              Text(
                                  context.l10n.stepXofY(
                                      _currentStep + 1, _totalSteps),
                                  style: AppTextStyles.bodySmall),
                              Text(
                                  context.l10n.percentComplete(
                                      ((_currentStep + 1) / _totalSteps * 100)
                                          .round()),
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
                        children: steps,
                      ),
                    ),
                  ],
                ),
    );
  }
}
