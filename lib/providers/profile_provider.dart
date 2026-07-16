import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart' show DocumentSnapshot;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../core/constants/app_constants.dart';
import '../core/services/porutham_match.dart';
import '../models/profile_model.dart';
import '../services/cloudinary/cloudinary_exception.dart';
import '../services/firebase/firestore_service.dart' show ProfilePage;
import 'demo_data_provider.dart';
import 'notification_provider.dart';
import 'service_providers.dart';
import 'auth_provider.dart';

// Current user's profile
final myProfileProvider = StreamProvider.autoDispose<ProfileModel?>((ref) {
  // Demo mode: serve the profile the user created locally (if any).
  if (kBypassAuth) {
    final id = ref.watch(myDemoProfileIdProvider);
    ref.watch(demoProfilesProvider); // stay reactive to store changes
    final mine =
        id == null ? null : ref.read(demoProfilesProvider.notifier).byId(id);
    return Stream.value(mine);
  }

  final authAsync = ref.watch(firebaseAuthStreamProvider);
  final userId = authAsync.valueOrNull?.uid;
  if (userId == null) return Stream.value(null);

  // LIVE snapshot stream (was a one-shot get() converted to a stream). Admin
  // edits to the profile document now reach the user app in real time —
  // no stale cache, no re-login needed.
  return ref.watch(profileRepositoryProvider).watchProfileByUserId(userId);
});

// Watch a specific profile by id
final profileByIdProvider =
    StreamProvider.autoDispose.family<ProfileModel?, String>((ref, profileId) {
  if (kBypassAuth) {
    ref.watch(demoProfilesProvider); // stay reactive
    return Stream.value(ref.read(demoProfilesProvider.notifier).byId(profileId));
  }
  return ref.watch(profileRepositoryProvider).watchProfile(profileId);
});

/// Look up another user's PUBLIC profile by their owner USER id (UID).
///
/// Prefer this over [profileByIdProvider] whenever a reliable UID is available
/// — e.g. an accepted interest's `senderId` / `receiverId`. The interest stores
/// the two users' UIDs, which always identify the right profile; a profile
/// *document* id copied into another record can be stale or missing, which is
/// why opening an accepted match by document id failed to load.
///
/// Uses [ProfileRepository.getApprovedProfileByUserId], which filters
/// userId + status == 'approved' + isActive — exactly mirroring the `profiles`
/// read rule's public path so the query is permitted (a userId-only query is
/// rejected with permission-denied for non-owners). An accepted match is, by
/// definition, an approved & active profile, so it resolves correctly.
final profileByUserIdProvider =
    FutureProvider.autoDispose.family<ProfileModel?, String>((ref, userId) {
  if (kBypassAuth) {
    final all = ref.watch(demoProfilesProvider); // stays reactive to the store
    for (final p in all) {
      if (p.userId == userId) return Future.value(p);
    }
    return Future.value(null);
  }
  return ref.watch(profileRepositoryProvider).getApprovedProfileByUserId(userId);
});

/// Another user's gated contact details, keyed by their USER id.
///
/// Resolves to the contact only when it is unlocked for the caller (owner /
/// admin / mutually-accepted connection). Otherwise the underlying Firestore
/// read is denied and this surfaces as an AsyncError, which the UI renders as
/// a "locked" state. Returns null in demo mode.
final contactByUserIdProvider =
    FutureProvider.autoDispose.family<ContactDetails?, String>((ref, userId) {
  if (kBypassAuth) return Future.value(null);
  return ref.watch(profileRepositoryProvider).getContact(userId);
});

// Profile creation / editing notifier
class ProfileCreationState {
  final Map<String, dynamic> data;
  final List<File> photos;
  final File? horoscopePdf;
  final bool isLoading;
  final String? error;
  final bool isComplete;

  /// Overall upload progress (0..1) across photos + horoscope PDF, while
  /// [isLoading] is true. Drives the progress bar on the final step.
  final double uploadProgress;

  /// Human-readable status shown under the progress bar, e.g.
  /// "Uploading photo 2 of 3...".
  final String? uploadStatus;

  const ProfileCreationState({
    this.data = const {},
    this.photos = const [],
    this.horoscopePdf,
    this.isLoading = false,
    this.error,
    this.isComplete = false,
    this.uploadProgress = 0,
    this.uploadStatus,
  });

  ProfileCreationState copyWith({
    Map<String, dynamic>? data,
    List<File>? photos,
    File? horoscopePdf,
    bool? isLoading,
    String? error,
    bool? isComplete,
    double? uploadProgress,
    String? uploadStatus,
  }) =>
      ProfileCreationState(
        data: data ?? this.data,
        photos: photos ?? this.photos,
        horoscopePdf: horoscopePdf ?? this.horoscopePdf,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isComplete: isComplete ?? this.isComplete,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        // `error` resets uploadStatus implicitly via copyWith below when null
        uploadStatus: uploadStatus,
      );
}

