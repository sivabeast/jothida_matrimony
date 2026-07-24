import 'dart:async';

/// Outcome of a bounded Firestore write.
enum WriteResult {
  /// The server acknowledged the write within the timeout.
  acknowledged,

  /// The server did not acknowledge in time, but the write has been committed
  /// to the local offline cache and Firestore will sync it automatically once
  /// connectivity is restored. Treat this as success for UI purposes.
  queued,
}

/// Awaits a Firestore write (`set` / `update` / `delete` / `add`) but never
/// hangs forever.
///
/// With offline persistence enabled — which is the DEFAULT on Android/iOS —
/// the Future returned by a write only completes once the **server**
/// acknowledges it. While the device is offline (or the backend is briefly
/// unreachable, or an App Check / rules handshake is retrying at the transport
/// level) that acknowledgement never arrives, so a naive `await docRef.set(...)`
/// stays pending indefinitely even though the write is safely applied to the
/// local cache and will sync later. Any UI that flips a "saving" flag in a
/// `try/finally` around such an await gets stuck on "Saving…" forever.
///
/// [commitWrite] bounds that wait:
///   • completes with [WriteResult.acknowledged] on a real server ack,
///   • completes with [WriteResult.queued] if the timeout elapses first (the
///     write is already in the local cache and will sync),
///   • rethrows any genuine error (e.g. `permission-denied`) unchanged so
///     callers can surface it.
///
/// The underlying write Future is intentionally left running after a timeout —
/// Firestore keeps it queued and syncs it when possible; abandoning our `await`
/// does not cancel or lose the write.
Future<WriteResult> commitWrite(
  Future<void> write, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    await write.timeout(timeout);
    return WriteResult.acknowledged;
  } on TimeoutException {
    return WriteResult.queued;
  }
}
