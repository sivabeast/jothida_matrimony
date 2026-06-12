import 'dart:io';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../models/profile_model.dart';
import '../services/cloudinary/cloudinary_exception.dart';
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
        'status': 'pending',
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

// Discover / search
class DiscoverState {
  final List<ProfileModel> profiles;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  final Map<String, dynamic> filters;

  const DiscoverState({
    this.profiles = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
    this.filters = const {},
  });

  DiscoverState copyWith({
    List<ProfileModel>? profiles,
    bool? isLoading,
    bool? hasMore,
    String? error,
    Map<String, dynamic>? filters,
  }) =>
      DiscoverState(
        profiles: profiles ?? this.profiles,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        error: error,
        filters: filters ?? this.filters,
      );
}

class DiscoverNotifier extends Notifier<DiscoverState> {
  @override
  DiscoverState build() => const DiscoverState();

  Future<void> load({String gender = 'Female', Map<String, dynamic>? filters}) async {
    state = DiscoverState(isLoading: true, filters: filters ?? {});

    // ── Demo mode: read from the in-memory sample store + apply filters ──
    if (kBypassAuth) {
      final f = filters ?? {};
      var profiles =
          ref.read(demoProfilesProvider.notifier).discover(gender: gender);

      final minAge = f['minAge'] as int?;
      final maxAge = f['maxAge'] as int?;
      final city = (f['city'] as String?)?.trim();
      final education = (f['education'] as String?)?.trim();
      final occupation = (f['occupation'] as String?)?.trim();

      profiles = profiles.where((p) {
        if (minAge != null && p.age < minAge) return false;
        if (maxAge != null && p.age > maxAge) return false;
        if (city != null && city.isNotEmpty &&
            !p.city.toLowerCase().contains(city.toLowerCase())) return false;
        if (education != null && education.isNotEmpty &&
            !p.education.toLowerCase().contains(education.toLowerCase())) return false;
        if (occupation != null && occupation.isNotEmpty &&
            !p.occupation.toLowerCase().contains(occupation.toLowerCase())) {
          return false;
        }
        return true;
      }).toList();

      state = state.copyWith(profiles: profiles, isLoading: false, hasMore: false);
      return;
    }

    try {
      final f = filters ?? {};
      // Gender is filtered at the Firestore query level (opposite-gender
      // matching); the remaining lightweight filters refine the page locally.
      var profiles = await ref.read(profileRepositoryProvider).searchProfiles(
            gender: gender,
            religion: f['religion'],
            city: f['city'],
            rasi: f['rasi'],
          );

      final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      final minAge = f['minAge'] as int?;
      final maxAge = f['maxAge'] as int?;
      final education = (f['education'] as String?)?.trim().toLowerCase();
      final occupation = (f['occupation'] as String?)?.trim().toLowerCase();

      profiles = profiles.where((p) {
        if (myUid != null && p.userId == myUid) return false; // never self
        if (p.isMarried) return false; // married users leave matchmaking
        if (minAge != null && p.age < minAge) return false;
        if (maxAge != null && p.age > maxAge) return false;
        if (education != null && education.isNotEmpty &&
            !p.education.toLowerCase().contains(education)) return false;
        if (occupation != null && occupation.isNotEmpty &&
            !p.occupation.toLowerCase().contains(occupation)) return false;
        return true;
      }).toList();

      state = state.copyWith(
        profiles: profiles,
        isLoading: false,
        hasMore: profiles.length == 20,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setFilters(Map<String, dynamic> filters) => state = state.copyWith(filters: filters);
}

final discoverProvider =
    NotifierProvider<DiscoverNotifier, DiscoverState>(() => DiscoverNotifier());