class ProfileCreationNotifier extends Notifier<ProfileCreationState> {
  @override
  ProfileCreationState build() => const ProfileCreationState();

  void updateData(Map<String, dynamic> partial) =>
      state = state.copyWith(data: {...state.data, ...partial});

  void setPhotos(List<File> photos) =>
      // Defensive copy: if the caller (Step6Photos) still holds a reference to
      // the same list and later modifies it (e.g. user navigates back and adds
      // or removes a photo), the provider state would be silently corrupted.
      state = state.copyWith(photos: List.unmodifiable(photos));

  void setHoroscopePdf(File pdf) => state = state.copyWith(horoscopePdf: pdf);

  /// Saves the wizard's data. CREATE mode (default) writes a brand-new
  /// profile; EDIT mode ([editProfileId] non-null) UPDATES the existing
  /// document in place — never a duplicate — keeping photos/PDF that weren't
  /// re-picked and preserving moderation fields (status, counters, verified).
  Future<String?> submitProfile(String userId, {String? editProfileId}) async {
    state = state.copyWith(isLoading: true, error: null, uploadProgress: 0, uploadStatus: null);

    // ── Demo mode: save the profile to the in-memory store, no backend ──
    if (kBypassAuth) {
      try {
        final id =
            editProfileId ?? 'me_${DateTime.now().millisecondsSinceEpoch}';
        final gender = (state.data['gender'] ?? 'Male').toString();
        // No upload available offline — use a placeholder portrait.
        final placeholder = gender == 'Female'
            ? 'https://randomuser.me/api/portraits/women/90.jpg'
            : 'https://randomuser.me/api/portraits/men/90.jpg';
        final profile = ProfileModel.fromMap({
          ...state.data,
          'id': id,
          'userId': userId,
          'photos': [placeholder],
          'status': 'approved', // visible immediately in demo
        }).copyWith(isActive: true, status: 'approved');

        ref.read(demoProfilesProvider.notifier).upsert(profile);
        ref.read(myDemoProfileIdProvider.notifier).state = id;
        state = state.copyWith(isLoading: false, isComplete: true);
        return id;
      } catch (e) {
        state = state.copyWith(isLoading: false, error: e.toString());
        return null;
      }
    }

    try {
      final repo = ref.read(profileRepositoryProvider);
      final hasPhotos = state.photos.isNotEmpty;
      final hasPdf = state.horoscopePdf != null;

      debugPrint(
        '[submitProfile] userId=$userId  '
        'photos=${state.photos.length}  hasPdf=$hasPdf',
      );

      // Validate that all photo files still exist on disk before we start.
      for (var i = 0; i < state.photos.length; i++) {
        final exists = await state.photos[i].exists();
        debugPrint(
          '[submitProfile] photo[$i] path=${state.photos[i].path}  exists=$exists',
        );
        if (!exists) {
          throw CloudinaryUploadException(
            'Photo file $i no longer exists at "${state.photos[i].path}". '
            'Please re-select your photo and try again.',
            isRetryable: false,
          );
        }
      }

      // Split overall progress (0..1) across the upload phases that apply.
      final photoWeight = hasPhotos ? (hasPdf ? 0.7 : 1.0) : 0.0;
      final pdfWeight = hasPdf ? (hasPhotos ? 0.3 : 1.0) : 0.0;

      List<String> photoUrls = [];
      if (hasPhotos) {
        state = state.copyWith(
          uploadStatus: state.photos.length == 1
              ? 'Uploading photo...'
              : 'Uploading ${state.photos.length} photos...',
        );
        debugPrint('[submitProfile] ▶ starting photo upload (${state.photos.length} file(s))');
        photoUrls = await repo.uploadPhotos(
          userId: userId,
          files: state.photos,
          onProgress: (p) => state = state.copyWith(uploadProgress: p * photoWeight),
        );
        debugPrint('[submitProfile] ✅ photo upload complete → urls: $photoUrls');
      } else {
        debugPrint('[submitProfile] ℹ no photos to upload');
      }

      String? pdfUrl;
      if (hasPdf) {
        state = state.copyWith(uploadStatus: 'Uploading horoscope PDF...');
        debugPrint('[submitProfile] ▶ starting PDF upload');
        pdfUrl = await repo.uploadHoroscopePdf(
          userId: userId,
          file: state.horoscopePdf!,
          onProgress: (p) =>
              state = state.copyWith(uploadProgress: photoWeight + p * pdfWeight),
        );
        debugPrint('[submitProfile] ✅ PDF upload complete → $pdfUrl');
      }

      state = state.copyWith(
        uploadStatus: 'Saving your profile...',
        uploadProgress: photoWeight + pdfWeight,
      );

      // In EDIT mode the existing photo URLs (seeded into the wizard data by
      // toWizardData) are kept when no new photo was picked.
      final existingPhotos = state.data['photos'] is List
          ? List<String>.from(
              (state.data['photos'] as List).map((e) => e.toString()))
          : const <String>[];

      final profileData = {
        ...state.data,
        'userId': userId,
        'photos': photoUrls.isNotEmpty ? photoUrls : existingPhotos,
        if (pdfUrl != null) 'horoscopeDetails.horoscopePdfUrl': pdfUrl,
        // Profiles are active immediately on completion — no admin approval
        // step. ('rejected'/'blocked' remain available for moderation only.)
        'status': 'approved',
        'isActive': true,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      };

      debugPrint('[submitProfile] ▶ building ProfileModel from map keys: ${profileData.keys.toList()}');
      final profile = ProfileModel.fromMap(profileData);
      final String profileId;
      if (editProfileId != null) {
        // ── EDIT: update the existing document IN PLACE — no duplicate. ──
        // Moderation/engagement fields are preserved (never reset by an edit).
        final map = profile.toFirestore()
          ..remove('createdAt')
          ..remove('status')
          ..remove('isActive')
          ..remove('isVerified')
          ..remove('isFeatured')
          ..remove('isMarried')
          ..remove('reportCount')
          ..remove('viewCount')
          ..remove('interestCount');
        debugPrint('[submitProfile] ▶ updating profile $editProfileId...');
        await repo.updateProfile(editProfileId, map);
        // Keep the gated contact record in sync with the edited details —
        // but ONLY when the wizard actually carries contact data, so editing
        // another section can never blank the saved contact record.
        if (profile.contact.mobileNumber.trim().isNotEmpty) {
          try {
            await ref
                .read(firestoreServiceProvider)
                .saveContact(userId, profile.contact);
          } catch (e) {
            debugPrint('[submitProfile] contact sync skipped: $e');
          }
        }
        profileId = editProfileId;
        debugPrint('[submitProfile] ✅ profile updated (id=$profileId)');
      } else {
        debugPrint('[submitProfile] ▶ writing profile to Firestore...');
        profileId = await repo.createProfile(profile);
        debugPrint('[submitProfile] ✅ Firestore profile created (id=$profileId)');

        // Mark the account as profile-completed so the Home gate opens.
        debugPrint('[submitProfile] ▶ marking profile completed for userId=$userId');
        await ref.read(firestoreServiceProvider).markProfileCompleted(userId);
        debugPrint('[submitProfile] ✅ markProfileCompleted done');
        // In-app "Profile Approved" notification — profiles go live immediately
        // on completion (best-effort; never fails the save).
        await ref.read(notificationNotifierProvider.notifier).notify(
              toUid: userId,
              event: AppNotificationEvent.profileApproved,
            );
      }

      ref.invalidate(currentUserProvider); // refresh the gate
      state = state.copyWith(
        isLoading: false,
        isComplete: true,
        uploadProgress: 1,
        uploadStatus: null,
      );
      return profileId;
    } catch (e, st) {
      debugPrint('[submitProfile] ❌ FAILED: $e\n$st');
      state = state.copyWith(
        isLoading: false,
        error: _friendlyProfileError(e),
        uploadProgress: 0,
        uploadStatus: null,
      );
      return null;
    }
  }

