import 'package:cloud_firestore/cloud_firestore.dart';

/// A user's request to delete their account. Stored in
/// `account_deletion_requests/{id}`. Nothing is deleted until a Super Admin
/// approves the request.
class AccountDeletionRequest {
  final String id;
  final String userId;
  final String userName;
  final String email;
  final DateTime requestDate;
  final String status; // pending | approved | rejected

  const AccountDeletionRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.email,
    required this.requestDate,
    this.status = 'pending',
  });

  factory AccountDeletionRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AccountDeletionRequest(
      id: doc.id,
      userId: d['userId'] ?? '',
      userName: d['userName'] ?? '',
      email: d['email'] ?? '',
      requestDate: d['requestDate'] != null
          ? (d['requestDate'] as Timestamp).toDate()
          : DateTime.now(),
      status: d['status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'userName': userName,
        'email': email,
        'requestDate': Timestamp.fromDate(requestDate),
        'status': status,
      };
}
