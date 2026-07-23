import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/dev_config.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';

/// PER-USER browsing progress for the Matches feed.
///
/// Every profile the user swipes past is recorded (persisted per uid). The
/// history is **never** cleared automatically: a viewed profile stays in the
/// feed forever so the user can always swipe back to it. Its only job is to
/// answer "which profiles has this member already seen?", which — together with
/// [LastViewedProfileNotifier] — is what lets browsing resume instead of
/// restarting at profile 1.
class ViewedProfilesNotifier extends Notifier<Set<String>> {
  static const _maxTracked = 1000; // oldest entries fall off beyond this

  String? get _uid => kBypassAuth
      ? kDemoUserId
      : ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;

  String get _key => 'viewed_profiles_${_uid ?? 'anon'}';

  @override
  Set<String> build() {
    _restore();
    return const {};
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = (prefs.getStringList(_key) ?? const []).toSet();
    } catch (_) {
      // Ignore — start with an empty history.
    }
  }

  /// Wipes the history. Only for an explicit user action (e.g. "start over") —
  /// browsing must NEVER reset itself just because every profile has been seen.
  Future<void> resetHistory() async {
    state = const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Best-effort; in-memory state already cleared.
    }
  }

  /// Records that the user has seen [profileId]. No-op when already recorded.
  Future<void> markViewed(String profileId) async {
    if (profileId.isEmpty || state.contains(profileId)) return;
    final updated = [...state, profileId];
    if (updated.length > _maxTracked) {
      updated.removeRange(0, updated.length - _maxTracked);
    }
    state = updated.toSet();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, updated);
    } catch (_) {
      // Best-effort; in-memory state already updated.
    }
  }
}

final viewedProfilesProvider =
    NotifierProvider<ViewedProfilesNotifier, Set<String>>(
        ViewedProfilesNotifier.new);

/// The EXACT profile the user was last looking at, persisted per uid.
///
/// This is the primary resume anchor. Resolving the saved *profile id* back to
/// an index (rather than storing the index itself) keeps the resume position
/// correct even when the ranked list shifts — a new profile ranking above the
/// current one, a member going inactive, or a filter change would all invalidate
/// a raw index.
///
/// `null` means "nothing recorded yet" — the feed then starts at the first
/// unseen profile, which for a first-ever session is profile 1.
class LastViewedProfileNotifier extends Notifier<String?> {
  String? get _uid => kBypassAuth
      ? kDemoUserId
      : ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;

  String get _key => 'last_viewed_profile_${_uid ?? 'anon'}';

  @override
  String? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null && saved.isNotEmpty) state = saved;
    } catch (_) {
      // Ignore — resume falls back to the first unseen profile.
    }
  }

  Future<void> set(String profileId) async {
    if (profileId.isEmpty || state == profileId) return;
    state = profileId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, profileId);
    } catch (_) {
      // Best-effort; in-memory state already updated.
    }
  }
}

final lastViewedProfileProvider =
    NotifierProvider<LastViewedProfileNotifier, String?>(
        LastViewedProfileNotifier.new);

/// Where browsing should CONTINUE inside [profileIds].
///
/// Resolution order:
///   1. the exact profile the user was last on ([lastViewed]) — the true
///      "resume where I left off";
///   2. otherwise the first profile not in [viewed] — the first unseen one;
///   3. otherwise the LAST profile.
///
/// Step 3 is the spec's "5 profiles, all 5 viewed" case: stay on the last
/// profile (the user can still swipe back), never restart at profile 1 and never
/// fall through to an empty state.
///
/// Pure and index-safe: always returns a valid index for a non-empty list, and 0
/// for an empty one.
int resolveResumeIndex({
  required List<String> profileIds,
  required Set<String> viewed,
  String? lastViewed,
}) {
  if (profileIds.isEmpty) return 0;
  if (lastViewed != null) {
    final at = profileIds.indexOf(lastViewed);
    if (at >= 0) return at;
  }
  final firstUnseen = profileIds.indexWhere((id) => !viewed.contains(id));
  if (firstUnseen >= 0) return firstUnseen;
  return profileIds.length - 1;
}
