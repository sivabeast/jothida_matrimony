import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/dev_config.dart';
import '../models/profile_model.dart';
import '../services/cloudinary/cloudinary_storage_service.dart';
import '../widgets/common/network_photo.dart' show evictCachedImage;
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Persists a single profile-section edit.
///
/// [updated] is the full edited model (used for the in-memory demo store);
/// [patch] is the Firestore field subset for just that section (used in real
/// mode). After saving, `myProfileProvider` is re-read so the completion
/// percentage and the Home card update immediately.
class ProfileEditController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> save({
    required ProfileModel updated,
    required Map<String, dynamic> patch,
  }) async {
    state = const AsyncLoading();
    try {
      final current = ref.read(myProfileProvider).valueOrNull;
      if (current == null) throw StateError('No profile to update');
      if (kBypassAuth) {
        ref.read(demoProfilesProvider.notifier).upsert(updated);
      } else {
        await ref
            .read(profileRepositoryProvider)
            .updateProfile(current.id, patch);
        // Keep the denormalized mirrors of the member's IDENTITY in step with
        // the profile they just saved (spec §2/§25). The profile document is
        // the source of truth and every screen resolves from it; these are
        // caches that exist for first paint, and a cache nobody refreshes is
        // exactly how an old name and an old photo survive in chat.
        await syncProfileIdentity(ref, before: current, after: updated);
        // ONE photo per member (spec §6/§24): the previous Cloudinary asset is
        // retired only AFTER the new reference is safely stored, so a failed
        // upload or a failed write can never leave the member with no photo.
        //
        // Gated on the PATCH, not on a model diff. Destroying an image is
        // irreversible, so it happens only when the caller actually said it was
        // changing the photo — never because some other section edit happened
        // to hand over a model whose photo field was not carried across.
        if (patch.containsKey('profilePhotoUrl')) {
          await retireReplacedPhoto(ref,
              oldUrl: current.profilePhotoUrl,
              newUrl: updated.profilePhotoUrl,
              reason: 'profile_photo_replaced:${updated.userId}');
        }
        ref.invalidate(myProfileProvider);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final profileEditControllerProvider =
    NotifierProvider<ProfileEditController, AsyncValue<void>>(
        ProfileEditController.new);

/// Propagates a member's CURRENT name / photo out to the denormalized copies
/// of it (spec §2/§8/§25), whenever either actually changed.
///
/// Two copies exist, both purely for rendering speed:
///
///   * `users/{uid}.photoUrl` — read by the Home header and the admin lists
///     alongside the profile; and
///   * `chats/{threadId}.participantNames/Photos` — read by the Chats list.
///
/// Neither is authoritative and nothing breaks if a refresh fails, so this is
/// best-effort by design: a chat that could not be updated must never make a
/// successful profile save look like it failed. It is a no-op when nothing
/// identity-related changed, so an ordinary section edit costs no writes.
Future<void> syncProfileIdentity(
  Ref ref, {
  required ProfileModel before,
  required ProfileModel after,
}) async {
  final uid = after.userId.trim();
  if (uid.isEmpty) return;
  final name = after.fullName.trim();
  final photo = (after.profilePhotoUrl ?? '').trim();
  final nameChanged = name != before.fullName.trim();
  final photoChanged = photo != (before.profilePhotoUrl ?? '').trim();
  if (!nameChanged && !photoChanged) return;

  if (photoChanged) {
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateUserPhoto(uid, photo.isEmpty ? null : photo);
    } catch (e) {
      debugPrint('[ProfileIdentity] users/$uid photo mirror skipped: $e');
    }
  }
  try {
    final updated = await ref
        .read(chatServiceProvider)
        .syncParticipantIdentity(uid: uid, name: name, photoUrl: photo);
    debugPrint('[ProfileIdentity] $uid: refreshed $updated chat thread(s).');
  } catch (e) {
    debugPrint('[ProfileIdentity] chat identity sync skipped: $e');
  }
}

/// Retires the profile photo a member just replaced or removed (spec §6/§24).
///
/// Called only AFTER the new reference is stored, which is the order that
/// matters: deleting first would leave a member with no photo at all whenever
/// the upload or the Firestore write failed. Doing it afterwards means the
/// worst case is an orphan — and even that is recorded, because the cleanup
/// service queues whatever it could not delete instead of dropping it.
///
/// Cloudinary's destroy API has to be SIGNED, so the delete itself runs in the
/// `deleteCloudinaryAssets` Cloud Function; the API secret never ships in the
/// app (spec §32).
///
/// No-ops when the URL did not change, when there was no previous photo, or
/// when the previous URL is not a Cloudinary asset (a legacy Firebase Storage
/// link, say) — [CloudinaryStorageService.deleteFiles] skips those itself.
Future<void> retireReplacedPhoto(
  Ref ref, {
  required String? oldUrl,
  required String? newUrl,
  required String reason,
}) async {
  final previous = (oldUrl ?? '').trim();
  if (previous.isEmpty || previous == (newUrl ?? '').trim()) return;
  // The old image must also stop being served from the on-device caches, or
  // the member keeps seeing it after it is gone (spec §25).
  await evictCachedImage(previous);
  try {
    final storage = ref.read(storageServiceProvider);
    if (storage is! CloudinaryStorageService) return;
    final deleted = await storage.deleteFiles([previous], reason: reason);
    debugPrint('[ProfilePhoto] retired $deleted previous asset(s) ($reason).');
  } catch (e) {
    debugPrint('[ProfilePhoto] previous-asset cleanup skipped: $e');
  }
}
