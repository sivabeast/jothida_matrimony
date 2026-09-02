/// **Five NEW profiles per day** (spec §8).
///
/// The distinction this file exists to protect is between DISCOVERING a profile
/// and LOOKING AT one:
///
///  * Discovering a profile the member has never seen before costs one of the
///    day's five. When they are gone, the sixth new profile is locked until the
///    next reset and a countdown says exactly when that is (§8A/§8B).
///  * Re-opening a profile they have already seen costs NOTHING, for ever, as
///    many times as they like (§8D/§8E). Swiping back through yesterday's five
///    is free.
///
/// Because the set of already-seen ids is kept — and never cleared — tomorrow
/// does not restart at profile 1. Yesterday's five are all "seen", so the next
/// NEW profile is the sixth (§8C).
///
/// **Where the state lives.** Both: Firestore is the record (`profile_browsing/
/// {uid}`), SharedPreferences is the cache. The remote copy is what makes the
/// limit real — it survives a reinstall, a cleared cache and a second device,
/// so the quota cannot be reset by wiping app data. The local copy is what
/// makes the feed instant and keeps it working offline. On a conflict the
/// HIGHER count and the UNION of seen ids win, because both errors are only
/// safe in one direction: briefly over-counting shows a countdown that clears
/// itself at the next reset, whereas under-counting hands out unlimited free
/// profiles.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/dev_config.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';

/// Profiles a member may newly discover per day.
const int kDailyNewProfileLimit = 5;

/// Hour of the LOCAL day at which the allowance resets. Midnight; kept as a
/// constant so the countdown and the reset can never disagree about it.
const int kQuotaResetHour = 0;

