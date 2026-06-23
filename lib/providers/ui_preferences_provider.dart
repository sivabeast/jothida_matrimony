import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the Matches feed lays profiles out.
///  • [card] — one full-screen swipeable "profile book" page at a time.
///  • [grid] — a 2-column grid of compact cards.
enum FeedViewMode { card, grid }

/// Persisted Matches view mode, remembered across app launches.
///
/// The user's last choice (Card / Grid) is restored on the next launch so the
/// feed opens in the layout they prefer.
class FeedViewModeNotifier extends Notifier<FeedViewMode> {
  static const _key = 'feed_view_mode';

  @override
  FeedViewMode build() {
    // Default to Card; asynchronously restore the saved choice.
    _restore();
    return FeedViewMode.card;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v == 'grid') {
        state = FeedViewMode.grid;
      } else if (v == 'card') {
        state = FeedViewMode.card;
      }
    } catch (_) {
      // Ignore — keep the default.
    }
  }

  Future<void> set(FeedViewMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode == FeedViewMode.grid ? 'grid' : 'card');
    } catch (_) {
      // Persisting is best-effort; in-memory state already updated.
    }
  }

  void toggle() =>
      set(state == FeedViewMode.grid ? FeedViewMode.card : FeedViewMode.grid);
}

final feedViewModeProvider =
    NotifierProvider<FeedViewModeNotifier, FeedViewMode>(
        FeedViewModeNotifier.new);

/// Whether profiles the user has already expressed interest in are hidden from
/// the Matches feed. Defaults to ON (per spec), remembered across launches.
class HideInterestedNotifier extends Notifier<bool> {
  static const _key = 'hide_interested_profiles';

  @override
  bool build() {
    _restore();
    return true; // default ON
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_key);
      if (v != null) state = v;
    } catch (_) {
      // Ignore — keep the default.
    }
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {
      // Best-effort.
    }
  }

  void toggle() => set(!state);
}

final hideInterestedProvider =
    NotifierProvider<HideInterestedNotifier, bool>(HideInterestedNotifier.new);