  void reset() => state = const ProfileCreationState();

  /// Turn raw upload/Firestore errors into actionable messages instead of
  /// dumping `e.toString()` (e.g. `[firebase_storage/object-not-found] No
  /// object exists at the desired reference.`) straight into a SnackBar.
  String _friendlyProfileError(Object e) {
    if (e is CloudinaryUploadException) {
      if (e.statusCode == 400 &&
          e.message.toLowerCase().contains('preset')) {
        return 'Could not upload your photo — the Cloudinary upload preset '
            '"matrimony_profiles" is missing or not set to "Unsigned". '
            'Check Cloudinary Console > Settings > Upload > Upload presets.';
      }
      if (e.statusCode == null) {
        return 'Could not upload your photo — check your internet '
            'connection and tap Submit to retry.';
      }
      return 'Could not upload your photo (${e.message}). Tap Submit to retry.';
    }
    if (e is FirebaseException && e.plugin == 'firebase_storage') {
      switch (e.code) {
        case 'object-not-found':
          return 'Could not save your photo — Cloud Storage may not be set '
              'up yet for this Firebase project. Enable Storage in the '
              'Firebase Console (Build > Storage > Get started), deploy '
              'storage.rules, and try again.';
        case 'unauthorized':
          return 'Could not save your photo — Storage security rules '
              'blocked the upload. Deploy storage.rules and try again.';
        case 'canceled':
          return 'Photo upload was cancelled. Please try again.';
        case 'retry-limit-exceeded':
          return 'Photo upload timed out. Check your connection and try again.';
        default:
          return 'Could not save your photo (${e.code}). Please try again.';
      }
    }
    if (e is FirebaseException) {
      return 'Could not save your profile (${e.plugin}/${e.code}): '
          '${e.message ?? 'unknown error'}.';
    }
    return 'Something went wrong while saving your profile: $e';
  }
}

