import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Creates the thread if it doesn't exist yet and returns its id.
  Future<String> getOrCreateThread({
    required String myUid,
    required String myName,
    required String myPhoto,
    required String otherUid,
    required String otherName,
    required String otherPhoto,
  }) async {
    final threadId = ChatThread.threadIdFor(myUid, otherUid);
    final ref = _chats.doc(threadId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set(ChatThread(
        id: threadId,
        participantIds: [myUid, otherUid],
        participantNames: {myUid: myName, otherUid: otherName},
        participantPhotos: {myUid: myPhoto, otherUid: otherPhoto},
        unread: {myUid: 0, otherUid: 0},
      ).toFirestore());
    }
    return threadId;
  }

  Stream<List<ChatThread>> watchThreads(String uid) => _chats
      .where('participantIds', arrayContains: uid)
      .orderBy('lastMessageAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(ChatThread.fromFirestore).toList());

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

  Future<void> sendMessage({
    required String threadId,
    required String senderId,
    required String text,
  }) async {
    final threadRef = _chats.doc(threadId);
    final msgRef =
        threadRef.collection(AppConstants.messagesSubcollection).doc();

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
      });
      txn.update(threadRef, {
        'lastMessage': text,
        'lastSenderId': senderId,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unread.$otherId': FieldValue.increment(1),
      });
    });
  }

  Future<void> markThreadRead(String threadId, String uid) =>
      _chats.doc(threadId).update({'unread.$uid': 0});
}
