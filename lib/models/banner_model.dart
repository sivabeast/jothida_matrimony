import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// A Home-page banner fully managed by the admin (`banners` collection).
///
/// Two kinds:
///  • IMAGE — the admin uploads finished artwork (offer/poster/promotion) and
///    the slide simply renders it edge-to-edge.
///  • TEXT — built in the admin's Text Banner Builder (title / subtitle /
///    description, background & text colours, optional font size, alignment)
///    with a live preview — no image needed.
///
/// Users only ever see banners with [enabled] == true, sorted by [order].
class HomeBannerModel {
  static const String typeImage = 'image';
  static const String typeText = 'text';

  final String id;
  final String type; // 'image' | 'text'

  // Image banner.
  final String imageUrl;

  // Text banner builder.
  final String title;
  final String subtitle;
  final String description;
  final String backgroundColor; // '#RRGGBB'
  final String textColor; // '#RRGGBB'
  /// Title font size; 0 = default sizing.
  final double fontSize;
  final String textAlign; // 'left' | 'center' | 'right'

  // Settings.
  final bool enabled;
  final int order;

  /// Banner height as a fraction of the banner width (height = width × ratio).
  final double heightRatio;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const HomeBannerModel({
    required this.id,
    required this.type,
    this.imageUrl = '',
    this.title = '',
    this.subtitle = '',
    this.description = '',
    this.backgroundColor = '#8B0000',
    this.textColor = '#FFFFFF',
    this.fontSize = 0,
    this.textAlign = 'left',
    this.enabled = true,
    this.order = 0,
    this.heightRatio = 0.6,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isImage => type == typeImage;
  bool get isText => type == typeText;

  Color get bgColor => parseHexColor(backgroundColor, const Color(0xFF8B0000));
  Color get fgColor => parseHexColor(textColor, Colors.white);

  TextAlign get textAlignment => switch (textAlign) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => TextAlign.left,
      };

  CrossAxisAlignment get crossAlignment => switch (textAlign) {
        'center' => CrossAxisAlignment.center,
        'right' => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.start,
      };

  /// Parses '#RRGGBB' / 'RRGGBB' / '#AARRGGBB'; falls back on bad input.
  static Color parseHexColor(String raw, Color fallback) {
    var s = raw.trim().replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    final v = int.tryParse(s, radix: 16);
    return v == null ? fallback : Color(v);
  }

  static String colorToHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  factory HomeBannerModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    double toDouble(dynamic v, double fb) =>
        v is num ? v.toDouble() : (double.tryParse('$v') ?? fb);
    return HomeBannerModel(
      id: doc.id,
      type: d['type'] ?? typeImage,
      imageUrl: d['imageUrl'] ?? '',
      title: d['title'] ?? '',
      subtitle: d['subtitle'] ?? '',
      description: d['description'] ?? '',
      backgroundColor: d['backgroundColor'] ?? '#8B0000',
      textColor: d['textColor'] ?? '#FFFFFF',
      fontSize: toDouble(d['fontSize'], 0),
      textAlign: d['textAlign'] ?? 'left',
      enabled: d['enabled'] ?? true,
      order: d['order'] is int ? d['order'] : (int.tryParse('${d['order']}') ?? 0),
      heightRatio: toDouble(d['heightRatio'], 0.6).clamp(0.3, 1.2),
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: d['updatedAt'] is Timestamp
          ? (d['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type,
        'imageUrl': imageUrl,
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'backgroundColor': backgroundColor,
        'textColor': textColor,
        'fontSize': fontSize,
        'textAlign': textAlign,
        'enabled': enabled,
        'order': order,
        'heightRatio': heightRatio,
        'createdAt': Timestamp.fromDate(createdAt),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };
}
