import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider.dart';

/// How long a guest is left alone between login prompts.
const Duration kGuestLoginPromptInterval = Duration(minutes: 10);

/// Time-based gate for the GUEST "please log in" prompt.
///
/// The permanent guest sign-up card was removed from Home; this replaces it
/// with a prompt that appears roughly once every [kGuestLoginPromptInterval]
/// and never more often than that. Two properties matter:
///
///   • it is TIME based, not rebuild based — navigating between tabs, pulling
///     to refresh or rotating the device cannot bring it back early; and
///   • the "last shown" stamp is PERSISTED, so closing and reopening the app
///     does not reset the clock either.
///
/// A signed-in member never sees it: [GuestLoginPromptController.shouldShow]
/// short-circuits on the authentication state, and the host widget stops its
/// timer the moment the guest logs in.
class GuestLoginPromptStore {
  static const _key = 'guest_login_prompt_last_shown_ms';

  const GuestLoginPromptStore();

  /// Epoch milliseconds of the last prompt, or null if it has never shown.
  Future<int?> lastShownMs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_key);
      return (v == null || v <= 0) ? null : v;
    } catch (e) {
      debugPrint('[GuestLoginPrompt] read failed: $e');
      return null;
    }
  }

  Future<void> markShown([DateTime? now]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _key, (now ?? DateTime.now()).millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[GuestLoginPrompt] write failed: $e');
    }
  }

  /// Clears the stamp so a future guest session starts fresh. Called after a
  /// successful login, since the prompt is meaningless for a member.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('[GuestLoginPrompt] clear failed: $e');
    }
  }
}

/// Pure decision function, extracted so the interval rule is unit-testable.
///
/// [lastShownMs] is null the very first time. A guest is prompted ONCE per app
/// launch, as soon as Home is up (spec §14), and then only every [interval]
/// while they keep browsing in that same session.
///
/// [promptedThisLaunch] is what separates the two: pass `false` for the first
/// check after Home appears — an app OPEN always earns the prompt, even if the
/// guest was already prompted nine minutes ago in the previous session — and
/// `true` for every check after that, which is where the interval takes over.
/// It defaults to `true` so a caller that only cares about the interval rule
/// reads exactly as before.
bool shouldShowGuestLoginPrompt({
  required bool isGuest,
  required int? lastShownMs,
  required DateTime now,
  Duration interval = kGuestLoginPromptInterval,
  bool promptedThisLaunch = true,
}) {
  if (!isGuest) return false;
  if (!promptedThisLaunch) return true;
  if (lastShownMs == null) return true;
  final last = DateTime.fromMillisecondsSinceEpoch(lastShownMs);
  // A stamp in the future (device clock moved backwards) is treated as "due"
  // rather than locking the prompt out for ever.
  if (last.isAfter(now)) return true;
  return now.difference(last) >= interval;
}

final guestLoginPromptStoreProvider =
    Provider<GuestLoginPromptStore>((ref) => const GuestLoginPromptStore());

/// Whether the login prompt has already been shown in THIS app launch.
///
/// Deliberately in-memory only: it must reset on every cold start, because
/// "show it when the app opens" (spec §14) is exactly a per-launch event. The
/// persisted stamp in [GuestLoginPromptStore] governs what happens afterwards,
/// within the session.
final guestPromptShownThisLaunchProvider = StateProvider<bool>((ref) => false);

/// Watches the auth state and wipes the stamp once the visitor is a member, so
/// the prompt can never resurface for a signed-in account.
final guestLoginPromptResetProvider = Provider<void>((ref) {
  final isGuest = ref.watch(isGuestProvider);
  if (!isGuest) {
    unawaited(ref.read(guestLoginPromptStoreProvider).clear());
  }
});
