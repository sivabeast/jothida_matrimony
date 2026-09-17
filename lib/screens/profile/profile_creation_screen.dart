import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/login_identifier.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/admin_account_service.dart';
import '../../widgets/admin/login_conflict_dialog.dart';
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

  /// ADMIN creates the profile for an EXISTING account that has none
  /// (`/admin/user/:uid/create-profile`, spec "Profile Not Created"). Uses the
  /// member's own Firebase UID from [ownerUserId]: no login step, no second
  /// account, and the ownership record keeps it to one profile.
  final bool adminForMember;

  const ProfileCreationScreen({
    super.key,
    this.editProfileId,
    this.sectionStep,
    this.adminMode = false,
    this.ownerUserId,
    this.adminForMember = false,
  });

  @override
  ConsumerState<ProfileCreationScreen> createState() =>
      _ProfileCreationScreenState();
}

class _ProfileCreationScreenState extends ConsumerState<ProfileCreationScreen> {
  static const String _draftKey = 'profile_draft_v1';

  /// Path of the draft's chosen photo (a file cannot live in the JSON draft).
  static const String _draftPhotoKey = 'profile_draft_photo_v1';
  late final PageController _pageController =
      PageController(initialPage: _currentStep);
  late int _currentStep = widget.sectionStep?.clamp(0, _totalSteps - 1) ?? 0;
  bool _ready = false; // draft/profile loaded → safe to build steps that prefill

  /// EDIT mode only: the existing profile could not be loaded, so the form
  /// must not be offered — saving it would blank the stored data.
  bool _prefillFailed = false;

  /// True while the member's Firebase Auth account is being created (admin
  /// mode). Keeps the app-bar spinner up across that step too.
  bool _provisioning = false;

  bool get _isEditMode => widget.editProfileId != null;

  /// Single-section editing (from My Profile). Implies [_isEditMode].
  bool get _isSectionMode => _isEditMode && widget.sectionStep != null;

  /// Admin-on-behalf creation — adds ONE extra step (Login Credentials) at the
  /// very end. Never combined with edit/section mode.
  bool get _isAdminMode => widget.adminMode && !_isEditMode;

