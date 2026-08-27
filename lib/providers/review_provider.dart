import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/review_service.dart';
import 'auth_provider.dart';
import 'service_providers.dart';

/// The rating ask, bound to the signed-in ACCOUNT (spec §29–§32).
///
/// [ReviewService] on its own only knows this device: it stores its cooldown
/// and its "already asked" marker in SharedPreferences, which a reinstall, a
/// second phone or a cache clear all wipe. That is fine for THROTTLING, but
/// not for the one rule that must never break — **a member who has already
/// rated is never asked again**. That fact belongs to the account, so it is
/// mirrored to `users/{uid}` and read back from there.
///
/// The two layers answer different questions, and both are consulted:
///
///   * account (Firestore) — "has this person ever rated?" Survives reinstalls
///     and follows them to a new device.
///   * device (prefs)      — "have we asked recently on THIS device?" Keeps a
///     guest, or an offline session, from being nagged.
///
/// A guest has no account, so only the device layer applies; nothing here ever
/// writes an anonymous session's state to Firestore.
class ReviewController {
  ReviewController(this._ref);

  final Ref _ref;

  /// Cached per session so a rated member costs one read, not one per trigger.
  bool? _ratedCache;

  String? get _uid => _ref.read(memberUidProvider);

  /// Records engagement and, when enough has built up, asks for the review.
  ///
  /// Safe to call from anywhere, as often as you like — cheap, silent and
  /// self-throttling. Never call it mid-task: only after something good has
  /// visibly succeeded (spec §30).
  Future<void> record(ReviewTrigger trigger) async {
    try {
      if (await hasRated()) return; // spec §31 — never ask a rated member.
      final asked = await ReviewService.instance.recordEngagement(trigger);
      if (asked) await _stampAsked();
    } catch (e) {
      // The rating ask is a nicety; it must never disturb the flow that called
      // it.
      debugPrint('[Review] engagement skipped: $e');
    }
  }

  /// "Rate this app" chosen explicitly from the menu — opens the Play listing
  /// and records the account as rated, so the automatic prompt stops for good.
  Future<bool> openStoreListing() async {
    final ok = await ReviewService.instance.openStoreListingForReview();
    if (ok) await markRated();
    return ok;
  }

  /// True once this ACCOUNT has completed the rating flow.
  Future<bool> hasRated() async {
    final cached = _ratedCache;
    if (cached != null) return cached;

    // The device marker is authoritative in the "yes" direction even for a
    // guest: whoever is holding the phone has already been through the flow.
    if (await ReviewService.instance.hasRatedOnThisDevice()) {
      _ratedCache = true;
      return true;
    }

    final uid = _uid;
    if (uid == null) return false; // guest — device layer only
    try {
      final rated =
          await _ref.read(firestoreServiceProvider).hasRatedApp(uid);
      _ratedCache = rated;
      // Bring the device in line so a rated member is not asked again even
      // while offline later.
      if (rated) await ReviewService.instance.markRatedOnThisDevice();
      return rated;
    } catch (e) {
      debugPrint('[Review] account rating status unavailable: $e');
      return false;
    }
  }

  /// Marks the account (and this device) as having rated — the terminal state.
  Future<void> markRated() async {
    _ratedCache = true;
    await ReviewService.instance.markRatedOnThisDevice();
    final uid = _uid;
    if (uid == null) return;
    try {
      await _ref.read(firestoreServiceProvider).setRatingStatus(
            uid: uid,
            rated: true,
          );
    } catch (e) {
      debugPrint('[Review] could not save the account rating status: $e');
    }
  }

  /// Records that the member was ASKED, without claiming they rated. Play's
  /// sheet gives no result, so this is all that can honestly be recorded; the
  /// cooldown then keeps the next ask far away (spec §32).
  Future<void> _stampAsked() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _ref.read(firestoreServiceProvider).setRatingStatus(
            uid: uid,
            rated: false,
          );
    } catch (e) {
      debugPrint('[Review] could not save the rating prompt time: $e');
    }
  }
}

final reviewControllerProvider =
    Provider<ReviewController>(ReviewController.new);