/// `YYYY-MM-DD` in LOCAL time — the day a view is counted against.
///
/// Local, not UTC, because "today" means the member's today: an IST user
/// browsing at 1 a.m. is on a new day, and telling them otherwise would look
/// like the app had lost their allowance.
String quotaDayKey(DateTime at) {
  final d = at.subtract(Duration(hours: kQuotaResetHour));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// When the allowance next refills, given [now].
DateTime nextQuotaResetAt(DateTime now) {
  final todayReset =
      DateTime(now.year, now.month, now.day, kQuotaResetHour);
  return now.isBefore(todayReset)
      ? todayReset
      : todayReset.add(const Duration(days: 1));
}

/// One member's browsing allowance and history.
@immutable
class DailyProfileQuota {
  /// The day [newViewsToday] belongs to. A different key means the count is
  /// stale and reads as zero.
  final String dayKey;

  /// New profiles discovered during [dayKey].
  final int newViewsToday;

  /// Every profile id ever seen. Never pruned by a day roll-over — this is what
  /// makes tomorrow continue instead of restarting (§8C).
  final Set<String> seen;

  /// Whether the state has finished loading. Until it has, nothing is locked:
  /// blocking a member on a guess would be the worst possible failure.
  final bool loaded;

  const DailyProfileQuota({
    this.dayKey = '',
    this.newViewsToday = 0,
    this.seen = const {},
    this.loaded = false,
  });

  /// The count that applies RIGHT NOW — zero once the day has rolled over,
  /// without needing a write to make it so.
  int usedAt(DateTime now) => dayKey == quotaDayKey(now) ? newViewsToday : 0;

  int remainingAt(DateTime now) =>
      (kDailyNewProfileLimit - usedAt(now)).clamp(0, kDailyNewProfileLimit);

  bool hasSeen(String profileId) => seen.contains(profileId);

  DailyProfileQuota copyWith({
    String? dayKey,
    int? newViewsToday,
    Set<String>? seen,
    bool? loaded,
  }) =>
      DailyProfileQuota(
        dayKey: dayKey ?? this.dayKey,
        newViewsToday: newViewsToday ?? this.newViewsToday,
        seen: seen ?? this.seen,
        loaded: loaded ?? this.loaded,
      );
}

/// How many ids are kept remotely. Comfortably more than anyone will browse,
/// and small enough that the document stays a few tens of kilobytes.
const int _kMaxRemoteSeen = 600;

/// Owns the allowance: loads it, spends it, and writes it back.
class DailyProfileQuotaNotifier extends Notifier<DailyProfileQuota> {
  Completer<void> _hydrated = Completer<void>();

  /// Completes once the stored state has been read. Callers that decide
  /// anything about locking MUST await this — acting on the empty initial state
  /// would treat a returning member as brand new.
  Future<void> get restored => _hydrated.future;

  String? get _uid => kBypassAuth ? kDemoUserId : ref.watch(memberUidProvider);

  String get _prefsKey => 'profile_quota_${_uid ?? 'anon'}';

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _uid;
    if (uid == null || kBypassAuth) return null;
    return FirebaseFirestore.instance.collection('profile_browsing').doc(uid);
  }

  @override
  DailyProfileQuota build() {
    _hydrated = Completer<void>();
    _restore();
    return const DailyProfileQuota();
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> _restore() async {
    var loaded = const DailyProfileQuota(loaded: true);
    try {
      loaded = _merge(loaded, await _readLocal());
    } catch (_) {
      // A missing/corrupt cache is not an error — the remote copy decides.
    }
    try {
      final remote = await _readRemote();
      if (remote != null) loaded = _merge(loaded, remote);
    } catch (e) {
      // Offline, or a rules denial for a guest. The local copy still applies,
      // which is the whole reason it is kept.
      debugPrint('[Quota] remote read skipped: $e');
    }
    state = loaded;
    if (!_hydrated.isCompleted) _hydrated.complete();
    // Push the merged view back so the two copies converge.
    unawaited(_persist(state));
  }

  /// Conflict resolution: keep the higher count for the CURRENT day and the
  /// union of everything seen. Never the lower — see the class doc.
  DailyProfileQuota _merge(DailyProfileQuota a, DailyProfileQuota b) {
    final today = quotaDayKey(DateTime.now());
    final used = [a.usedAt(DateTime.now()), b.usedAt(DateTime.now())]
        .reduce((x, y) => x > y ? x : y);
    return DailyProfileQuota(
      dayKey: today,
      newViewsToday: used,
      seen: {...a.seen, ...b.seen},
      loaded: true,
    );
  }

  Future<DailyProfileQuota> _readLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey);
    // Layout: [dayKey, count, ...ids]. A plain list keeps this readable in the
    // debugger and avoids a JSON parse on the startup path.
    if (raw == null || raw.length < 2) {
      // Fall back to the pre-quota history so an existing member's already-seen
      // profiles are not suddenly "new" again after this update ships.
      final legacy = prefs.getStringList('viewed_profiles_${_uid ?? 'anon'}');
      return DailyProfileQuota(seen: (legacy ?? const []).toSet(), loaded: true);
    }
    return DailyProfileQuota(
      dayKey: raw[0],
      newViewsToday: int.tryParse(raw[1]) ?? 0,
      seen: raw.skip(2).toSet(),
      loaded: true,
    );
  }

  Future<DailyProfileQuota?> _readRemote() async {
    final doc = _doc;
    if (doc == null) return null;
    final snap = await doc.get().timeout(const Duration(seconds: 8));
    final d = snap.data();
    if (d == null) return null;
    return DailyProfileQuota(
      dayKey: '${d['dayKey'] ?? ''}',
      newViewsToday: (d['newViewsToday'] is num)
          ? (d['newViewsToday'] as num).toInt()
          : 0,
      seen: (d['seen'] is List)
          ? (d['seen'] as List).map((e) => '$e').toSet()
          : const {},
      loaded: true,
    );
  }

  // ── Spending ──────────────────────────────────────────────────────────────

  /// Records that [profileId] was viewed, and returns whether it was allowed.
  ///
  /// Already seen → always true and nothing is spent (§8E). New and within the
  /// allowance → true, one spent. New and over the allowance → **false**, and
  /// the caller must not reveal it.
  Future<bool> registerView(String profileId) async {
    if (profileId.isEmpty) return true;
    await restored;
    final now = DateTime.now();
    final s = state;
    if (s.hasSeen(profileId)) return true; // free, for ever
    if (s.remainingAt(now) <= 0) return false; // locked until the reset

    final seen = {...s.seen, profileId};
    state = s.copyWith(
      dayKey: quotaDayKey(now),
      newViewsToday: s.usedAt(now) + 1,
      seen: seen,
    );
    unawaited(_persist(state));
    return true;
  }

  /// Whether [profileId] may be shown right now, WITHOUT spending anything.
  /// Used to decide where the feed locks before the member swipes into it.
  bool canView(String profileId) {
    if (!state.loaded) return true; // never lock on unloaded state
    return state.hasSeen(profileId) ||
        state.remainingAt(DateTime.now()) > 0;
  }

  // ── Writing ───────────────────────────────────────────────────────────────

  Future<void> _persist(DailyProfileQuota q) async {
    final ids = q.seen.toList();
    final trimmed = ids.length > _kMaxRemoteSeen
        ? ids.sublist(ids.length - _kMaxRemoteSeen)
        : ids;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _prefsKey, [q.dayKey, '${q.newViewsToday}', ...trimmed]);
    } catch (_) {
      // In-memory state is already correct; the remote write still runs.
    }
    final doc = _doc;
    if (doc == null) return;
    try {
      await doc.set({
        'dayKey': q.dayKey,
        'newViewsToday': q.newViewsToday,
        'seen': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
    } catch (e) {
      // Offline or denied — the local copy carries the limit until the next
      // successful sync. Never surfaced to the member.
      debugPrint('[Quota] remote write skipped: $e');
    }
  }
}

final dailyProfileQuotaProvider =
    NotifierProvider<DailyProfileQuotaNotifier, DailyProfileQuota>(
        DailyProfileQuotaNotifier.new);

/// A once-per-second tick, so a countdown re-renders without every screen
/// owning a Timer. Auto-disposes the moment nothing is watching it.
final quotaCountdownProvider = StreamProvider.autoDispose<Duration>((ref) {
  Duration remaining() {
    final now = DateTime.now();
    final left = nextQuotaResetAt(now).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  return Stream<Duration>.periodic(
          const Duration(seconds: 1), (_) => remaining())
      .distinct();
});

/// "23:45:18" — always three fields, so the digits do not jump about as the
/// hours tick down.
String formatCountdown(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return '${two(h)}:${two(m)}:${two(s)}';
}
