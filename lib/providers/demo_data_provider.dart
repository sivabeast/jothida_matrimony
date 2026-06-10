import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/data/sample_profiles.dart';
import '../models/profile_model.dart';

/// In-memory profile store used in frontend/demo mode (`kBypassAuth == true`).
///
/// Seeded with [sampleProfiles]. The profile the user creates in the
/// 7-step flow is prepended here so it shows up immediately on Discover and
/// "My Profile" without any backend. Resets when the app restarts.
class DemoProfilesNotifier extends Notifier<List<ProfileModel>> {
  @override
  List<ProfileModel> build() => sampleProfiles();

  /// Add (or replace) the user's created profile at the top of the list.
  void upsert(ProfileModel profile) {
    final without = state.where((p) => p.id != profile.id).toList();
    state = [profile, ...without];
  }

  ProfileModel? byId(String id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Opposite-gender, active, approved profiles for the Discover feed.
  List<ProfileModel> discover({required String gender}) =>
      state.where((p) => p.gender == gender && p.isActive).toList();
}

final demoProfilesProvider =
    NotifierProvider<DemoProfilesNotifier, List<ProfileModel>>(
        DemoProfilesNotifier.new);

/// Id of the profile created by the current demo user (null until they finish
/// the creation flow). Drives "My Profile" in demo mode.
final myDemoProfileIdProvider = StateProvider<String?>((_) => null);

/// Stable demo user id used when auth is bypassed.
const String kDemoUserId = 'demo-user';
