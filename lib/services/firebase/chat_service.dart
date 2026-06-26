import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/constants/app_constants.dart';
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
    try {
      await ref.set({
        'participantIds': [myUid, otherUid],
        'participantNames': {myUid: myName, otherUid: otherName},
        'participantPhotos': {myUid: myPhoto, otherUid: otherPhoto},
        'unread': {myUid: 0, otherUid: 0},
      }, SetOptions(merge: true));
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

  Stream<ChatThread?> watchThread(String threadId) => _chats
      .doc(threadId)
      .snapshots()
      .map((d) => d.exists ? ChatThread.fromFirestore(d) : null);

  Stream<List<ChatMessage>> watchMessages(String threadId, {int limit = 100}) =>
      _chats
          .doc(threadId)
          .collection(AppConstants.messagesSubcollection)
          .orderBy('sentAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(ChatMessage.fromFirestore).toList());

  /// Sends a message into [threadId]. A plain text message passes just [text];
  /// an attachment passes [type] + [attachmentUrl] (+ [fileName]/[fileType]).
  /// The thread's `lastMessage` preview is set to [text] for a text message, or
  /// a short label (📷 Photo / 📄 PDF / 📎 Attachment) for an attachment.
  Future<void> sendMessage({
    required String threadId,
    required String senderId,
    required String text,
    ChatMessageType type = ChatMessageType.text,
    String attachmentUrl = '',
    String fileName = '',
    String fileType = '',
  }) async {
    final threadRef = _chats.doc(threadId);
    final msgRef =
        threadRef.collection(AppConstants.messagesSubcollection).doc();
    final preview = chatPreviewFor(type: type, text: text, fileName: fileName);

    await _db.runTransaction((txn) async {
      final thread = await txn.get(threadRef);
      final participants =
          List<String>.from(thread.data()?['participantIds'] ?? const []);
      final otherId = participants.firstWhere((id) => id != senderId,
          orElse: () => senderId);
      txn.set(msgRef, {
        'senderId': senderId,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
        'type': type.key,
        if (attachmentUrl.isNotEmpty) 'attachmentUrl': attachmentUrl,
        if (fileName.isNotEmpty) 'fileName': fileName,
        if (fileType.isNotEmpty) 'fileType': fileType,
      });
      txn.update(threadRef, {
        'lastMessage': preview,
        'lastSenderId': senderId,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unread.$otherId': FieldValue.increment(1),
      });
    });
  }

  Future<void> markThreadRead(String threadId, String uid) =>
      _chats.doc(threadId).update({'unread.$uid': 0});
}
