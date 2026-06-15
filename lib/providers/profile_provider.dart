import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart' show DocumentSnapshot;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../models/profile_model.dart';
import '../services/cloudinary/cloudinary_exception.dart';
import '../services/firebase/firestore_service.dart' show ProfilePage;
import 'demo_data_provider.dart';
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

  return ref.watch(profileRepositoryProvider).getProfileByUserId(userId).asStream();
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

  Future<String?> submitProfile(String userId) async {
    state = state.copyWith(isLoading: true, error: null, uploadProgress: 0, uploadStatus: null);

    // ── Demo mode: save the profile to the in-memory store, no backend ──
    if (kBypassAuth) {
      try {
        final id = 'me_${DateTime.now().millisecondsSinceEpoch}';
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

      final profileData = {
        ...state.data,
        'userId': userId,
        'photos': photoUrls,
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
      debugPrint('[submitProfile] ▶ writing profile to Firestore...');
      final profileId = await repo.createProfile(profile);
      debugPrint('[submitProfile] ✅ Firestore profile created (id=$profileId)');

      // Mark the account as profile-completed so the Home gate opens.
      debugPrint('[submitProfile] ▶ marking profile completed for userId=$userId');
      await ref.read(firestoreServiceProvider).markProfileCompleted(userId);
      debugPrint('[submitProfile] ✅ markProfileCompleted done');
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
// MATCHING RULE: the ONLY matching filter is gender (opposite gender). No age,
// caste, religion, district or horoscope filtering. Horoscope compatibility is
// surfaced as an informational badge only — it never removes a profile.
const int _kDiscoverPageSize = 20;

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

  @override
  DiscoverState build() => const DiscoverState();

  /// Data-integrity excludes only (NOT matching filters): never show the user
  /// themselves, married members, or deactivated / blocked accounts.
  bool _keep(ProfileModel p, String? myUid) {
    if (myUid != null && p.userId == myUid) return false;
    if (p.isMarried) return false;
    if (!p.isActive) return false;
    if (p.status == 'rejected' || p.status == 'blocked') return false;
    return true;
  }

  /// Load the first page of opposite-gender matches.
  Future<void> load() async {
    _gender = ref.read(matchGenderProvider);
    _lastDoc = null;
    state = const DiscoverState(isLoading: true);

    // ── Demo mode: in-memory store, no pagination ──
    if (kBypassAuth) {
      final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      final profiles = ref
          .read(demoProfilesProvider.notifier)
          .discover(gender: _gender)
          .where((p) => _keep(p, myUid))
          .toList();
      state = DiscoverState(profiles: profiles, isLoading: false, hasMore: false);
      return;
    }

    try {
      final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      final ProfilePage page = await ref
          .read(profileRepositoryProvider)
          .searchProfilesPage(gender: _gender, limit: _kDiscoverPageSize);
      _lastDoc = page.lastDoc;
      state = DiscoverState(
        profiles: page.profiles.where((p) => _keep(p, myUid)).toList(),
        isLoading: false,
        hasMore: page.hasMore,
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
      final ProfilePage page = await ref
          .read(profileRepositoryProvider)
          .searchProfilesPage(
              gender: _gender, limit: _kDiscoverPageSize, startAfter: _lastDoc);
      _lastDoc = page.lastDoc;

      // Append, de-duplicating by id so a re-fetched boundary doc can't double.
      final existing = state.profiles.map((p) => p.id).toSet();
      final added = page.profiles
          .where((p) => _keep(p, myUid) && !existing.contains(p.id))
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

/// Home "Recommended Matches": the latest 10 opposite-gender registrations
/// (createdAt DESC, limit 10). Gender is the only filter; horoscope
/// compatibility is shown as a badge, never used to exclude.
final recommendedMatchesProvider =
    FutureProvider.autoDispose<List<ProfileModel>>((ref) async {
  final gender = ref.watch(matchGenderProvider);
  final myUid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;

  if (kBypassAuth) {
    return ref
        .read(demoProfilesProvider.notifier)
        .discover(gender: gender)
        .where((p) => p.userId != myUid)
        .take(10)
        .toList();
  }

  // Fetch a small buffer beyond 10 so client-side self/married excludes can't
  // leave us short.
  final page = await ref
      .read(profileRepositoryProvider)
      .searchProfilesPage(gender: gender, limit: 14);
  return page.profiles
      .where((p) =>
          p.userId != myUid &&
          !p.isMarried &&
          p.isActive &&
          p.status != 'rejected' &&
          p.status != 'blocked')
      .take(10)
      .toList();
});
