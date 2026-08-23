import 'package:cloud_firestore/cloud_firestore.dart';

/// An app-opening popup, fully managed by the admin (`app_popups` collection).
///
/// Nothing here is hardcoded in the app: the admin creates as many contents as
/// they like (astrology guidance, why a marriage is delayed, horoscope-matching
/// advice…), and the app shows the next ACTIVE one each time it is opened,
/// cycling through them (spec §13/§14).
///
/// Users only ever see popups with [enabled] == true, in [order]. With none
/// enabled no popup is shown at all — there is no default or fallback content.
class AppPopupModel {
  final String id;

  /// Headline. A popup with neither a title nor a body is never displayed.
  final String title;

  /// Body copy. Plain text; rendered as-is under the title.
  final String content;

  /// Optional artwork shown above the text. Popups work fine without one.
  final String imageUrl;

  final bool enabled;
  final int order;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const AppPopupModel({
    required this.id,
    this.title = '',
    this.content = '',
    this.imageUrl = '',
    this.enabled = true,
    this.order = 0,
    required this.createdAt,
    this.updatedAt,
  });

  /// Whether this popup has anything worth showing.
  bool get hasContent =>
      title.trim().isNotEmpty || content.trim().isNotEmpty;

  bool get hasImage => imageUrl.trim().isNotEmpty;

  factory AppPopupModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AppPopupModel(
      id: doc.id,
      title: d['title'] ?? '',
      content: d['content'] ?? '',
      imageUrl: d['imageUrl'] ?? '',
      enabled: d['enabled'] ?? true,
      order:
          d['order'] is int ? d['order'] : (int.tryParse('${d['order']}') ?? 0),
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
        'content': content,
        'imageUrl': imageUrl,
        'enabled': enabled,
        'order': order,
        'createdAt': Timestamp.fromDate(createdAt),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  AppPopupModel copyWith({
    String? title,
    String? content,
    String? imageUrl,
    bool? enabled,
    int? order,
  }) =>
      AppPopupModel(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        imageUrl: imageUrl ?? this.imageUrl,
        enabled: enabled ?? this.enabled,
        order: order ?? this.order,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
