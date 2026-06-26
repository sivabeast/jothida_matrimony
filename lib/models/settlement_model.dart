import 'package:cloud_firestore/cloud_firestore.dart';

/// One astrologer-payout settlement batch recorded when the admin presses
/// "Mark as Paid" on a set of delivered (completed + paid) consultations.
///
/// Firestore: `settlements/{id}`. There is NO commission — `amount` is the full
/// sum paid out to the astrologer. The covered consultation docs are flagged
/// `settled = true` with this doc's id as their `settlementId`. Backs the admin
/// Settlement History + the astrologer's "Last Settlement" / "Total Paid".
class Settlement {
  final String id;
  final String astrologerId;
  final String astrologerName;
  final int amount;
  final int bookingCount;
  final List<String> bookingIds;
  final String note;
  final DateTime createdAt;

  const Settlement({
    required this.id,
    required this.astrologerId,
    this.astrologerName = '',
    this.amount = 0,
    this.bookingCount = 0,
    this.bookingIds = const [],
    this.note = '',
    required this.createdAt,
  });

  factory Settlement.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Settlement(
      id: doc.id,
      astrologerId: d['astrologerId'] ?? '',
      astrologerName: d['astrologerName'] ?? '',
      amount: (d['amount'] ?? 0) is num ? (d['amount'] as num).toInt() : 0,
      bookingCount:
          (d['bookingCount'] ?? 0) is num ? (d['bookingCount'] as num).toInt() : 0,
      bookingIds: (d['bookingIds'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      note: d['note'] ?? '',
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'astrologerId': astrologerId,
        'astrologerName': astrologerName,
        'amount': amount,
        'bookingCount': bookingCount,
        'bookingIds': bookingIds,
        'note': note,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
