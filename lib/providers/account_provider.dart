import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/dev_config.dart';
import '../models/account_deletion_request_model.dart';
import '../models/profile_model.dart';
import 'astrologer_session_provider.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Account lifecycle: "Mark as Married" and the admin-approved account
/// deletion workflow. Works in demo mode (in-memory) and real mode (Firestore).

// ── Demo in-memory deletion-request store ────────────────────────────────────

class DemoDeletionNotifier extends Notifier<List<AccountDeletionRequest>> {
  @override
  List<AccountDeletionRequest> build() => [];

  void add(AccountDeletionRequest r) => state = [r, ...state];

  void setStatus(String id, String status) => state = [
        for (final r in state)
          if (r.id == id)
            AccountDeletionRequest(
              id: r.id,
              userId: r.userId,
              userName: r.userName,
              email: r.email,
              requestDate: r.requestDate,
              status: status,
            )
          else
            r,
      ];
}

final demoDeletionRequestsProvider =
    NotifierProvider<DemoDeletionNotifier, List<AccountDeletionRequest>>(
        DemoDeletionNotifier.new);

// ── Read providers (admin) ───────────────────────────────────────────────────

/// All account deletion requests (newest first). Demo store or Firestore.
final deletionRequestsProvider =
    FutureProvider.autoDispose<List<AccountDeletionRequest>>((ref) async {
  if (kBypassAuth) return ref.watch(demoDeletionRequestsProvider);
  return ref.watch(firestoreServiceProvider).getDeletionRequests();
});

/// Number of pending requests — drives the admin notification badge.
final pendingDeletionCountProvider = Provider.autoDispose<int>((ref) {
  final reqs =
      ref.watch(deletionRequestsProvider).valueOrNull ?? const <AccountDeletionRequest>[];
  return reqs.where((r) => r.status == 'pending').length;
});

/// Whether the current user has a pending deletion request (Settings badge).
final deletionPendingProvider = Provider.autoDispose<bool>((ref) {
  if (kBypassAuth) {
    return ref.watch(demoDeletionRequestsProvider).any((r) => r.status == 'pending');
  }
  return ref.watch(currentUserProvider).valueOrNull?.deletionRequested ?? false;
});

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

  Future<void> markMarried(ProfileModel profile) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (kBypassAuth) {
        ref
            .read(demoProfilesProvider.notifier)
            .upsert(profile.copyWith(isMarried: true, isActive: false));
      } else {
        await ref.read(firestoreServiceProvider).markProfileMarried(profile.id);
        ref.invalidate(myProfileProvider);
      }
    });
  }

  Future<void> submitDeletionRequest({
    required String userId,
    required String userName,
    required String email,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final req = AccountDeletionRequest(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: userId,
        userName: userName,
        email: email,
        requestDate: DateTime.now(),
        status: 'pending',
      );
      if (kBypassAuth) {
        ref.read(demoDeletionRequestsProvider.notifier).add(req);
      } else {
        await ref.read(firestoreServiceProvider).submitDeletionRequest(req);
        ref.invalidate(currentUserProvider);
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

  Future<void> approveDeletion(AccountDeletionRequest req) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (kBypassAuth) {
        ref.read(demoDeletionRequestsProvider.notifier).setStatus(req.id, 'approved');
      } else {
        await ref.read(firestoreServiceProvider).approveDeletionRequest(req);
      }
      ref.invalidate(deletionRequestsProvider);
    });
  }

  Future<void> rejectDeletion(AccountDeletionRequest req) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (kBypassAuth) {
        ref.read(demoDeletionRequestsProvider.notifier).setStatus(req.id, 'rejected');
      } else {
        await ref
            .read(firestoreServiceProvider)
            .rejectDeletionRequest(req.id, req.userId);
      }
      ref.invalidate(deletionRequestsProvider);
    });
  }
}

final accountControllerProvider =
    NotifierProvider<AccountController, AsyncValue<void>>(AccountController.new);
