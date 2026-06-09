import 'package:cloud_firestore/cloud_firestore.dart';

class InterestModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String senderProfileId;
  final String receiverProfileId;
  final String status; // pending, accepted, rejected
  final DateTime sentAt;
  final DateTime? respondedAt;
  final String? message;

  const InterestModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.senderProfileId,
    required this.receiverProfileId,
    required this.status,
    required this.sentAt,
    this.respondedAt,
    this.message,
  });

  factory InterestModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return InterestModel(
      id: doc.id,
      senderId: d['senderId'] ?? '',
      receiverId: d['receiverId'] ?? '',
      senderProfileId: d['senderProfileId'] ?? '',
      receiverProfileId: d['receiverProfileId'] ?? '',
      status: d['status'] ?? 'pending',
      sentAt: d['sentAt'] != null ? (d['sentAt'] as Timestamp).toDate() : DateTime.now(),
      respondedAt: d['respondedAt'] != null ? (d['respondedAt'] as Timestamp).toDate() : null,
      message: d['message'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'senderId': senderId,
        'receiverId': receiverId,
        'senderProfileId': senderProfileId,
        'receiverProfileId': receiverProfileId,
        'status': status,
        'sentAt': Timestamp.fromDate(sentAt),
        'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
        'message': message,
      };

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
}