final profileCreationProvider =
    NotifierProvider<ProfileCreationNotifier, ProfileCreationState>(() => ProfileCreationNotifier());

/// Gender of profiles to show on Discover, derived automatically from the
/// signed-in user's own gender (opposite-gender matching). No manual toggle.
///
/// Sources, in priority order: the user's matrimony profile → the `users/{uid}`
/// account document (gender is collected at signup). Defaults to showing
/// Female profiles until the gender is known.
final matchGenderProvider = Provider.autoDispose<String>((ref) {
  final myGender = ref.watch(myProfileProvider).valueOrNull?.gender ??
      ref.watch(currentUserProvider).valueOrNull?.gender;
  return myGender == 'Female' ? 'Male' : 'Female';
});

// ── Discover / Matches feed ────────────────────────────────────────────────
//
// MATCHING RULE: gender (opposite gender) is always applied first. On top of
// that the user may apply OPTIONAL [MatchFilters] — every field is nullable and
// an unset field is ignored. Horoscope compatibility is also exposed as an
// informational badge that never removes a profile (only the explicit
// match-quality filter can).
const int _kDiscoverPageSize = 20;

/// Optional, user-chosen Matches filters. Every field is nullable; a `null`
/// field means "ignore this filter". Applied client-side AFTER the gender
/// restriction, so any combination (none / one / all) works.
class MatchFilters {
  final int? minAge;
  final int? maxAge;
  final String? state;
  final String? district;
  final String? city;
  final String? religion;
  final String? caste;
  final String? education;
  final String? occupation;
  final String? maritalStatus;
  final String? rasi;
  final String? nakshatra;

  const MatchFilters({
    this.minAge,
    this.maxAge,
    this.state,
    this.district,
    this.city,
    this.religion,
    this.caste,
    this.education,
    this.occupation,
    this.maritalStatus,
    this.rasi,
    this.nakshatra,
  });

  bool get isActive =>
      minAge != null ||
      maxAge != null ||
      _has(state) ||
      _has(district) ||
      _has(city) ||
      _has(religion) ||
      _has(caste) ||
      _has(education) ||
      _has(occupation) ||
      _has(maritalStatus) ||
      _has(rasi) ||
      _has(nakshatra);

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;
  static bool _eq(String a, String? b) =>
      b == null || b.trim().isEmpty || a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Whether [p] passes every SET filter. [me] is accepted for signature
  /// compatibility with callers but no longer needed (the porutham-grade
  /// filter was removed with the rating system).
  bool matches(ProfileModel p, ProfileModel? me) {
    if (minAge != null && p.age < minAge!) return false;
    if (maxAge != null && p.age > maxAge!) return false;
    if (!_eq(p.state, state)) return false;
    if (!_eq(p.district, district)) return false;
    if (!_eq(p.city, city)) return false;
    if (!_eq(p.religion, religion)) return false;
    if (!_eq(p.caste ?? '', caste)) return false;
    if (!_eq(p.education, education)) return false;
    if (!_eq(p.occupation, occupation)) return false;
    if (!_eq(p.maritalStatus, maritalStatus)) return false;
    if (!_eq(p.horoscope.rasi, rasi)) return false;
    if (!_eq(p.horoscope.nakshatra, nakshatra)) return false;
    return true;
  }
}

// ── Partner-preference matching ─────────────────────────────────────────────
// Matches must SATISFY the signed-in user's partner preferences — never random.
// Each constraint is applied only when it is actually set ('Any' / empty = no
// constraint), so a user who hasn't filled preferences still sees the broad
// (gender-filtered) pool while the reminder banner nudges them to set them.

bool _ppSet(String? s) =>
    s != null && s.trim().isNotEmpty && s.trim().toLowerCase() != 'any';
bool _ppEq(String a, String? b) =>
    !_ppSet(b) || a.trim().toLowerCase() == b!.trim().toLowerCase();

/// How many of the user's ACTIVE partner-preference constraints a candidate
/// satisfies. `total` is the number of active constraints; `satisfied` is how
/// many the candidate meets. A constraint is "active" only when it is actually
/// set ('Any'/empty are ignored) — so an unconfigured profile yields total == 0
/// and therefore matches everyone.
class PartnerPrefScore {
  final int satisfied;
  final int total;
  const PartnerPrefScore(this.satisfied, this.total);

