import 'package:cloud_firestore/cloud_firestore.dart';

/// A platform-wide announcement created by an admin and shown to ALL users and
/// astrologers (unlike `notifications`, which are per-user). Stored in the
/// `announcements` collection.
class AnnouncementModel {
  final String id;
  final String title;
  final String message;
  final String createdBy; // 'admin'
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.message,
    this.createdBy = 'admin',
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  factory AnnouncementModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AnnouncementModel(
      id: doc.id,
      title: d['title'] ?? '',
      message: d['message'] ?? '',
      createdBy: d['createdBy'] ?? 'admin',
      isActive: d['isActive'] ?? true,
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: d['updatedAt'] is Timestamp
          ? (d['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'message': message,
        'createdBy': createdBy,
        'isActive': isActive,
        'createdAt': Timestamp.fromDate(createdAt),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };
}
