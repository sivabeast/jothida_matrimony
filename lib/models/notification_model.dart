import 'package:cloud_firestore/cloud_firestore.dart';

/// A stored in-app / push notification for one user.
///
/// Core fields (`userId`, `title`, `body`, `type`, `data`, `isRead`,
/// `createdAt`) are the original schema and MUST keep their names — security
/// rules and old documents depend on them. The metadata fields (`senderId`,
/// `targetScreen`, `targetId`, `updatedAt`) were added by the notification
/// redesign and are optional on old documents.
class NotificationModel {
  final String id;

  /// RECEIVER uid (legacy name kept — rules gate reads on it).
  final String userId;
  final String title;
  final String body;

  /// interest_received, interest_accepted, interest_rejected, porutham_ready,
  /// profile_approval, appointment, admin_update, report_assigned,
  /// chat_message, new_match, announcement, app_update …
  final String type;

  /// Navigation payload. `data['route']` is the canonical in-app deep link
  /// (e.g. '/interests?tab=accepted&highlight=<uid>' or '/chat/<threadId>').
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime createdAt;

  /// Uid of the user whose action generated this notification ('' = system).
  final String senderId;

  /// Logical destination kind ('interests', 'chat', 'horoscope',
  /// 'announcement', 'profile', 'update', …). The route in [data] stays the
  /// source of truth for navigation; this exists for analytics/scalability.
  final String targetScreen;

  /// Id of the destination entity (thread id, interest id, profile id …).
  final String targetId;
  final DateTime? updatedAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.data,
    this.isRead = false,
    required this.createdAt,
    this.senderId = '',
    this.targetScreen = '',
    this.targetId = '',
    this.updatedAt,
  });

  /// The deep-link route this notification navigates to ('' = none).
  String get route => (data?['route'] as String?)?.trim() ?? '';

  static DateTime? _toDate(dynamic v) => v is Timestamp ? v.toDate() : null;

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      userId: d['userId'] ?? '',
      title: d['title'] ?? '',
      body: d['body'] ?? '',
      type: d['type'] ?? '',
      data: d['data'] != null ? Map<String, dynamic>.from(d['data']) : null,
      isRead: d['isRead'] ?? false,
      // A serverTimestamp still pending sync arrives as null — treat as "now"
      // instead of crashing the whole notifications stream.
      createdAt: _toDate(d['createdAt']) ?? DateTime.now(),
      senderId: d['senderId'] ?? '',
      targetScreen: d['targetScreen'] ?? '',
      targetId: d['targetId'] ?? '',
      updatedAt: _toDate(d['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data,
        'isRead': isRead,
        'createdAt': Timestamp.fromDate(createdAt),
        'senderId': senderId,
        'targetScreen': targetScreen,
        'targetId': targetId,
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };
}
