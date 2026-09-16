import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/constants/app_constants.dart';
import '../../core/utils/firestore_write.dart';
import '../../models/chat_model.dart';

/// Firestore-backed 1-to-1 chat.
///
/// Layout: `chats/{threadId}` (thread metadata, deterministic id from the two
/// uids) and `chats/{threadId}/messages/{messageId}`.
class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection(AppConstants.chatsCollection);

  /// Returns the deterministic thread id for [myUid] ⇄ [otherUid], creating the
  /// `chats/{threadId}` document first if it doesn't exist yet.
  ///
  /// ROOT-CAUSE NOTE ("Could not open chat"): a `get()` on a NON-existent chat
  /// document is DENIED by the security rules — the read rule dereferences
  /// `resource.data.participantIds`, and for a missing doc `resource` is null,
  /// so Firestore returns `permission-denied` (NOT an empty snapshot). The old
  /// code did `get()` → `if (!exists) create`, so the very first `get()` threw
  /// before the create branch could run. That single bug broke BOTH booking-time
  /// pre-creation (its error was swallowed, leaving no thread) AND every later
  /// open-chat attempt. We now treat a `permission-denied` / `not-found` get as
  /// "thread missing" and fall through to create it, and we log every step so an
  /// unexpected failure is easy to pinpoint.
  Future<String> getOrCreateThread({
    required String myUid,
    required String myName,
    required String myPhoto,
    required String otherUid,
    required String otherName,
    required String otherPhoto,
  }) async {
    if (myUid.isEmpty || otherUid.isEmpty) {
      // A booking/profile with a missing id would otherwise build a malformed
      // thread id and silently misbehave — fail loudly with a clear cause.
      throw ArgumentError(
          'getOrCreateThread needs both ids (myUid="$myUid", otherUid="$otherUid")');
    }
    final threadId = ChatThread.threadIdFor(myUid, otherUid);
    final ref = _chats.doc(threadId);

    // 1) Does the thread already exist? Reuse it if so.
    try {
      final snap = await ref.get();
      if (snap.exists) {
        debugPrint('[ChatService] thread $threadId exists → reuse');
        return threadId;
      }
      debugPrint('[ChatService] thread $threadId missing → create');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'not-found') {
        // Expected for a not-yet-created thread (see ROOT-CAUSE NOTE) — create.
        debugPrint(
            '[ChatService] thread $threadId not readable (${e.code}) → create');
      } else {
        debugPrint('[ChatService] getOrCreateThread get($threadId) '
            'failed: ${e.code} ${e.message}');
        rethrow;
      }
    }

    // 2) Create it. The deterministic id + merge make this idempotent and never
    // clobber a last-message a concurrent writer may have just set.
    //
    // Bounded write: this set() carries serverTimestamps, so its Future only
    // resolves on a SERVER ack (offline persistence). Awaiting it raw made the
    // "Chat" button hang forever with no error whenever the network was down or
    // flaky — it never navigated. commitWrite caps the wait; the create is
    // idempotent and the thread id is deterministic, so we can safely return it
    // and navigate even when the doc is still queued to sync. A real
    // permission-denied still throws (only TimeoutException is absorbed).
    try {
      await commitWrite(ref.set({
        'participantIds': [myUid, otherUid],
        'participantNames': {myUid: myName, otherUid: otherName},
        'participantPhotos': {myUid: myPhoto, otherUid: otherPhoto},
        'unread': {myUid: 0, otherUid: 0},
        'createdAt': FieldValue.serverTimestamp(),
        // Stamped at creation so a brand-new (still message-less) conversation
        // sorts to the TOP of the Chats list immediately — the accepted-interest
        // thread must be visible without waiting for a first message.
        'lastMessageAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
      debugPrint('[ChatService] thread $threadId created');
      return threadId;
    } on FirebaseException catch (e) {
      // A denied CREATE means the rules forbid THIS participant from creating
      // the thread (e.g. an astrologer, who must not cold-initiate contact — the
      // user pre-creates the thread at booking time instead).
      debugPrint('[ChatService] getOrCreateThread create($threadId) '
          'failed: ${e.code} ${e.message}');
      rethrow;
    }
  }

  /// Threads for [uid], most-recent activity first.
  ///
  /// Intentionally a single `arrayContains` filter with NO server-side
  /// `orderBy`. Combining `arrayContains` with `orderBy('lastMessageAt')`
  /// requires a composite Firestore index; until that index exists the query
  /// throws `failed-precondition` and the entire Chats list errors out. We sort
  /// by `lastMessageAt` client-side instead, so the list ALWAYS loads — with or
  /// without the composite index. (The index is still declared in
  /// firestore.indexes.json for server-side ordering at scale.)
  Stream<List<ChatThread>> watchThreads(String uid) => _chats
      .where('participantIds', arrayContains: uid)
      .snapshots()
      .map((s) {
        final threads = s.docs.map(ChatThread.fromFirestore).toList();
        threads.sort((a, b) =>
            (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                    a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
        return threads;
      });

  /// Tombstones every thread [uid] takes part in, so the conversation stops
  /// being shown to the other member (spec §2).
  ///
  /// An UPDATE, not a delete: the rules let a participant update the thread but
  /// never delete it, and deleting would destroy the other member's copy of the
  /// history from under them. The name and photo entries are blanked at the
  /// same time so no identifying data survives on the document even for a
  /// client that has not been updated.
  ///
  /// Best-effort per thread: one failure must not abort the rest of account
  /// deletion, and the caller logs what could not be cleared.
  Future<int> tombstoneThreadsFor(String uid) async {
    var failed = 0;
    try {
      final snap =
          await _chats.where('participantIds', arrayContains: uid).get();
      for (final doc in snap.docs) {
        try {
          await doc.reference.update({
            'deletedParticipants': FieldValue.arrayUnion([uid]),
            'participantNames.$uid': '',
            'participantPhotos.$uid': '',
          });
        } catch (e) {
          failed++;
          debugPrint('[ChatService] tombstone failed for ${doc.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('[ChatService] tombstoneThreadsFor($uid) query failed: $e');
      return -1;
    }
    return failed;
  }

  /// Pushes [uid]'s CURRENT matrimony name and photo into every thread they
  /// take part in (spec §2).
  ///
  /// The thread document snapshots both so the Chats list can render without a
  /// profile read per row. A snapshot is a cache, and a cache that is never
  /// refreshed is just stale data: renaming yourself or changing your photo
  /// left the other member looking at the old one forever.
  ///
  /// The UI no longer DEPENDS on this — [ChatThread.otherName] / `otherPhoto`
  /// are a fallback behind the live profile (see `chatCounterpartIdentity`) —
  /// so this is the cache catching up, not the source of truth. It is
  /// therefore best-effort and bounded: only threads whose stored values
  /// actually differ are written, and a failure never propagates into the
  /// profile save that triggered it.
  ///
  /// Returns the number of threads updated.
  Future<int> syncParticipantIdentity({
    required String uid,
    required String name,
    required String photoUrl,
  }) async {
    if (uid.isEmpty) return 0;
    var updated = 0;
    try {
      final snap =
          await _chats.where('participantIds', arrayContains: uid).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        // A member who deleted their account is tombstoned with blank name and
        // photo — never resurrect that entry.
        final deleted =
            List<String>.from(data['deletedParticipants'] ?? const []);
        if (deleted.contains(uid)) continue;
        final names = Map<String, dynamic>.from(
            data['participantNames'] ?? const <String, dynamic>{});
        final photos = Map<String, dynamic>.from(
            data['participantPhotos'] ?? const <String, dynamic>{});
        if ((names[uid] ?? '') == name && (photos[uid] ?? '') == photoUrl) {
          continue; // already current
        }
        try {
          await doc.reference.update({
            'participantNames.$uid': name,
            'participantPhotos.$uid': photoUrl,
          });
          updated++;
        } catch (e) {
          debugPrint('[ChatService] identity sync failed for ${doc.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('[ChatService] syncParticipantIdentity($uid) query failed: $e');
    }
    return updated;
  }

  Stream<ChatThread?> watchThread(String threadId) => _chats
      .doc(threadId)
      .snapshots()
      .map((d) => d.exists ? ChatThread.fromFirestore(d) : null);

  /// Messages newest-first. `includeMetadataChanges` so an optimistic local
  /// write emits immediately with `hasPendingWrites` (→ "Sending…") and again
  /// once the server acknowledges it (→ "Sent").
  ///
  /// [limit] is the newest N messages — the chat screen starts with a page and
  /// raises it when the member scrolls to the oldest loaded message, so a long
  /// history is never downloaded in full just to open the conversation.
  Stream<List<ChatMessage>> watchMessages(String threadId, {int limit = 50}) =>
      _chats
          .doc(threadId)
          .collection(AppConstants.messagesSubcollection)
          .orderBy('sentAt', descending: true)
          .limit(limit)
          .snapshots(includeMetadataChanges: true)
          .map((s) => s.docs.map(ChatMessage.fromFirestore).toList());

  /// Sends a message into [threadId]. A plain text message passes just [text];
  /// an attachment passes [type] + [attachmentUrl] (+ [fileName]/[fileType]).
  /// The thread's `lastMessage` preview is set to [text] for a text message, or
  /// a short label (📷 Photo / 📄 PDF / 📎 Attachment) for an attachment.
  ///
  /// [messageId] forces a DETERMINISTIC message doc id. Used for the one-time
  /// accepted-interest greeting ('greeting_&lt;threadId&gt;') so the client and the
  /// interest-accepted Cloud Function can both try to post it without ever
  /// producing two greeting bubbles.
  ///
  /// ROOT CAUSE of "Send keeps spinning": this used to run inside
  /// `runTransaction`, only to READ the thread for the other participant's id.
  /// A transaction never touches the local cache — it needs a live server
  /// round-trip, retries on contention (both members typing) and only gives up
  /// after its ~30 s timeout. So the message did not appear, the send button
  /// spun, and on a weak network the whole thing failed. The "Sending…" state
  /// driven by `hasPendingWrites` could never show, because a transaction
  /// produces no pending local write.
  ///
  /// It is now ONE atomic batch: the message and the thread preview commit
  /// together, the batch is applied to the local cache immediately (the
  /// message is on screen at once, marked Sending), and the returned future
  /// completes on the server ack. [otherUid] is supplied by the caller, which
  /// already holds the thread; without it the thread is read from the local
  /// cache first. Re-sending with the same [messageId] rewrites the same
  /// document, so a retry can never create a duplicate message.
  Future<void> sendMessage({
    required String threadId,
    required String senderId,
    required String text,
    ChatMessageType type = ChatMessageType.text,
    String attachmentUrl = '',
    String fileName = '',
    String fileType = '',
    String? messageId,
    String? otherUid,
  }) async {
    final threadRef = _chats.doc(threadId);
    final messages = threadRef.collection(AppConstants.messagesSubcollection);
    final msgRef = messageId == null || messageId.isEmpty
        ? messages.doc()
        : messages.doc(messageId);
    final preview = chatPreviewFor(type: type, text: text, fileName: fileName);
    final otherId = (otherUid ?? '').trim().isNotEmpty
        ? otherUid!.trim()
        : await _otherParticipant(threadRef, senderId);

    final batch = _db.batch()
      ..set(msgRef, {
        'senderId': senderId,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
        'type': type.key,
        if (attachmentUrl.isNotEmpty) 'attachmentUrl': attachmentUrl,
        if (fileName.isNotEmpty) 'fileName': fileName,
        if (fileType.isNotEmpty) 'fileType': fileType,
      })
      ..update(threadRef, {
        'lastMessage': preview,
        'lastSenderId': senderId,
        'lastMessageAt': FieldValue.serverTimestamp(),
        if (otherId.isNotEmpty && otherId != senderId)
          'unread.$otherId': FieldValue.increment(1),
      });
    await batch.commit();
  }

  /// A new message document id, generated locally (no network). Lets the UI
  /// show the message before the write and match it to the stored one after.
  String newMessageId(String threadId) => _chats
      .doc(threadId)
      .collection(AppConstants.messagesSubcollection)
      .doc()
      .id;

  /// The other participant of [threadRef], cache first.
  Future<String> _otherParticipant(
      DocumentReference<Map<String, dynamic>> threadRef, String me) async {
    DocumentSnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await threadRef.get(const GetOptions(source: Source.cache));
    } catch (_) {
      snap = null;
    }
    if (snap == null || !snap.exists) {
      try {
        snap = await threadRef.get();
      } catch (e) {
        debugPrint('[ChatService] thread read for unread count failed: $e');
        return '';
      }
    }
    final ids = List<String>.from(snap.data()?['participantIds'] ?? const []);
    return ids.firstWhere((id) => id != me, orElse: () => '');
  }

  /// Clears [uid]'s unread count AND stamps their read receipt — a message of
  /// the other participant is "Seen" once `readAt.$uid` is at/after its sentAt.
  Future<void> markThreadRead(String threadId, String uid) =>
      _chats.doc(threadId).update({
        'unread.$uid': 0,
        'readAt.$uid': FieldValue.serverTimestamp(),
        // Anything read has necessarily been delivered.
        'deliveredAt.$uid': FieldValue.serverTimestamp(),
      });

  /// Stamps [uid]'s delivery receipt — called from the RECIPIENT's device the
  /// moment its thread stream sees a newer incoming message, so the sender's
  /// tick flips to "Delivered" without the chat being opened.
  Future<void> markThreadDelivered(String threadId, String uid) =>
      _chats.doc(threadId).update({
        'deliveredAt.$uid': FieldValue.serverTimestamp(),
      });

  /// Presence marker for push suppression: records which conversation [uid]
  /// is currently viewing on `users/{uid}.activeThreadId` (null clears it).
  /// The chat-message Cloud Function skips the FCM push when the receiver is
  /// already looking at that thread. Best-effort — never throws.
  Future<void> setActiveThread(String uid, String? threadId) async {
    if (uid.isEmpty) return;
    try {
      await _db.collection(AppConstants.usersCollection).doc(uid).update({
        'activeThreadId':
            (threadId == null || threadId.isEmpty) ? FieldValue.delete() : threadId,
      });
    } catch (e) {
      debugPrint('[ChatService] setActiveThread failed (non-fatal): $e');
    }
  }
}
