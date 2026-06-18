import 'package:cloud_firestore/cloud_firestore.dart';

/// A single user's rating (1–5) and optional written review of an astrologer.
///
/// Stored in the `astrologers/{astrologerId}/reviews/{userId}` subcollection —
/// keying the document by the rating user's uid guarantees **one review per
/// user per astrologer**, so re-submitting edits the same document instead of
/// creating a duplicate.
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

  /// Deterministic id used by the in-memory demo store (one flat list across all
  /// astrologers). The live Firestore path uses the userId as the subcollection
  /// document id instead.
  static String docId(String astrologerId, String userId) =>
      '${astrologerId}_$userId';

  /// Builds a review from a subcollection document. [astrologerId] is passed
  /// from the parent path (`astrologers/{astrologerId}/reviews/...`) and used as
  /// the fallback when the field isn't stored on the document itself.
  factory AstrologerReviewModel.fromFirestore(DocumentSnapshot doc,
      {String astrologerId = ''}) {
    final d = doc.data() as Map<String, dynamic>;
    DateTime ts(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    return AstrologerReviewModel(
      id: doc.id,
      astrologerId: (d['astrologerId'] as String?)?.isNotEmpty == true
          ? d['astrologerId']
          : astrologerId,
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
