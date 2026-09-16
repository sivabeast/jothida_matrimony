import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/dev_config.dart';
import '../models/profile_model.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';
import 'matches_prefs_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';
import '../repositories/auth_repository.dart' show AccountDeletionResult;
import '../services/cloudinary/cloudinary_storage_service.dart';

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
  /// session providers. The caller navigates to the Login screen afterwards.
  ///
  /// Rethrows on failure (in ADDITION to recording the error in [state]) so the
  /// Settings screen's try/catch can actually show its "could not delete"
  /// message — `AsyncValue.guard` alone swallows the error, which used to make
  /// a failed deletion look like a successful one.
  ///
  /// Returns what actually happened ([AccountDeletionResult]) rather than a
  /// bare "it worked": the Firebase Auth record and the Firestore data fail
  /// independently, and only the caller can decide what to tell the member.
  Future<AccountDeletionResult> deleteAccount(
      {required bool isAstrologer}) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(authRepositoryProvider);
      final uid = repo.currentUserId;
      var result = const AccountDeletionResult(authDeleted: true);

      if (kBypassAuth) {
        // Demo mode: drop the locally-created profile / astrologer session.
        final demoId = ref.read(myDemoProfileIdProvider);
        if (demoId != null) {
          ref.read(demoProfilesProvider.notifier).remove(demoId);
        }
        ref.read(myDemoProfileIdProvider.notifier).state = null;
      } else if (uid != null) {
        // Cloudinary assets FIRST, while the profile document still exists —
        // once it is deleted the URLs are gone and the images would be
        // orphaned in Cloudinary forever (spec §12). Best-effort: whatever
        // cannot be deleted is queued in `cloudinary_cleanup` by the cleanup
        // service, never silently dropped.
        await _deleteCloudinaryAssets(uid);
        // Chats FIRST, while the session still satisfies the participant-only
        // rules. The thread document is shared, so it cannot be deleted by the
        // leaving member — it is tombstoned instead, which removes their name,
        // photo and the whole conversation from the other member's Chats list
        // (spec §2). Best-effort: a chat that cannot be cleared must never
        // block the account deletion itself, but it IS logged so an orphaned
        // thread can be found later rather than failing silently.
        if (!isAstrologer) {
          try {
            final failed =
                await ref.read(chatServiceProvider).tombstoneThreadsFor(uid);
            if (failed != 0) {
              debugPrint('[AccountController] chat tombstone incomplete for '
                  '$uid (failed=$failed) — threads may still show this member.');
            }
          } catch (e) {
            debugPrint('[AccountController] chat tombstone skipped: $e');
          }
        }
        result = await repo.deleteAccount(uid, isAstrologer: isAstrologer);
      }

      // Local cleanup — SharedPreferences holds cached login/role/onboarding
      // state. (This app does not use flutter_secure_storage.)
      await _clearLocalStorage();
      // ...and the IMAGE caches, which SharedPreferences knows nothing about.
      // `cached_network_image` keeps the bytes on disk keyed by URL, and
      // Flutter keeps decoded frames in memory; neither notices that the
      // account they belonged to is gone. Left alone, the next person to use
      // this device can be shown the previous member's photo the moment a
      // stale URL is rendered (spec §4/§27).
      await _clearImageCaches();

      // Belt and braces: even if `deleteAccount` above bailed out early, the
      // session must end. A signed-OUT user is what sends the router to /login.
      try {
        await repo.signOut();
      } catch (e) {
        debugPrint('[AccountController] post-delete signOut skipped: $e');
      }

      // Reset in-memory session so nothing stale survives into the next login.
      ref.invalidate(currentUserProvider);
      ref.invalidate(myProfileProvider);
      ref.invalidate(viewedProfilesProvider);
      state = const AsyncData(null);
      return result;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Removes every Cloudinary asset this member uploaded — profile photos and
  /// horoscope images/PDFs (spec §12).
  ///
  /// Reads the URLs off the LIVE profile before anything is deleted, because
  /// once the profile document is gone there is no way to know which assets
  /// belonged to them. Never throws: a failed cleanup must not stop the
  /// account deletion, and the cleanup service queues anything it could not
  /// delete so orphans stay findable.
  Future<void> _deleteCloudinaryAssets(String uid) async {
    try {
      final profile = ref.read(myProfileProvider).valueOrNull;
      if (profile == null) return;
      final h = profile.horoscope;
      final urls = <String?>[
        profile.profilePhotoUrl,
        ...profile.photos,
        ...h.horoscopeImages,
        ...h.allPdfUrls,
      ];
      final storage = ref.read(storageServiceProvider);
      if (storage is CloudinaryStorageService) {
        final deleted =
            await storage.deleteFiles(urls, reason: 'account_deleted:$uid');
        debugPrint('[AccountController] Cloudinary: $deleted asset(s) deleted '
            'for $uid.');
      }
    } catch (e) {
      debugPrint('[AccountController] Cloudinary cleanup skipped: $e');
    }
  }

  /// Keys that must SURVIVE a `prefs.clear()`.
  ///
  /// The chosen app language is a device preference, not account data. Wiping
  /// it drops the user on the first-launch Language screen instead of Login,
  /// which is not what "delete my account" should do.
  /// Must stay in sync with `_kLocaleKey` in locale_provider.dart.
  static const _preservedPrefKeys = <String>['app_locale'];

  /// Empties both image caches so nothing of the deleted account can still be
  /// painted on this device. Best-effort — a cache that will not clear must
  /// never block the deletion.
  Future<void> _clearImageCaches() async {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {/* no binding (tests) */}
    try {
      await DefaultCacheManager().emptyCache();
    } catch (e) {
      debugPrint('[AccountController] image cache clear skipped: $e');
    }
  }

  Future<void> _clearLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preserved = <String, String>{
        for (final k in _preservedPrefKeys)
          if (prefs.getString(k) != null) k: prefs.getString(k)!,
      };
      await prefs.clear();
      for (final entry in preserved.entries) {
        await prefs.setString(entry.key, entry.value);
      }
    } catch (_) {
      // Best-effort: never let a cache-clear failure block the deletion.
    }
  }
}

final accountControllerProvider =
    NotifierProvider<AccountController, AsyncValue<void>>(AccountController.new);