  /// All active constraints satisfied (or none configured).
  bool get isExact => total == 0 || satisfied == total;

  /// Fraction satisfied (1.0 when nothing is configured).
  double get ratio => total == 0 ? 1 : satisfied / total;
}

PartnerPrefScore partnerPreferenceScore(
    ProfileModel candidate, ProfileModel? me) {
  if (me == null) return const PartnerPrefScore(0, 0);
  final pp = me.partnerPreferences;
  final c = candidate;
  var total = 0, sat = 0;
  void check(bool active, bool ok) {
    if (active) {
      total++;
      if (ok) sat++;
    }
  }

  check(c.age > 0, c.age >= pp.minAge && c.age <= pp.maxAge);
  check(_ppSet(pp.maritalStatus), _ppEq(c.maritalStatus, pp.maritalStatus));
  check(_ppSet(pp.religion), _ppEq(c.religion, pp.religion));
  check(_ppSet(pp.caste), _ppEq(c.caste ?? '', pp.caste));
  check(pp.education.isNotEmpty, pp.education.any((e) => _ppEq(c.education, e)));
  check(pp.occupation.isNotEmpty,
      pp.occupation.any((o) => _ppEq(c.occupation, o)));
  check(_ppSet(pp.state), _ppEq(c.state, pp.state));
  check(_ppSet(pp.district), _ppEq(c.district, pp.district));
  check(_ppSet(pp.city), _ppEq(c.city, pp.city));
  check(_ppSet(pp.rasi), _ppEq(c.horoscope.rasi, pp.rasi));
  check(_ppSet(pp.nakshatra), _ppEq(c.horoscope.nakshatra, pp.nakshatra));

  // Height — only an active constraint when both bounds AND the candidate's
  // height are recognised values.
  final list = AppConstants.heightList;
  final minIdx = list.indexOf(pp.minHeight);
  final maxIdx = list.indexOf(pp.maxHeight);
  final cIdx = list.indexOf(c.height);
  check(minIdx >= 0 && maxIdx >= 0 && cIdx >= 0 && minIdx <= maxIdx,
      cIdx >= minIdx && cIdx <= maxIdx);

  return PartnerPrefScore(sat, total);
}

/// Strict match — the candidate satisfies ALL of the user's set preferences.
bool partnerPreferenceMatch(ProfileModel candidate, ProfileModel? me) =>
    partnerPreferenceScore(candidate, me).isExact;

/// True once the user has set at least one MEANINGFUL partner preference.
///
/// Age & height are deliberately EXCLUDED here because they always carry
/// defaults (18–40, 5'0"–5'10") — a profile with only those is treated as
/// "no preferences configured", so it is never silently over-filtered.
bool partnerPreferencesComplete(ProfileModel? me) {
  if (me == null) return false;
  final pp = me.partnerPreferences;
  return pp.education.isNotEmpty ||
      pp.occupation.isNotEmpty ||
      _ppSet(pp.religion) ||
      _ppSet(pp.caste) ||
      _ppSet(pp.state) ||
      _ppSet(pp.city) ||
      _ppSet(pp.maritalStatus) ||
      _ppSet(pp.rasi) ||
      _ppSet(pp.nakshatra);
}

// ── MANDATORY vs OPTIONAL matching ──────────────────────────────────────────
//
// Product rule for the Matches feed:
//   MANDATORY (a failing profile is NEVER shown):
//     1. Community / Caste — when the user has selected a caste preference, only
//        candidates of that caste/community appear.
//     2. Age — the candidate's age MUST fall inside the user's preferred age
//        range [minAge, maxAge].
//   OPTIONAL (used for RANKING only, never removes a profile):
//     religion, education, occupation, height, income, location, marital
//     status, mother tongue, rasi/nakshatra, … — see [partnerPreferenceScore].

/// Whether [candidate] passes BOTH mandatory gates (caste + age) for [me].
/// Returns true when [me] is null (we can't evaluate preferences yet) so the
/// feed isn't silently emptied before the user's own profile has loaded.
bool mandatoryPreferenceMatch(ProfileModel candidate, ProfileModel? me) {
  if (me == null) return true;
  final pp = me.partnerPreferences;

  // Age range — mandatory. Only skipped when the candidate's age is unknown (0),
  // so a data gap can't hide an otherwise-eligible profile.
  if (candidate.age > 0 &&
      (candidate.age < pp.minAge || candidate.age > pp.maxAge)) {
    return false;
  }

  // Community / Caste — mandatory ONLY when the user actually set a caste
  // preference ('Any'/empty means "no caste constraint").
  if (_ppSet(pp.caste) && !_casteMatches(candidate, pp)) return false;

  return true;
}

