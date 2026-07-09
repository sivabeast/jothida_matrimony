import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/dev_config.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';

/// The two Matches feed modes (Filter menu on the top compact card).
///  • [compatible] — partner preferences (age + caste mandatory) AND
///    nakshatra compatibility. The DEFAULT on first open.
///  • [all] — partner preferences only; horoscope compatibility is not
///    required (compatible and non-compatible profiles both appear).
enum MatchMode { compatible, all }

/// Persisted Matches mode. Defaults to Compatible Matches (per spec) and
/// remembers the user's last Filter choice across launches.
class MatchModeNotifier extends Notifier<MatchMode> {
  static const _key = 'matches_match_mode';

  @override
  MatchMode build() {
    _restore();
    return MatchMode.compatible; // spec default
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v == 'all') {
        state = MatchMode.all;
      } else if (v == 'compatible') {
        state = MatchMode.compatible;
      }
    } catch (_) {
      // Ignore — keep the default.
    }
  }

  Future<void> set(MatchMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, mode == MatchMode.all ? 'all' : 'compatible');
    } catch (_) {
      // Best-effort; in-memory state already updated.
    }
  }
}

final matchModeProvider =
    NotifierProvider<MatchModeNotifier, MatchMode>(MatchModeNotifier.new);

/// PER-USER browsing progress for the Matches feed.
///
/// Every profile the user swipes past is recorded (persisted per uid), so the
/// next session resumes from the first profile they have NOT seen yet instead
/// of restarting from profile 1. Already-viewed profiles are moved to the END
/// of the feed (never dropped), so nothing is permanently hidden.
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

  /// Clears the history — called when the user has viewed EVERY profile once,
  /// so the rotation restarts from profile 1 and progress tracks again.
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
