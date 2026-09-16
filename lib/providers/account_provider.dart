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
import '../core/errors/auth_exception.dart';
import '../core/utils/account_deletion_flow.dart';
import '../repositories/auth_repository.dart'
    show AccountDeletionOutcome, AccountDeletionResult;
import '../services/cloudinary/cloudinary_storage_service.dart';
import '../services/firebase/storage_service.dart';

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

  /// Permanently deletes the signed-in account — the member's data AND the
  /// Firebase Authentication user — in the order `AccountDeletionFlow`
  /// defines (see core/utils/account_deletion_flow.dart for why):
  ///
  ///   signed-in check → re-authenticate if Firebase would require it →
  ///   files + chats + Firestore data (still authenticated) → Firebase Auth
  ///   user → ONLY THEN sign out and clear local state.
  ///
  /// Nothing signs the member out before the Auth user is gone. When
  /// [AccountDeletionResult.outcome] is anything other than
  /// [AccountDeletionOutcome.deleted] the member is still signed in and the
  /// caller must NOT report a deletion.
  ///
  /// [reauthenticate] is supplied by the screen: it shows the password prompt
  /// (or the Google picker) and returns whether the member re-authenticated.
  Future<AccountDeletionResult> deleteAccount({
    required bool isAstrologer,
    required Reauthenticate reauthenticate,
  }) async {
    state = const AsyncLoading();
    try {
      if (kBypassAuth) {
        // Demo mode: drop the locally-created profile / astrologer session.
        final demoId = ref.read(myDemoProfileIdProvider);
        if (demoId != null) {
          ref.read(demoProfilesProvider.notifier).remove(demoId);
        }
        ref.read(myDemoProfileIdProvider.notifier).state = null;
        await _endLocalSession();
        state = const AsyncData(null);
        return const AccountDeletionResult(authDeleted: true);
      }

      final repo = ref.read(authRepositoryProvider);
      final flow = AccountDeletionFlow(
        AccountDeletionPorts(
          currentUid: () => repo.currentUserId,
          isAnonymous: () => repo.isGuest,
          providerIds: () => repo.currentProviderIds,
          lastSignInTime: repo.lastSignInTime,
          deleteUserFiles: _deleteUserFiles,
          clearChats: (uid) => _clearChats(uid, isAstrologer: isAstrologer),
          deleteUserData: (uid) async => (await repo.deleteAccountData(uid,
                  isAstrologer: isAstrologer))
              .failedSteps,
          hasResidualData: (uid) =>
              ref.read(firestoreServiceProvider).hasResidualAccountData(uid),
          deleteAuthUser: () async {
            try {
              await repo.deleteAuthUser();
            } on AuthException catch (e) {
              throw DeletionAuthError(e.code, e.message);
            }
          },
          endSession: () async {
            await repo.endSessionAfterDeletion();
            await _endLocalSession();
          },
        ),
        log: (m) => debugPrint('[AccountDeletion] $m'),
      );
      final result = await flow.run(reauthenticate);
      debugPrint('[AccountController] deleteAccount → ${result.outcome} '
          '(authDeleted=${result.authDeleted}, '
          'failedSteps=${result.failedSteps}, '
          'residual=${result.residualData})');
      state = const AsyncData(null);
      return result;
    } catch (e, st) {
      debugPrint('[AccountController] deleteAccount crashed: $e\n$st');
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Clears everything this device still holds for the deleted account — run
  /// only after the Firebase Auth user is gone.
  Future<void> _endLocalSession() async {
    // SharedPreferences holds cached login/role/onboarding state. (This app
    // does not use flutter_secure_storage.)
    await _clearLocalStorage();
    // ...and the IMAGE caches, which SharedPreferences knows nothing about.
    // `cached_network_image` keeps the bytes on disk keyed by URL, and
    // Flutter keeps decoded frames in memory; neither notices that the
    // account they belonged to is gone (spec §4/§27).
    await _clearImageCaches();
    // Reset in-memory session so nothing stale survives into the next login —
    // including the long-lived Matches feed and any profile-wizard data, which
    // are not tied to the auth stream.
    ref.invalidate(currentUserProvider);
    ref.invalidate(myProfileProvider);
    ref.invalidate(viewedProfilesProvider);
    ref.invalidate(discoverProvider);
    ref.invalidate(profileCreationProvider);
  }

  /// Removes the member from shared chat threads while the participant-only
  /// rules still recognise them. A thread is shared, so it is tombstoned (name,
  /// photo and the conversation disappear for the other member) rather than
  /// deleted. Best-effort and logged.
  Future<void> _clearChats(String uid, {required bool isAstrologer}) async {
    if (isAstrologer) return;
    try {
      final failed = await ref.read(chatServiceProvider).tombstoneThreadsFor(uid);
      if (failed != 0) {
        debugPrint('[AccountController] chat tombstone incomplete for $uid '
            '(failed=$failed) — threads may still show this member.');
      }
    } catch (e) {
      debugPrint('[AccountController] chat tombstone skipped: $e');
    }
  }

  /// Deletes every file this member uploaded, while their documents still say
  /// which files those are:
  ///
  ///  * Cloudinary — profile photo, horoscope images and PDFs, and the Aadhaar
  ///    ID-proof images. URLs come from the FULL profile (a hidden photo or
  ///    horoscope is stored in the private copy) and the Aadhaar record.
  ///    Anything the trusted delete function could not remove is queued in
  ///    `cloudinary_cleanup` by the cleanup service, so it stays findable.
  ///  * Firebase Storage — the member's own `profiles/{uid}/` folder, where
  ///    media lived before the move to Cloudinary.
  ///
  /// Never throws: a file that cannot be removed must not strand the member
  /// half-deleted, and every failure is logged.
  Future<void> _deleteUserFiles(String uid) async {
    try {
      final firestore = ref.read(firestoreServiceProvider);
      final profile = await firestore.getFullProfileByUserId(uid);
      final aadhaar = await firestore.getAadhaar(uid).catchError((Object e) {
        debugPrint('[AccountController] Aadhaar record unreadable: $e');
        return null;
      });
      final urls = <String?>[
        if (profile != null) ...[
          profile.profilePhotoUrl,
          ...profile.photos,
          ...profile.horoscope.horoscopeImages,
          ...profile.horoscope.allPdfUrls,
        ],
        aadhaar?.frontUrl,
        aadhaar?.backUrl,
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
    final storageFiles = await FirebaseStorageService.deleteUserFolder(uid);
    if (storageFiles < 0) {
      debugPrint('[AccountController] Firebase Storage cleanup for $uid '
          'incomplete (see log above).');
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
