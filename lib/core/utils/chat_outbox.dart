/// The chat screen's OUTBOX — messages the member sent that the stored stream
/// has not confirmed yet.
///
/// Sending is optimistic: the message is on screen the moment Send is tapped,
/// the composer clears, and the write happens in the background. Each outgoing
/// message is exactly one of:
///
///  * **sending** — written, not yet acknowledged (bounded by a timeout);
///  * **failed**  — refused or timed out; shown as "Failed · Tap to retry";
///  * **confirmed** — the server acknowledged it; the outbox entry is dropped
///    and the stored copy is shown.
///
/// A retry re-sends under the SAME message id, which rewrites the same
/// document, so it can never produce a duplicate message.
library;

import '../../models/chat_model.dart';

enum OutgoingStatus { sending, failed }

class OutgoingMessage {
  final String id;
  final String text;
  final DateTime createdAt;
  final OutgoingStatus status;

  const OutgoingMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    this.status = OutgoingStatus.sending,
  });

  OutgoingMessage withStatus(OutgoingStatus s) =>
      OutgoingMessage(id: id, text: text, createdAt: createdAt, status: s);
}

/// The list the chat screen renders, newest first: [stored] (the live stream)
/// plus every outbox entry the stream does not already show as acknowledged.
///
///  * a stored, acknowledged copy always wins — the outbox entry is stale;
///  * a FAILED entry wins over a still-pending stored copy, so a write that
///    timed out is offered for retry instead of spinning forever;
///  * an entry the stream does not contain at all (a refused write is rolled
///    back out of the local cache) is shown from the outbox.
List<ChatMessage> mergeOutbox({
  required List<ChatMessage> stored,
  required Iterable<OutgoingMessage> outbox,
  required String myUid,
}) {
  final byId = {for (final m in stored) m.id: m};
  final out = <ChatMessage>[];
  final replaced = <String>{};
  for (final o in outbox) {
    final s = byId[o.id];
    if (s != null && !s.isPending) continue; // confirmed
    if (s != null && o.status == OutgoingStatus.sending) continue; // pending
    replaced.add(o.id);
    out.add(ChatMessage(
      id: o.id,
      senderId: myUid,
      text: o.text,
      sentAt: o.createdAt,
      isPending: o.status == OutgoingStatus.sending,
      isFailed: o.status == OutgoingStatus.failed,
    ));
  }
  out.addAll(stored.where((m) => !replaced.contains(m.id)));
  out.sort((a, b) => b.sentAt.compareTo(a.sentAt));
  return out;
}

/// Outbox ids the stream has now confirmed (stored and acknowledged) — safe to
/// drop from the outbox.
Set<String> confirmedOutboxIds(
  List<ChatMessage> stored,
  Iterable<OutgoingMessage> outbox,
) {
  final acked = {
    for (final m in stored)
      if (!m.isPending) m.id,
  };
  return {
    for (final o in outbox)
      if (acked.contains(o.id)) o.id,
  };
}
