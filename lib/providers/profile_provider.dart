import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../models/profile_model.dart';
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

  const ProfileCreationState({
    this.data = const {},
    this.photos = const [],
    this.horoscopePdf,
    this.isLoading = false,
    this.error,
    this.isComplete = false,
  });

  ProfileCreationState copyWith({
    Map<String, dynamic>? data,
    List<File>? photos,
    File? horoscopePdf,
    bool? isLoading,
    String? error,
    bool? isComplete,
  }) =>
      ProfileCreationState(
        data: data ?? this.data,
        photos: photos ?? this.photos,
        horoscopePdf: horoscopePdf ?? this.horoscopePdf,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isComplete: isComplete ?? this.isComplete,
      );
}

class ProfileCreationNotifier extends Notifier<ProfileCreationState> {
  @override
  ProfileCreationState build() => const ProfileCreationState();

  void updateData(Map<String, dynamic> partial) =>
      state = state.copyWith(data: {...state.data, ...partial});

  void setPhotos(List<File> photos) => state = state.copyWith(photos: photos);

  void setHoroscopePdf(File pdf) => state = state.copyWith(horoscopePdf: pdf);

  Future<String?> submitProfile(String userId) async {
    state = state.copyWith(isLoading: true, error: null);

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
      List<String> photoUrls = [];
      if (state.photos.isNotEmpty) {
        photoUrls = await repo.uploadPhotos(userId: userId, files: state.photos);
      }
      String? pdfUrl;
      if (state.horoscopePdf != null) {
        pdfUrl = await repo.uploadHoroscopePdf(userId: userId, file: state.horoscopePdf!);
      }

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

      final profile = ProfileModel.fromMap(profileData);
      final profileId = await repo.createProfile(profile);
      // Mark the account as profile-completed so the Home gate opens.
      await ref.read(firestoreServiceProvider).markProfileCompleted(userId);
      ref.invalidate(currentUserProvider); // refresh the gate
      state = state.copyWith(isLoading: false, isComplete: true);
      return profileId;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  void reset() => state = const ProfileCreationState();
}

final profileCreationProvider =
    NotifierProvider<ProfileCreationNotifier, ProfileCreationState>(() => ProfileCreationNotifier());

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
      final profiles = await ref.read(profileRepositoryProvider).searchProfiles(
            gender: gender,
            religion: f['religion'],
            city: f['city'],
            rasi: f['rasi'],
          );
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
