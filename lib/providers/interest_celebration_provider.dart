import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/dev_config.dart';
import '../models/interest_model.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';
import 'interest_provider.dart';

/// Interests the SENDER has already been shown the "accepted" celebration for.
///
/// The celebration is a one-time event per interest: the receiver accepts while
/// the sender may be away, the sender sees it once the next time they open the
/// app, and never again. The interest document itself cannot carry the marker —
/// the security rules only let the RECEIVER write to it — so the seen-set is
/// stored per signed-in uid in SharedPreferences.
class CelebratedInterestsNotifier extends Notifier<Set<String>> {
  static const int _maxTracked = 300;

  /// Completes once SharedPreferences has been read, so the Home page never
  /// celebrates an interest that was in fact already seen (which is exactly
  /// what an un-awaited restore would cause on a cold start).
  Completer<void> _hydrated = Completer<void>();
  Future<void> get ready => _hydrated.future;

  String? get _uid => kBypassAuth
      ? kDemoUserId
      : ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;

  String get _key => 'celebrated_interests_${_uid ?? 'anon'}';

  @override
  Set<String> build() {
    _hydrated = Completer<void>();
    _restore();
    return const {};
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = (prefs.getStringList(_key) ?? const []).toSet();
    } catch (_) {
      // Ignore — an unreadable store just means the celebration may replay
      // once, which is far better than swallowing it entirely.
    } finally {
      if (!_hydrated.isCompleted) _hydrated.complete();
    }
  }

  /// Records that the sender has now SEEN the celebration for [interestId].
  Future<void> markCelebrated(String interestId) async {
    if (interestId.isEmpty || state.contains(interestId)) return;
    final updated = [...state, interestId];
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

final celebratedInterestsProvider =
    NotifierProvider<CelebratedInterestsNotifier, Set<String>>(
        CelebratedInterestsNotifier.new);

/// Interests THIS user sent that have since been ACCEPTED and whose celebration
/// has not been shown yet — oldest acceptance first, so a backlog is replayed
/// in the order it happened and nothing is lost.
///
/// Empty until the seen-set has hydrated; the Home page awaits
/// [CelebratedInterestsNotifier.ready] before reading it.
final pendingAcceptedInterestsProvider =
    Provider.autoDispose<List<InterestModel>>((ref) {
  final sent =
      ref.watch(sentInterestsProvider).valueOrNull ?? const <InterestModel>[];
  final seen = ref.watch(celebratedInterestsProvider);
  final pending = sent
      .where((i) => i.isAccepted && !seen.contains(i.id))
      .toList()
    ..sort((a, b) => (a.respondedAt ?? a.sentAt)
        .compareTo(b.respondedAt ?? b.sentAt));
  return pending;
});