/// Whether [candidate]'s caste/community satisfies the user's SET caste
/// preference. Prefers an id match when both sides carry a caste id; otherwise
/// compares names case-insensitively with a tolerant contains check (so
/// "Vanniyar" still matches "Vanniyar Kula Kshatriyar").
bool _casteMatches(ProfileModel candidate, PartnerPreferences pp) {
  final b = (pp.caste ?? '').trim().toLowerCase();
  if (b.isEmpty) return true; // no caste preference set → not a constraint

  // Unknown candidate caste can't be PROVEN to mismatch — keep it rather than
  // hard-filtering on missing data, which would needlessly blank the feed when
  // profiles simply haven't filled in caste.
  final a = (candidate.caste ?? '').trim().toLowerCase();
  if (a.isEmpty) {
    final candId = (candidate.casteId ?? '').trim();
    if (candId.isEmpty) return true; // truly unknown → don't filter out
  }

  // Prefer an id match when both sides carry a caste id; otherwise compare
  // names case-insensitively with a tolerant contains check (so "Vanniyar"
  // still matches "Vanniyar Kula Kshatriyar").
  final prefId = (pp.casteId ?? '').trim();
  final candId = (candidate.casteId ?? '').trim();
  if (prefId.isNotEmpty && candId.isNotEmpty) return prefId == candId;

  if (a.isEmpty) return true;
  return a == b || a.contains(b) || b.contains(a);
}

/// The ONE hard partner-preference gate (per spec): **caste**.
///
/// When the user has selected a caste preference, only profiles of that
/// caste/community may appear anywhere profiles are listed (Matches feed,
/// Home New Profiles). 'Any' / unset caste applies no filtering at all.
/// Every other preference (age, education, income, location, …) only
/// PRIORITIZES the order — it never hides a profile.
bool casteGate(ProfileModel candidate, ProfileModel? me) {
  if (me == null) return true; // can't evaluate before my profile loads
  final pp = me.partnerPreferences;
  if (!_ppSet(pp.caste)) return true; // 'Any' / empty → no caste constraint
  return _casteMatches(candidate, pp);
}

/// Relevance highlight for a browse card. Deliberately NOT a score, percentage
/// or grade — just a simple flag driving the ⭐ badge:
///   • [nakshatra] — the candidate's star is compatible with the user's
///     ([isNakshatraCompatible]) → "⭐ Nakshatra Match";
///   • [matching]  — the user has set meaningful partner preferences and the
///     candidate satisfies the hard age + caste gate
///     ([mandatoryPreferenceMatch]) → "⭐ Matching Profile";
///   • [none]      — neither, so the card shows no badge.
enum ProfileHighlight { nakshatra, matching, none }

/// Computes the [ProfileHighlight] for [candidate] against the signed-in user
/// [me]. Nakshatra compatibility takes precedence over a plain preference
/// match. Returns [ProfileHighlight.none] until the user's own profile loads.
ProfileHighlight profileHighlight(ProfileModel? me, ProfileModel candidate) {
  if (me == null) return ProfileHighlight.none;
  if (isNakshatraCompatible(me, candidate)) return ProfileHighlight.nakshatra;
  if (partnerPreferencesComplete(me) &&
      mandatoryPreferenceMatch(candidate, me)) {
    return ProfileHighlight.matching;
  }
  return ProfileHighlight.none;
}

class DiscoverState {
  final List<ProfileModel> profiles;
  final bool isLoading; // initial page
  final bool isLoadingMore; // pagination
  final bool hasMore;
  final String? error;

