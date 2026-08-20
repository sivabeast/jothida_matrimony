import 'package:cloud_firestore/cloud_firestore.dart';

/// The Home banner's FIXED display geometry. Every banner renders at the user
/// Home carousel size (width-24 logical px wide × width×[kBannerAspectRatio]
/// tall), so there is no manual width/height configuration anywhere.
const double kBannerAspectRatio = 0.6; // height = width × 0.6  (5:3)

/// The upload size recommended to admins (5:3, crisp on all phones). Uploads
/// whose aspect ratio deviates from 5:3 by more than [kBannerAspectTolerance]
/// are rejected.
const int kBannerRecommendedWidth = 1500;
const int kBannerRecommendedHeight = 900;
const double kBannerAspectTolerance = 0.05; // ±5%
const int kBannerMinUploadWidth = 800;

/// A Home-page banner fully managed by the admin (`banners` collection).
///
/// Banners are IMAGE-ONLY: the admin uploads finished artwork and the Home
/// carousel renders that exact image edge-to-edge. There is no text/template
/// banner builder and nothing is ever overlaid on the uploaded artwork.
///
/// Users only ever see banners with [enabled] == true, sorted by [order]. When
/// the admin has published none, the Home carousel is hidden entirely — there
/// are no default, demo or fallback banners.
class HomeBannerModel {
  final String id;

  /// The uploaded artwork. A banner without one is never displayed.
  final String imageUrl;

  /// Optional admin-only label so a banner is identifiable in the management
  /// list. NEVER rendered over the artwork.
  final String title;

  final bool enabled;
  final int order;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const HomeBannerModel({
    required this.id,
    this.imageUrl = '',
    this.title = '',
    this.enabled = true,
    this.order = 0,
    required this.createdAt,
    this.updatedAt,
  });

  /// Whether this banner can actually be shown. Legacy text-builder documents
  /// (which carry no artwork) are filtered out by this check.
  bool get hasImage => imageUrl.trim().isNotEmpty;

  factory HomeBannerModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return HomeBannerModel(
      id: doc.id,
      imageUrl: d['imageUrl'] ?? '',
      title: d['title'] ?? '',
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
        'imageUrl': imageUrl,
        'title': title,
        'enabled': enabled,
        'order': order,
        'createdAt': Timestamp.fromDate(createdAt),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };
}
