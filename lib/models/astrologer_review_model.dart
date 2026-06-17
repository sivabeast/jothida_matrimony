import 'package:cloud_firestore/cloud_firestore.dart';

/// A single user's rating (1–5) and optional written review of an astrologer.
///
/// Stored in `astrologer_reviews/{astrologerId}_{userId}` — the deterministic
/// id guarantees **one review per user per astrologer**, so re-submitting edits
/// the same document instead of creating a duplicate.
class AstrologerReviewModel {
  final String id;
  final String astrologerId;
  final String userId;
  final String userName;
  final int rating; // 1..5
  final String review; // optional comment
  final DateTime createdAt;
  final DateTime updatedAt;

  const AstrologerReviewModel({
    required this.id,
    required this.astrologerId,
    required this.userId,
    required this.userName,
    required this.rating,
    this.review = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Deterministic document id → enforces one-review-per-user-per-astrologer.
  static String docId(String astrologerId, String userId) =>
      '${astrologerId}_$userId';

  factory AstrologerReviewModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    DateTime ts(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    return AstrologerReviewModel(
      id: doc.id,
      astrologerId: d['astrologerId'] ?? '',
      userId: d['userId'] ?? '',
      userName: (d['userName'] as String?)?.trim().isNotEmpty == true
          ? d['userName']
          : 'User',
      rating: (d['rating'] as num?)?.toInt() ?? 0,
      review: d['review'] ?? '',
      createdAt: ts(d['createdAt']),
      updatedAt: ts(d['updatedAt']),
    );
  }
}
