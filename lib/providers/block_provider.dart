import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/blocked_entry.dart';
import 'auth_provider.dart';
import 'service_providers.dart';

/// User ↔ user blocking (spec §6).
///
/// A block hides the other person from Matches & Search, and prevents chat and
/// interest in BOTH directions. State comes from the `blocks` collection via two
/// streams (whom I blocked, and who blocked me), unioned for the hide logic.

/// UIDs the signed-in user has blocked. Drives the Block/Unblock toggle label
/// and prevents the user *initiating* contact.
final myBlockedUidsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(<String>{});
  return ref.watch(firestoreServiceProvider).watchBlockedByMe(uid);
});

/// UIDs that have blocked the signed-in user.
final whoBlockedMeProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(<String>{});
  return ref.watch(firestoreServiceProvider).watchWhoBlockedMe(uid);
});

/// The signed-in user's blocked users WITH block dates, newest first — feeds
/// the user-facing Blocked Users page.
final myBlocksProvider = StreamProvider.autoDispose<List<BlockedEntry>>((ref) {
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const <BlockedEntry>[]);
  return ref.watch(firestoreServiceProvider).watchMyBlocks(uid);
});

/// Union of both directions — anyone here is hidden from the feed/search and
/// can neither chat with nor send an interest to the signed-in user.
final blockedUidsProvider = Provider.autoDispose<Set<String>>((ref) {
  final mine = ref.watch(myBlockedUidsProvider).valueOrNull ?? const <String>{};
  final them = ref.watch(whoBlockedMeProvider).valueOrNull ?? const <String>{};
  if (mine.isEmpty && them.isEmpty) return const <String>{};
  return {...mine, ...them};
});

/// Whether the signed-in user has blocked [targetUid] (for the toggle state).
final hasBlockedProvider = Provider.autoDispose.family<bool, String>((ref, uid) {
  return (ref.watch(myBlockedUidsProvider).valueOrNull ?? const <String>{})
      .contains(uid);
});

class BlockController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  String? get _myUid => ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;

  Future<void> block(String targetUid) async {
    final me = _myUid;
    if (me == null || targetUid.isEmpty || targetUid == me) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).blockUserId(me, targetUid));
  }

  Future<void> unblock(String targetUid) async {
    final me = _myUid;
    if (me == null || targetUid.isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).unblockUserId(me, targetUid));
  }
}

final blockControllerProvider =
    NotifierProvider<BlockController, AsyncValue<void>>(BlockController.new);

/// Convenience: is contact with [otherUid] blocked in either direction?
bool isContactBlocked(WidgetRef ref, String otherUid) {
  if (otherUid.isEmpty) return false;
  final blocked = ref.read(blockedUidsProvider);
  final result = blocked.contains(otherUid);
  if (result) debugPrint('[Block] contact with $otherUid is blocked');
  return result;
}
