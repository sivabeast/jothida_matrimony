import 'package:cloud_firestore/cloud_firestore.dart';

/// The kind of admin notification — drives the icon/colour on the user side
/// and the default action-button label.
enum AnnouncementType {
  featureUpdate('feature_update', 'Feature Update'),
  announcement('announcement', 'Announcement'),
  offer('offer', 'Offer'),
  maintenance('maintenance', 'Maintenance'),
  general('general', 'General'),
  other('other', 'Other');

  final String key;
  final String label;
  const AnnouncementType(this.key, this.label);

  static AnnouncementType fromKey(String? raw) =>
      AnnouncementType.values.firstWhere(
        (t) => t.key == (raw ?? '').trim().toLowerCase(),
        orElse: () => AnnouncementType.general,
      );

  /// Sensible action-button text when the admin didn't provide one.
  String get defaultActionLabel => switch (this) {
        AnnouncementType.featureUpdate => 'Update Now',
        AnnouncementType.offer => 'View Offer',
        AnnouncementType.maintenance => 'Learn More',
        _ => 'Open',
      };
}

/// A platform-wide announcement created by an admin and shown to ALL users and
/// astrologers (unlike `notifications`, which are per-user). Stored in the
/// `announcements` collection. Can optionally carry an action link (Play Store
/// update, website, internal app page…) rendered as a button on the
/// notification details page.
class AnnouncementModel {
  final String id;
  final String title;
  final String message;
  final String createdBy; // 'admin'
  final bool isActive;

  /// One of [AnnouncementType.key]. Legacy documents without the field are
  /// treated as 'general'.
  final String type;

  /// Optional link opened by the action button — an external URL (https://…)
  /// or an internal app route (starting with '/'). Empty = no action button.
  final String actionUrl;

  /// Optional custom label for the action button ("Update Now", "Open"…).
  final String actionLabel;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.message,
    this.createdBy = 'admin',
    this.isActive = true,
    this.type = 'general',
    this.actionUrl = '',
    this.actionLabel = '',
    required this.createdAt,
    this.updatedAt,
  });

  AnnouncementType get typeEnum => AnnouncementType.fromKey(type);
  bool get hasAction => actionUrl.trim().isNotEmpty;

  /// The label shown on the action button — the admin's custom label, or a
  /// default derived from the type.
  String get effectiveActionLabel => actionLabel.trim().isNotEmpty
      ? actionLabel.trim()
      : typeEnum.defaultActionLabel;

  factory AnnouncementModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AnnouncementModel(
      id: doc.id,
      title: d['title'] ?? '',
      message: d['message'] ?? '',
      createdBy: d['createdBy'] ?? 'admin',
      isActive: d['isActive'] ?? true,
      type: d['type'] ?? 'general',
      actionUrl: d['actionUrl'] ?? '',
      actionLabel: d['actionLabel'] ?? '',
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
        'type': type,
        'actionUrl': actionUrl,
        'actionLabel': actionLabel,
        'createdAt': Timestamp.fromDate(createdAt),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };
}
