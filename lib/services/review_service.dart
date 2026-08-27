import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_update_config.dart';
import 'app_update_service.dart';

/// Things a member can do that make asking for a review reasonable.
///
/// These are all "something good just happened" moments — never the middle of
/// a task. See [ReviewService.recordEngagement] for how they accumulate.
enum ReviewTrigger {
  /// Finished creating their matrimony profile.
  profileCompleted,

  /// An interest they sent was accepted (a real match).
  matchAccepted,

  /// A horoscope report they paid for was delivered.
  reportReady,

  /// An astrology appointment was confirmed.
  appointmentConfirmed,

  /// Ordinary healthy usage — browsing matches.
  browsedMatches,
}

/// Google Play **In-App Review**, asked for at a sensible moment (spec §9–§11).
///
/// This deliberately does NOT build a custom star widget: the goal is a genuine
/// Play Store review, so it calls Play's own sheet. Play decides whether to
/// actually show it — quota, eligibility, already-reviewed — and gives no
/// feedback either way. The code therefore never assumes a dialog appeared; it
/// only records that it asked, so it does not ask again soon.
///
/// Nothing here throws. A device without Play, without network, or with the
/// review API unavailable simply does not get asked.
class ReviewService {
  ReviewService._();

  static final ReviewService instance = ReviewService._();

  final InAppReview _review = InAppReview.instance;

  // ── Persistence keys ──
  static const _pointsKey = 'review_engagement_points';
  static const _askedAtKey = 'review_last_asked_at';
  static const _askedVersionKey = 'review_last_asked_version';
  static const _doneKey = 'review_completed_flow';

  /// Engagement needed before the first ask. Reached by a couple of meaningful
  /// actions, or a longer run of ordinary browsing.
  static const int _pointsNeeded = 5;

  /// Never ask twice inside this window, even across app launches.
  static const Duration _minGap = Duration(days: 60);

  int _weight(ReviewTrigger t) => switch (t) {
        ReviewTrigger.profileCompleted => 3,
        ReviewTrigger.matchAccepted => 3,
        ReviewTrigger.reportReady => 3,
        ReviewTrigger.appointmentConfirmed => 2,
        ReviewTrigger.browsedMatches => 1,
      };

  /// Records that something good happened, and asks for a review when enough
  /// has accumulated.
  ///
  /// Returns TRUE when the ask was actually triggered on this call, so the
  /// caller can mirror that to the account (see `ReviewController`). It is
  /// never a claim that a dialog appeared — Play alone decides that, and tells
  /// nobody.
  ///
  /// Safe to call from anywhere, as often as you like — it is cheap, silent and
  /// self-throttling. Call it AFTER the action has visibly succeeded, never
  /// during registration, payment, booking, chat or profile creation itself
  /// (spec §30).
  Future<bool> recordEngagement(ReviewTrigger trigger) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_doneKey) == true) return false;

      final points = (prefs.getInt(_pointsKey) ?? 0) + _weight(trigger);
      await prefs.setInt(_pointsKey, points);
      if (points < _pointsNeeded) return false;

      if (!await _mayAsk(prefs)) return false;
      await _ask(prefs);
      return true;
    } catch (e) {
      // Review is a nicety; it must never disturb the flow that called it.
      debugPrint('[Review] engagement skipped: $e');
      return false;
    }
  }

  /// Whether the rating flow has been completed on THIS device.
  ///
  /// The device layer only ever answers "yes" — a "no" means "not here", not
  /// "never", which is why the account layer exists (spec §31).
  Future<bool> hasRatedOnThisDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_doneKey) == true;
    } catch (_) {
      return false;
    }
  }

  /// Marks the rating flow complete on this device — used both when the member
  /// rates here and when the ACCOUNT says they already rated elsewhere.
  Future<void> markRatedOnThisDevice() => _markDone();

  /// True when enough time has passed since the last ask.
  Future<bool> _mayAsk(SharedPreferences prefs) async {
    final askedAt = prefs.getInt(_askedAtKey) ?? 0;
    if (askedAt == 0) return true;
    final since = DateTime.now().millisecondsSinceEpoch - askedAt;
    if (since < _minGap.inMilliseconds) return false;
    // A new app version is a fresh reason to ask, but only once the gap above
    // has also elapsed.
    final lastVersion = prefs.getInt(_askedVersionKey) ?? 0;
    final current = await AppUpdateService.instance.installedVersionCode();
    return current == 0 || current != lastVersion;
  }

  Future<void> _ask(SharedPreferences prefs) async {
    // Record BEFORE asking: if Play throws or silently declines, we still must
    // not retry on the next action.
    await prefs.setInt(_askedAtKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(_askedVersionKey,
        await AppUpdateService.instance.installedVersionCode());
    await prefs.setInt(_pointsKey, 0);

    if (!await _review.isAvailable()) {
      debugPrint('[Review] Play in-app review unavailable on this device.');
      return;
    }
    // Play may show nothing at all (quota, already reviewed). There is no
    // result to inspect and that is by design — never treat it as an error.
    await _review.requestReview();
    debugPrint('[Review] review requested (Play decides whether to show it).');
  }

  /// Opens the Play listing so the member can review by hand — for an explicit
  /// "Rate us" menu item, where they ASKED to leave a review and an invisible
  /// no-op would be confusing.
  Future<bool> openStoreListingForReview() async {
    try {
      await _review.openStoreListing();
      await _markDone();
      return true;
    } catch (e) {
      debugPrint('[Review] openStoreListing failed ($e) — using Play URL.');
      final ok = await AppUpdateService.instance
          .openStoreListing(const AppUpdateConfig());
      if (ok) await _markDone();
      return ok;
    }
  }

  Future<void> _markDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_doneKey, true);
    } catch (_) {
      // Not worth surfacing.
    }
  }
}