  const DiscoverState({
    this.profiles = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  DiscoverState copyWith({
    List<ProfileModel>? profiles,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
  }) =>
      DiscoverState(
        profiles: profiles ?? this.profiles,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: error,
      );
}

class DiscoverNotifier extends Notifier<DiscoverState> {
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  String _gender = '';
  MatchFilters _filters = const MatchFilters();

  /// The raw fetched (gender-eligible) pool, cached so switching the match
  /// mode (Compatible ⇄ All) re-filters INSTANTLY without refetching.
  final List<ProfileModel> _pool = [];

  /// When an active filter makes a single fetched page sparse, keep fetching up
  /// to this many extra pages so the feed isn't empty just because the first
  /// page happened to contain no matches.
  static const int _kMaxAutoPages = 6;

  @override
  DiscoverState build() => const DiscoverState();

  /// The currently applied optional filters (read by the UI for the badge).
  MatchFilters get filters => _filters;

  /// Replace the optional filters and reload from the first page.
  Future<void> applyFilters(MatchFilters filters) async {
    _filters = filters;
    await load();
  }

  /// Clear all optional filters and reload.
  Future<void> clearFilters() => applyFilters(const MatchFilters());

  /// Data-integrity excludes only (NOT matching filters): never show the user
  /// themselves, married members, or deactivated / blocked accounts.
  bool _keep(ProfileModel p, String? myUid) {
    if (myUid != null && p.userId == myUid) return false;
    if (p.isMarried) return false;
    if (!p.isActive) return false;
    if (p.status == 'rejected' || p.status == 'blocked') return false;
    return true;
  }

  /// Visibility gate for the Matches feed.
  ///
  /// CASTE is the single hard filter (highest priority, per spec): when the
  /// user set a caste preference, only matching-caste profiles appear; 'Any'
  /// applies no filtering. Every OTHER preference (age, education, income, …)
  /// and nakshatra compatibility only prioritise the order in [_rank] — they
  /// never remove a profile from browsing.
  bool _passesMode(ProfileModel p, ProfileModel? me) => casteGate(p, me);

  /// How close [p] is to [me] geographically: 3 same city · 2 same district ·
  /// 1 same state · 0 elsewhere/unknown. Ranking signal only.
  static int _locationScore(ProfileModel p, ProfileModel? me) {
    if (me == null) return 0;
    bool eq(String a, String b) {
      final na = a.trim().toLowerCase(), nb = b.trim().toLowerCase();
      return na.isNotEmpty && na == nb;
    }

    if (eq(p.city, me.city)) return 3;
    if (eq(p.district, me.district)) return 2;
    if (eq(p.state, me.state)) return 1;
    return 0;
  }

  /// Builds the feed from a fetched [pool]:
  ///   • Data-integrity + the user's explicit filter-sheet choices decide who
  ///     is ELIGIBLE at all; the match-mode gate ([_passesMode]) is applied on
  ///     top (Compatible only — All Matches never hides an eligible profile).
  ///   • The result is sorted by the spec's priority ladder:
  ///       1. Horoscope (nakshatra) compatibility
  ///       2. Partner-preference match (mandatory age+caste, then the ratio)
  ///       3. Nearby location (city > district > state)
  ///       4. Recently active (updatedAt) — with the id as the final
  ///          tie-break so the order is STABLE across loads (the swipe
  ///          browser's saved position stays meaningful).
  List<ProfileModel> _rank(
      List<ProfileModel> pool, String? myUid, ProfileModel? me,
      {required int fetched}) {
    final eligible = pool
        .where((p) =>
            _keep(p, myUid) && _filters.matches(p, me) && _passesMode(p, me))
        .toList();

    int cmp(ProfileModel a, ProfileModel b) {
      // 1. Horoscope compatibility first.
      if (me != null) {
        final ca = isNakshatraCompatible(me, a) ? 1 : 0;
        final cb = isNakshatraCompatible(me, b) ? 1 : 0;
        if (ca != cb) return cb - ca;
      }
      // 2. Partner-preference match — hard (age+caste) gate first, then the
      //    fraction of optional preferences satisfied.
      final ma = mandatoryPreferenceMatch(a, me) ? 1 : 0;
      final mb = mandatoryPreferenceMatch(b, me) ? 1 : 0;
      if (ma != mb) return mb - ma;
      final pa = partnerPreferenceScore(a, me).ratio;
      final pb = partnerPreferenceScore(b, me).ratio;
      if (pa != pb) return pb.compareTo(pa);
      // 3. Nearby location.
      final la = _locationScore(a, me), lb = _locationScore(b, me);
      if (la != lb) return lb - la;
      // 4. Recently active.
      final act = b.updatedAt.compareTo(a.updatedAt);
      if (act != 0) return act;
      // Stable, deterministic tie-break.
      return a.id.compareTo(b.id);
    }

    final result = [...eligible]..sort(cmp);

    debugPrint('[Discover] gender=$_gender myGender=${me?.gender} · '
        'fetched=$fetched · eligible=${eligible.length} · '
        'returned=${result.length} · '
        'casteSet=${_ppSet(me?.partnerPreferences.caste)} · '
        'age=${me?.partnerPreferences.minAge}-${me?.partnerPreferences.maxAge} · '
        'explicitFilters=${_filters.isActive}');
    if (fetched > 0 && eligible.isEmpty) {
      debugPrint('[Discover] ⚠ all $fetched fetched profile(s) were excluded by '
          'integrity / explicit filters (self / married / inactive / blocked).');
    }
    if (fetched == 0) {
      debugPrint('[Discover] ⚠ the gender="$_gender" query returned 0 profiles. '
          'Either no opposite-gender profiles exist, or your own gender is '
          'missing (myGender=${me?.gender}).');
    }
    return result;
  }

  /// Load the first page of opposite-gender matches, then rank with the
  /// partner-preference fallback ladder.
  Future<void> load() async {
    _gender = ref.read(matchGenderProvider);
    _lastDoc = null;
    state = const DiscoverState(isLoading: true);

    final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    final me = ref.read(myProfileProvider).valueOrNull;

    // ── Demo mode: in-memory store, no pagination ──
    if (kBypassAuth) {
      final pool =
          ref.read(demoProfilesProvider.notifier).discover(gender: _gender);
      _pool
        ..clear()
        ..addAll(pool);
      state = DiscoverState(
        profiles: _rank(pool, myUid, me, fetched: pool.length),
        isLoading: false,
        hasMore: false,
      );
      return;
    }

    try {
      final repo = ref.read(profileRepositoryProvider);
      // Build a pool of gender-eligible profiles to rank over. Page until we
      // have a reasonable pool (so the mode gate has profiles to work with).
      final pool = <ProfileModel>[];
      var hasMore = true;
      for (var i = 0; i < _kMaxAutoPages && hasMore; i++) {
        final ProfilePage page = await repo.searchProfilesPage(
          gender: _gender,
          limit: _kDiscoverPageSize,
          startAfter: _lastDoc,
        );
        _lastDoc = page.lastDoc;
        hasMore = page.hasMore;
        pool.addAll(page.profiles);
        if (pool.length >= 60) break; // enough to rank over
      }
      _pool
        ..clear()
        ..addAll(pool);
      state = DiscoverState(
        profiles: _rank(pool, myUid, me, fetched: pool.length),
        isLoading: false,
        hasMore: hasMore,
      );
    } on FirebaseException catch (e, st) {
      debugPrint('[Discover] Firestore error ${e.code}: ${e.message}\n$st');
      state = state.copyWith(isLoading: false, error: e.code);
    } catch (e, st) {
      debugPrint('[Discover] load failed: $e\n$st');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Append the next page (called as the user nears the end of the feed).
  Future<void> loadMore() async {
    if (kBypassAuth) return; // demo store has no further pages
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    if (_lastDoc == null) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      final me = ref.read(myProfileProvider).valueOrNull;
      final ProfilePage page = await ref
          .read(profileRepositoryProvider)
          .searchProfilesPage(
              gender: _gender, limit: _kDiscoverPageSize, startAfter: _lastDoc);
      _lastDoc = page.lastDoc;

      // Cache the raw page too, so a later Compatible ⇄ All switch re-filters
      // over everything fetched so far.
      final pooled = _pool.map((p) => p.id).toSet();
      _pool.addAll(page.profiles.where((p) => !pooled.contains(p.id)));

      // Append, de-duplicating by id so a re-fetched boundary doc can't double.
      // The same match-mode gate used by [_rank] applies, so newly paged-in
      // profiles always match what's already on screen.
      final existing = state.profiles.map((p) => p.id).toSet();
      final added = page.profiles
          .where((p) =>
              _keep(p, myUid) &&
              _filters.matches(p, me) &&
              _passesMode(p, me) &&
              !existing.contains(p.id))
          .toList();
      state = state.copyWith(
        profiles: [...state.profiles, ...added],
        isLoadingMore: false,
        hasMore: page.hasMore,
      );
    } catch (e, st) {
      debugPrint('[Discover] loadMore failed: $e\n$st');
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final discoverProvider =
    NotifierProvider<DiscoverNotifier, DiscoverState>(() => DiscoverNotifier());

/// **New Profiles** for the Home page — the LATEST registered opposite-gender
/// profiles, newest first, capped to 10.
///
/// CASTE is the one hard gate (same rule as the Matches feed, per spec): with
/// a caste preference set, only matching-caste profiles appear; 'Any' shows the
/// newest 10 without filtering. No other preference or nakshatra gating —
/// besides basic eligibility (never self / married / inactive / rejected /
/// blocked), the list simply surfaces the newest members as people register.
final newProfilesProvider =
    FutureProvider.autoDispose<List<ProfileModel>>((ref) async {
  final gender = ref.watch(matchGenderProvider);
  final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  final me = ref.watch(myProfileProvider).valueOrNull;

  final List<ProfileModel> pool;
  if (kBypassAuth) {
    pool = ref.read(demoProfilesProvider.notifier).discover(gender: gender);
  } else {
    final page = await ref
        .read(profileRepositoryProvider)
        .searchProfilesPage(gender: gender, limit: 60);
    pool = page.profiles;
  }

  final eligible = pool.where((p) {
    if (p.userId == myUid) return false;
    if (p.isMarried) return false;
    if (!p.isActive) return false;
    if (p.status == 'rejected' || p.status == 'blocked') return false;
    return casteGate(p, me);
  }).toList()
    // Newest joiners first.
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return eligible.take(10).toList();
});