  /// Admin completing the profile of an existing account (see
  /// [ProfileCreationScreen.adminForMember]).
  bool get _isAdminForMember =>
      widget.adminForMember &&
      !_isEditMode &&
      (widget.ownerUserId ?? '').trim().isNotEmpty;

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
    // After the first frame: preparing resets the shared wizard provider, and
    // a provider must not be modified while the tree is building — which is
    // exactly when this screen is mounted (e.g. the admin editor swaps it in
    // once the member's profile has been found). The spinner covers the gap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prepareThenReady();
    });
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
        _prefillFailed = false;
        try {
          // The FULL profile — a hidden photo / salary / horoscope lives in
          // the private copy, and seeding the wizard without it would save
          // blanks over the member's real values.
          final profile = await ref
              .read(profileRepositoryProvider)
              .getFullProfile(widget.editProfileId!,
                  ownerUid: widget.ownerUserId);
          if (profile == null) {
            _prefillFailed = true;
          } else {
            ref
                .read(profileCreationProvider.notifier)
                .updateData(profile.toWizardData());
            // Contact lives in the access-gated `contacts/{uid}` record, NOT
            // on the public profile doc — seed it separately so the Contact
            // step shows the saved values (and a save can never blank them).
            try {
              // The OWNER's record — for an admin edit that is the member,
              // even when the document's own userId is blank.
              final ownerUid = widget.ownerUserId?.trim().isNotEmpty == true
                  ? widget.ownerUserId!.trim()
                  : profile.userId;
              final contact = await ref
                  .read(firestoreServiceProvider)
                  .getFullContact(ownerUid);
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
          // FAIL CLOSED. An edit saves the WHOLE profile, so continuing with an
          // empty form would overwrite the stored photo and horoscope document
          // URLs with blanks — the uploads stay in Cloudinary but the profile
          // loses every reference to them. The form is not shown until the
          // current profile has actually loaded.
          debugPrint('[ProfileCreation] edit prefill failed: $e');
          _prefillFailed = true;
        }
      } else if (_isAdminForMember) {
        await _seedFromMemberAccount(widget.ownerUserId!.trim());
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
          // The chosen photo is a FILE, which the JSON draft above cannot
          // hold — without this a resumed draft silently lost it and the
          // profile was created with no photo.
          final photoPath = prefs.getString(_draftPhotoKey);
          if (photoPath != null && await File(photoPath).exists()) {
            ref
                .read(profileCreationProvider.notifier)
                .setPhotos([File(photoPath)]);
            debugPrint('[ProfileCreation] draft photo restored: $photoPath');
          }
        } catch (e) {
          debugPrint('[ProfileCreation] draft restore failed: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  /// Pre-fills what the member already gave at registration — name, gender,
  /// date of birth, mobile, e-mail — so the admin completes their details
  /// rather than retyping (and possibly contradicting) them.
  Future<void> _seedFromMemberAccount(String uid) async {
    try {
      final raw = await ref.read(firestoreServiceProvider).getRawUser(uid);
      if (raw == null) return;
      String str(Object? v) => '${v ?? ''}'.trim();
      final dob = raw['dateOfBirth'];
      final email = str(raw['email']);
      ref.read(profileCreationProvider.notifier).updateData({
        if (str(raw['displayName']).isNotEmpty) 'name': str(raw['displayName']),
        if (str(raw['gender']).isNotEmpty) 'gender': str(raw['gender']),
        if (dob is Timestamp) 'dateOfBirth': dob.toDate().toIso8601String(),
        'contactDetails': {
          'mobileNumber':
              LoginIdentifier.localMobile(str(raw['phone'])) ?? str(raw['phone']),
          'email': LoginIdentifier.realEmailOrEmpty(email),
        },
      });
    } catch (e) {
      debugPrint('[ProfileCreation] member account prefill skipped: $e');
    }
  }

  Future<void> _saveDraft() async {
    // Never persist an edit, and never persist a profile the admin is creating
    // for someone else (it would resurface as the admin's own draft).
    if (_isEditMode || _isAdminMode || _isAdminForMember) return;
    try {
      final state = ref.read(profileCreationProvider);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, jsonEncode(state.data));
      await _saveDraftPhoto(prefs, state.photos);
    } catch (e) {
      debugPrint('[ProfileCreation] draft save failed: $e');
    }
  }

  /// Keeps the chosen (cropped) photo with the draft. The crop screen writes
  /// to the TEMP directory, which the OS may empty, so the file is copied once
  /// into app storage and the draft remembers that path.
  Future<void> _saveDraftPhoto(
      SharedPreferences prefs, List<File> photos) async {
    final previous = prefs.getString(_draftPhotoKey);
    if (photos.isEmpty) {
      await prefs.remove(_draftPhotoKey);
      if (previous != null) await _deleteQuietly(previous);
      return;
    }
    final file = photos.first;
    final dir = await getApplicationSupportDirectory();
    var path = file.path;
    if (!path.startsWith(dir.path)) {
      final copy = await file.copy('${dir.path}${Platform.pathSeparator}'
          'profile_draft_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
      path = copy.path;
      ref.read(profileCreationProvider.notifier).setPhotos([copy]);
    }
    if (previous != null && previous != path) await _deleteQuietly(previous);
    await prefs.setString(_draftPhotoKey, path);
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      final photo = prefs.getString(_draftPhotoKey);
      await prefs.remove(_draftPhotoKey);
      // Only cleared after a successful submit — the photo is uploaded by then.
      if (photo != null) await _deleteQuietly(photo);
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

  /// ADMIN mode save: resolve the member's LOGIN first, then write the very
  /// same profile the member would have created themselves — under that
  /// member's uid, so it is genuinely THEIR profile and they are never asked to
  /// create one again.
  ///
  /// The login is resolved before the profile deliberately: if it cannot be
  /// created (duplicate, weak password, an old login still holding the number)
  /// nothing is written at all. A conflict is never a dead end — the admin is
  /// shown the account that holds the number and decides (see
  /// [showLoginConflictDialog]). "Use existing account" writes the profile
  /// under THAT uid and creates no login at all.
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
    final firestore = ref.read(firestoreServiceProvider);
    setState(() => _provisioning = true);
    final ({String uid, ProvisionedAccount? account})? target;
    try {
      target = await _resolveMemberLogin(data, creds);
    } catch (e) {
      debugPrint('[ProfileCreation] admin account provisioning failed: $e');
      if (!mounted) return;
      setState(() => _provisioning = false);
      final message = e is AuthException
          ? e.message
          : e is LoginConflictException
              ? e.message
              : e.toString();
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!mounted) return;
    setState(() => _provisioning = false);
    if (target == null) return; // the admin cancelled

    // Never a second profile for an account that already has one.
    if (target.account == null || target.account!.restored) {
      try {
        final existing = await firestore.profilesOfUser(target.uid);
        if (existing.isNotEmpty) {
          if (!mounted) return;
          messenger.showSnackBar(const SnackBar(
              content: Text('That account already has a matrimony profile — '
                  'opening it instead of creating another.')));
          context.pushReplacement('/admin/user/${target.uid}');
          return;
        }
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
            content: Text('Could not check the existing account ($e).')));
        return;
      }
    }

    // Same submit path as a member creating their own profile — one shared
    // flow, one shared validation, one shared document shape.
    final profileId = await ref
        .read(profileCreationProvider.notifier)
        .submitProfile(target.uid, adminCreated: true);
    if (!mounted) return;
    final account = target.account;
    if (profileId == null) {
      // A NEW login was provisioned as "profile complete" — only true when the
      // profile actually landed — so put it back, or the member signs in and
      // is dropped onto a Home page with no profile behind it (spec §21/§28).
      if (account != null && !account.restored) {
        try {
          await firestore.updateUser(account.uid,
              {'isProfileComplete': false, 'profileCompleted': false});
        } catch (e) {
          debugPrint('[ProfileCreation] could not reset the profile-complete '
              'flag for ${account.uid}: $e');
        }
      }
      final error = ref.read(profileCreationProvider).error;
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(error ?? context.l10n.failedToCreateProfile)));
      return;
    }
    await _clearDraft();
    final adminUid =
        ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
    unawaited(firestore.logAdminAction(
      adminUid: adminUid,
      action: account == null
          ? 'profile_created_for_existing_account'
          : 'profile_created',
      targetUid: target.uid,
      targetProfileId: profileId,
      details: account == null
          ? 'Linked to the existing login (no new account created)'
          : 'Admin-created member (mobile ${account.mobile}'
              '${account.restored ? ', existing login re-used' : ''})',
    ));
    if (!mounted) return;
    messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.profileCreatedForMember)));
    if (account != null) {
      // Hand the member their login — including the one-tap WhatsApp share.
      await showShareLoginDetailsDialog(
        context,
        memberName: (data['name'] ?? '').toString().trim(),
        mobile: account.mobile,
        email: account.email,
        password: (creds['password'] ?? '').toString(),
      );
      unawaited(firestore.logAdminAction(
        adminUid: adminUid,
        action: 'credentials_shared',
        targetUid: account.uid,
        details: 'Login details dialog shown (WhatsApp share offered)',
      ));
    }
    if (!mounted) return;
    context.pop();
  }

  /// The uid the admin's new profile belongs to: a freshly provisioned login,
  /// an existing account the admin chose to use, or a leftover login verified
  /// with its password. Null when the admin cancelled.
  Future<({String uid, ProvisionedAccount? account})?> _resolveMemberLogin(
      Map<String, dynamic> data, Map creds) async {
    final linkUid = '${creds['linkExistingUid'] ?? ''}'.trim();
    if (linkUid.isNotEmpty) return (uid: linkUid, account: null);

    final service = ref.read(adminAccountServiceProvider);
    final name = (data['name'] ?? '').toString().trim();
    final mobile = (creds['mobile'] ?? '').toString();
    final email = (creds['email'] ?? '').toString();
    final password = (creds['password'] ?? '').toString();
    final gender = (data['gender'] ?? '').toString();
    var releaseStaleIndex = creds['releaseStaleIndex'] == true;
    var replaceOrphanUid = '${creds['replaceOrphanUid'] ?? ''}';

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final account = await service.provisionMemberAccount(
          name: name,
          mobile: mobile,
          email: email,
          password: password,
          gender: gender,
          releaseStaleIndex: releaseStaleIndex,
          replaceOrphanUid: replaceOrphanUid,
        );
        return (uid: account.uid, account: account);
      } on LoginConflictException catch (conflict) {
        if (!mounted) return null;
        setState(() => _provisioning = false);
        final choice = await showLoginConflictDialog(context, conflict);
        if (!mounted) return null;
        setState(() => _provisioning = true);
        switch (choice) {
          case null:
            return null;
          case OpenExistingAccount(:final uid):
            context.push(
                uid.isEmpty ? '/admin/account-health' : '/admin/user/$uid');
            return null;
          case LinkExistingAccount(:final account):
            return (uid: account.uid, account: null);
          case CreateNewLogin(
              releaseStaleIndex: final release,
              replaceOrphanUid: final replace,
            ):
            releaseStaleIndex = releaseStaleIndex || release;
            if (replace.isNotEmpty) replaceOrphanUid = replace;
          case ReclaimWithPassword(:final currentPassword):
            final account = await service.reclaimWithCurrentPassword(
              name: name,
              mobile: mobile,
              email: email,
              currentPassword: currentPassword,
              newPassword: password,
              gender: gender,
            );
            return (uid: account.uid, account: account);
        }
      }
    }
    throw const AuthException(
        'The login could not be created. Open Account Health to review this '
        'number.',
        code: 'member-provisioning-failed');
  }

  /// Admin → a member with a login but NO profile → Create Profile. The
  /// profile is written under the member's existing uid; nothing about their
  /// login changes.
  Future<void> _submitForExistingMember() async {
    final uid = widget.ownerUserId!.trim();
    final messenger = ScaffoldMessenger.of(context);
    final firestore = ref.read(firestoreServiceProvider);
    try {
      final existing = await firestore.profilesOfUser(uid);
      if (existing.isNotEmpty) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(
            content: Text('This account already has a matrimony profile — '
                'nothing was created.')));
        context.pushReplacement('/admin/user/$uid');
        return;
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not check for an existing profile ($e).')));
      return;
    }
    final profileId = await ref
        .read(profileCreationProvider.notifier)
        .submitProfile(uid, adminCreated: true);
    if (!mounted) return;
    if (profileId == null) {
      final error = ref.read(profileCreationProvider).error;
      messenger.showSnackBar(SnackBar(
          content: Text(error ?? context.l10n.failedToCreateProfile)));
      return;
    }
    unawaited(firestore.logAdminAction(
      adminUid: ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '',
      action: 'profile_created_for_existing_account',
      targetUid: uid,
      targetProfileId: profileId,
      details: 'Admin completed the profile of an existing login',
    ));
    messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.profileCreatedForMember)));
    context.pop();
  }

  Future<void> _submitProfile() async {
    // Never save an edit whose current values were not loaded (see
    // [_prefillFailed]).
    if (_isEditMode && _prefillFailed) return;
    if (_isAdminMode) {
      await _submitAsAdmin();
      return;
    }
    if (_isAdminForMember) {
      await _submitForExistingMember();
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
                : (_isEditMode || _isAdminMode || _isAdminForMember)
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
          : (_isEditMode && _prefillFailed)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.l10n.couldNotLoadProfileRetry,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _ready = false);
                            _prepareThenReady();
                          },
                          icon: const Icon(Icons.refresh),
                          label: Text(context.l10n.tryAgain),
                        ),
                      ],
                    ),
                  ),
                )
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
