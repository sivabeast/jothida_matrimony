import 'package:cloud_firestore/cloud_firestore.dart';

/// Kind of request a matrimony user sends to an astrologer.
enum AstrologerRequestType { consultation, inquiry, matching }

/// Lifecycle of a request.
enum AstrologerRequestStatus { pending, accepted, completed, rejected }

extension AstrologerRequestTypeX on AstrologerRequestType {
  String get label {
    switch (this) {
      case AstrologerRequestType.consultation:
        return 'Consultation';
      case AstrologerRequestType.inquiry:
        return 'Inquiry';
      case AstrologerRequestType.matching:
        return 'Horoscope Matching';
    }
  }
}

extension AstrologerRequestStatusX on AstrologerRequestStatus {
  String get label {
    switch (this) {
      case AstrologerRequestStatus.pending:
        return 'Pending';
      case AstrologerRequestStatus.accepted:
        return 'Accepted';
      case AstrologerRequestStatus.completed:
        return 'Completed';
      case AstrologerRequestStatus.rejected:
        return 'Rejected';
    }
  }
}

/// A request from a matrimony user to an astrologer.
///
/// Firestore: `astrologer_requests/{id}`
/// { astrologerId, userId, userName, userPhotoUrl, type, status, message,
///   amount, profileAId, profileBId, createdAt, respondedAt }
///
/// For [AstrologerRequestType.matching], `profileAId` / `profileBId` are the
/// two matrimony profiles whose horoscopes should be compared.
class AstrologerRequestModel {
  final String id;
  final String astrologerId;
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final AstrologerRequestType type;
  final AstrologerRequestStatus status;
  final String message;
  final int amount;
  final String? profileAId;
  final String? profileBId;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const AstrologerRequestModel({
    required this.id,
    required this.astrologerId,
    required this.userId,
    required this.userName,
    this.userPhotoUrl = '',
    required this.type,
    this.status = AstrologerRequestStatus.pending,
    this.message = '',
    this.amount = 0,
    this.profileAId,
    this.profileBId,
    required this.createdAt,
    this.respondedAt,
  });

  factory AstrologerRequestModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AstrologerRequestModel(
      id: doc.id,
      astrologerId: d['astrologerId'] ?? '',
      userId: d['userId'] ?? '',
      userName: d['userName'] ?? 'User',
      userPhotoUrl: d['userPhotoUrl'] ?? '',
      type: AstrologerRequestType.values.firstWhere(
        (t) => t.name == (d['type'] ?? 'inquiry'),
        orElse: () => AstrologerRequestType.inquiry,
      ),
      status: AstrologerRequestStatus.values.firstWhere(
        (s) => s.name == (d['status'] ?? 'pending'),
        orElse: () => AstrologerRequestStatus.pending,
      ),
      message: d['message'] ?? '',
      amount: d['amount'] ?? 0,
      profileAId: d['profileAId'],
      profileBId: d['profileBId'],
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      respondedAt: d['respondedAt'] != null
          ? (d['respondedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'astrologerId': astrologerId,
        'userId': userId,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'type': type.name,
        'status': status.name,
        'message': message,
        'amount': amount,
        'profileAId': profileAId,
        'profileBId': profileBId,
        'createdAt': Timestamp.fromDate(createdAt),
        'respondedAt':
            respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      };

  AstrologerRequestModel copyWith({AstrologerRequestStatus? status}) =>
      AstrologerRequestModel(
        id: id,
        astrologerId: astrologerId,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        type: type,
        status: status ?? this.status,
        message: message,
        amount: amount,
        profileAId: profileAId,
        profileBId: profileBId,
        createdAt: createdAt,
        respondedAt: respondedAt ?? (status != null ? DateTime.now() : null),
      );
}
