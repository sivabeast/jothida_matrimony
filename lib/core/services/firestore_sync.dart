import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../utils/firestore_write.dart';

// Re-exported so a single import gives callers both halves of the sync model:
// the realtime READ helpers below and the canonical Firestore-first WRITE.
export '../utils/firestore_write.dart' show commitWrite, WriteResult;

/// Centralized Firestore data-synchronization helpers — the one reusable place
/// the app turns Firestore into live, self-refreshing state (spec §19).
///
/// The model this enforces across every CRUD module:
///
///  • **Firestore is the source of truth.** Reads are realtime `.snapshots()`
///    listeners, so when a document is created / updated / DELETED the stream
///    re-emits and every widget watching it rebuilds with fresh data — the
///    local cache is refreshed and removed rows drop out automatically, with no
///    manual cache bookkeeping (§1/§2/§3). Firestore's own offline persistence
///    (enabled in `main`) backs the cache and offline sync; the cache is a
///    performance layer, never primary storage (§21).
///
///  • **Writes go through [commitWrite]** (re-exported here): a Firestore-first,
///    offline-aware write that resolves `acknowledged` on a server ack or
///    `queued` when offline (already in the cache, will sync), and rethrows a
///    real error (e.g. `permission-denied`) so the UI can surface it instead of
///    silently diverging from the server.
///
/// Per-document parsing is defensive: one malformed record is skipped (and
/// logged) rather than blanking the whole list — the pattern the admin lists
/// already relied on, centralized here so every stream is equally robust.
///
/// Riverpod's `StreamProvider` is the delivery mechanism to the UI; these
/// helpers standardize what goes INTO those providers so new CRUD modules stay
/// consistent without re-implementing snapshot plumbing.
class FirestoreSync {
  const FirestoreSync._();

  /// A live list from [query]: re-emits on every change, maps each doc with
  /// [fromDoc], skips (and logs) any doc that fails to parse, optionally keeps
  /// only those matching [where], and applies an optional client-side [sort].
  ///
  /// Prefer the client-side [sort] over a Firestore `orderBy`: an `orderBy`
  /// silently EXCLUDES documents missing the ordered field and can require a
  /// composite index, both of which have blanked admin lists before.
  static Stream<List<T>> collectionStream<T>(
    Query<Map<String, dynamic>> query, {
    required T Function(DocumentSnapshot<Map<String, dynamic>> doc) fromDoc,
    int Function(T a, T b)? sort,
    bool Function(T item)? where,
    String label = 'collection',
  }) {
    return query.snapshots().map((snap) {
      final out = <T>[];
      for (final d in snap.docs) {
        try {
          final item = fromDoc(d);
          if (where == null || where(item)) out.add(item);
        } catch (e) {
          debugPrint('[FirestoreSync] $label: skipped ${d.id}: $e');
        }
      }
      if (sort != null) out.sort(sort);
      return out;
    });
  }

  /// A live single document mapped with [fromDoc]; emits null when the document
  /// does not exist (or fails to parse), so a deletion propagates cleanly.
  static Stream<T?> docStream<T>(
    DocumentReference<Map<String, dynamic>> ref, {
    required T Function(DocumentSnapshot<Map<String, dynamic>> doc) fromDoc,
    String label = 'doc',
  }) {
    return ref.snapshots().map((d) {
      if (!d.exists) return null;
      try {
        return fromDoc(d);
      } catch (e) {
        debugPrint('[FirestoreSync] $label: parse failed ${d.id}: $e');
        return null;
      }
    });
  }
}
