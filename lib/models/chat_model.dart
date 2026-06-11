import 'package:cloud_firestore/cloud_firestore.dart';

/// A 1-to-1 conversation between two users.
///
/// Firestore: `chats/{threadId}` where `threadId` is the two uids sorted and
/// joined with '_' so the same pair always maps to the same document.
/// { participantIds: [a, b], participantNames: {uid: name},
///   participantPhotos: {uid: url}, lastMessage, lastSenderId,
///   lastMessageAt, unread: {uid: count} }
class ChatThread {
  final String id;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final Map<String, String> participantPhotos;
  final String lastMessage;
  final String lastSenderId;
  final DateTime? lastMessageAt;
  final Map<String, int> unread;

  const ChatThread({
    required this.id,
    required this.participantIds,
    this.participantNames = const {},
    this.participantPhotos = const {},
    this.lastMessage = '',
    this.lastSenderId = '',
    this.lastMessageAt,
    this.unread = const {},
  });

  /// Deterministic thread id for a pair of uids.
  static String threadIdFor(String uidA, String uidB) {
    final ids = [uidA, uidB]..sort();
    return ids.join('_');
  }

  String otherId(String myUid) =>
      participantIds.firstWhere((id) => id != myUid, orElse: () => '');

  String otherName(String myUid) => participantNames[otherId(myUid)] ?? 'User';

  String otherPhoto(String myUid) => participantPhotos[otherId(myUid)] ?? '';

  int unreadFor(String myUid) => unread[myUid] ?? 0;

  factory ChatThread.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ChatThread(
      id: doc.id,
      participantIds: List<String>.from(d['participantIds'] ?? const []),
      participantNames:
          Map<String, String>.from(d['participantNames'] ?? const {}),
      participantPhotos:
          Map<String, String>.from(d['participantPhotos'] ?? const {}),
      lastMessage: d['lastMessage'] ?? '',
      lastSenderId: d['lastSenderId'] ?? '',
      lastMessageAt: d['lastMessageAt'] != null
          ? (d['lastMessageAt'] as Timestamp).toDate()
          : null,
      unread: Map<String, int>.from(d['unread'] ?? const {}),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'participantIds': participantIds,
        'participantNames': participantNames,
        'participantPhotos': participantPhotos,
        'lastMessage': lastMessage,
        'lastSenderId': lastSenderId,
        'lastMessageAt':
            lastMessageAt != null ? Timestamp.fromDate(lastMessageAt!) : null,
        'unread': unread,
      };
}

/// One message inside a thread. Firestore: `chats/{threadId}/messages/{id}`.
class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      senderId: d['senderId'] ?? '',
      text: d['text'] ?? '',
      sentAt: d['sentAt'] != null
          ? (d['sentAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'senderId': senderId,
        'text': text,
        'sentAt': Timestamp.fromDate(sentAt),
      };
}
