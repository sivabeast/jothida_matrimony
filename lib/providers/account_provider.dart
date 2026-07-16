import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/dev_config.dart';
import '../models/profile_model.dart';
import 'astrologer_session_provider.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Account lifecycle: "Mark as Married" and immediate self-service account
/// deletion. Works in demo mode (in-memory) and real mode (Firestore).
/// (The old admin-approved deletion-request workflow was removed — deletion
/// is instant and needs no admin review.)

/// Married profiles (admin "Married Users").
final marriedProfilesProvider =
    FutureProvider.autoDispose<List<ProfileModel>>((ref) async {
  if (kBypassAuth) {
    return ref.watch(demoProfilesProvider).where((p) => p.isMarried).toList();
  }
  return ref.watch(firestoreServiceProvider).getMarriedProfiles();
});

// ── Action controller ────────────────────────────────────────────────────────

class AccountController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Marks the profile married (leaves matchmaking). [via] records how the
  /// partner was found ('app' | 'other') from the confirmation flow.
  Future<void> markMarried(ProfileModel profile, {String? via}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (kBypassAuth) {
        ref
            .read(demoProfilesProvider.notifier)
            .upsert(profile.copyWith(isMarried: true, isActive: false));
      } else {
        await ref
            .read(firestoreServiceProvider)
            .markProfileMarried(profile.id, via: via);
        ref.invalidate(myProfileProvider);
      }
    });
  }

  /// UNDO for [markMarried]: returns the profile to normal matchmaking — for
  /// an accidental confirmation or changed marriage plans. Fully reversible
  /// by the user at any time.
  Future<void> unmarkMarried(ProfileModel profile) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (kBypassAuth) {
        ref
            .read(demoProfilesProvider.notifier)
            .upsert(profile.copyWith(isMarried: false, isActive: true));
      } else {
        await ref
            .read(firestoreServiceProvider)
            .unmarkProfileMarried(profile.id);
        ref.invalidate(myProfileProvider);
      }
    });
  }

  /// Immediately and permanently deletes the signed-in account (no admin
  /// approval). Removes all Firestore data, deletes the Firebase Auth user,
  /// signs out of Google + Firebase, clears local caches, and resets in-memory
  /// session providers. The caller navigates to the Login screen on success.
  Future<void> deleteAccount({required bool isAstrologer}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final uid = repo.currentUserId;

      if (kBypassAuth) {
        // Demo mode: drop the locally-created profile / astrologer session.
        final demoId = ref.read(myDemoProfileIdProvider);
        if (demoId != null) {
          ref.read(demoProfilesProvider.notifier).remove(demoId);
        }
        ref.read(myDemoProfileIdProvider.notifier).state = null;
      } else if (uid != null) {
        await repo.deleteAccount(uid, isAstrologer: isAstrologer);
      }

      // Local cleanup — SharedPreferences holds cached login/role/onboarding
      // state. (This app does not use flutter_secure_storage.)
      await _clearLocalStorage();

      // Reset in-memory session so nothing stale survives into the next login.
      ref.read(myAstrologerAccountProvider.notifier).signOut();
      ref.invalidate(currentUserProvider);
      ref.invalidate(myProfileProvider);
    });
  }

  Future<void> _clearLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {
      // Best-effort: never let a cache-clear failure block the deletion.
    }
  }

}

final accountControllerProvider =
    NotifierProvider<AccountController, AsyncValue<void>>(AccountController.new);
