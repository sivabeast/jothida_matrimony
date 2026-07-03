import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// The Home banner's FIXED display geometry. Every banner — uploaded image or
/// text-builder — renders at the user Home carousel size (width-24 logical px
/// wide × width×[kBannerAspectRatio] tall), so there is no manual width/height
/// configuration anywhere.
const double kBannerAspectRatio = 0.6; // height = width × 0.6  (5:3)

/// The upload size recommended to admins for image banners (5:3, crisp on all
/// phones). Uploads whose aspect ratio deviates from 5:3 by more than
/// [kBannerAspectTolerance] are rejected.
const int kBannerRecommendedWidth = 1500;
const int kBannerRecommendedHeight = 900;
const double kBannerAspectTolerance = 0.05; // ±5%
const int kBannerMinUploadWidth = 800;

/// A professional, pre-designed look for TEXT banners. Each template carries a
/// premium background (gradient base + decorative astrology graphics, texture
/// and light effects painted by the banner slide) and default colours the admin
/// can override — overriding colours never removes the design itself.
enum BannerTemplate {
  redPremium('red_premium', 'Red Premium',
      Color(0xFF8B0000), Color(0xFF45020B), Color(0xFFFFD700)),
  royalBlue('royal_blue', 'Royal Blue',
      Color(0xFF14337F), Color(0xFF060F3D), Color(0xFFFFD98A)),
  purple('purple', 'Purple',
      Color(0xFF5B2C93), Color(0xFF23104A), Color(0xFFE0B3FF)),
  goldLuxury('gold_luxury', 'Gold Luxury',
      Color(0xFFB8860B), Color(0xFF5C4300), Color(0xFFFFF3C9)),
  green('green', 'Green',
      Color(0xFF1B5E20), Color(0xFF07300F), Color(0xFFB9F6CA)),
  darkElegant('dark_elegant', 'Dark Elegant',
      Color(0xFF262B38), Color(0xFF0A0D14), Color(0xFFFFD700));

  final String key;
  final String label;

  /// Default gradient start (primary) / end (secondary) and the accent used by
  /// the decorative graphics + default text gradient.
  final Color primary;
  final Color secondary;
  final Color accent;

  const BannerTemplate(
      this.key, this.label, this.primary, this.secondary, this.accent);

  static BannerTemplate fromKey(String? raw) => BannerTemplate.values
      .firstWhere((t) => t.key == (raw ?? '').trim().toLowerCase(),
          orElse: () => BannerTemplate.redPremium);
}

/// The built-in astrology illustration rendered on the RIGHT side of a text
/// banner (with the company logo medallion above it).
enum BannerLogoStyle {
  zodiacWheel('zodiac_wheel', 'Zodiac Wheel'),
  sunMoon('sun_moon', 'Sun & Moon'),
  starSparkle('star_sparkle', 'Star Sparkle'),
  orbitRings('orbit_rings', 'Orbit Rings');

  final String key;
  final String label;
  const BannerLogoStyle(this.key, this.label);

  static BannerLogoStyle fromKey(String? raw) => BannerLogoStyle.values
      .firstWhere((s) => s.key == (raw ?? '').trim().toLowerCase(),
          orElse: () => BannerLogoStyle.zodiacWheel);
}

/// How the TITLE text is filled.
enum BannerTextFill {
  solid('solid', 'Solid Color'),
  gradient2('gradient2', 'Two-Color Gradient'),
  gradientMulti('multi', 'Multi-Color Gradient');

  final String key;
  final String label;
  const BannerTextFill(this.key, this.label);

  static BannerTextFill fromKey(String? raw) => BannerTextFill.values
      .firstWhere((f) => f.key == (raw ?? '').trim().toLowerCase(),
          orElse: () => BannerTextFill.solid);
}

/// How the banner background base is filled (the decorative design layer is
/// painted on top of ALL of these — it never disappears).
enum BannerBackgroundStyle {
  solid('solid', 'Solid'),
  gradient('gradient', 'Gradient'),
  pattern('pattern', 'Pattern');

  final String key;
  final String label;
  const BannerBackgroundStyle(this.key, this.label);

  static BannerBackgroundStyle fromKey(String? raw) =>
      BannerBackgroundStyle.values.firstWhere(
          (s) => s.key == (raw ?? '').trim().toLowerCase(),
          orElse: () => BannerBackgroundStyle.gradient);
}

/// A Home-page banner fully managed by the admin (`banners` collection).
///
/// Two kinds:
///  • IMAGE — the admin uploads finished artwork (offer/poster/promotion) and
///    the slide renders it edge-to-edge at the fixed Home banner size.
///  • TEXT — a professional advertisement banner generated from a
///    [BannerTemplate]: fixed layout (LEFT ~62% title/subtitle/description,
///    RIGHT ~38% logo + astrology illustration), premium gradient background
///    with decorative graphics, optional gradient text, font and colours.
///
/// Users only ever see banners with [enabled] == true, sorted by [order].
class HomeBannerModel {
  static const String typeImage = 'image';
  static const String typeText = 'text';

  final String id;
  final String type; // 'image' | 'text'

  // Image banner.
  final String imageUrl;

  // Text banner content.
  final String title;
  final String subtitle;
  final String description;

  // Text banner design (professional builder).
  final String template; // BannerTemplate.key
  final String primaryColor; // '#RRGGBB' — '' → template default
  final String secondaryColor; // '#RRGGBB' — '' → template default
  final String textColor; // '#RRGGBB'
  final String backgroundStyle; // BannerBackgroundStyle.key
  final String textFill; // BannerTextFill.key
  final List<String> textGradientColors; // used by gradient text fills
  final String fontFamily; // '' = system, 'Poppins', 'NotoSansTamil'
  final String logoStyle; // BannerLogoStyle.key

  /// Title font size; 0 = default sizing.
  final double fontSize;
  final String textAlign; // 'left' | 'center' | 'right'

  // Settings.
  final bool enabled;
  final int order;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const HomeBannerModel({
    required this.id,
    required this.type,
    this.imageUrl = '',
    this.title = '',
    this.subtitle = '',
    this.description = '',
    this.template = 'red_premium',
    this.primaryColor = '',
    this.secondaryColor = '',
    this.textColor = '#FFFFFF',
    this.backgroundStyle = 'gradient',
    this.textFill = 'solid',
    this.textGradientColors = const [],
    this.fontFamily = 'Poppins',
    this.logoStyle = 'zodiac_wheel',
    this.fontSize = 0,
    this.textAlign = 'left',
    this.enabled = true,
    this.order = 0,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isImage => type == typeImage;
  bool get isText => type == typeText;

  BannerTemplate get templateEnum => BannerTemplate.fromKey(template);
  BannerLogoStyle get logoStyleEnum => BannerLogoStyle.fromKey(logoStyle);
  BannerTextFill get textFillEnum => BannerTextFill.fromKey(textFill);
  BannerBackgroundStyle get backgroundStyleEnum =>
      BannerBackgroundStyle.fromKey(backgroundStyle);

  /// Effective design colours — the admin's override, or the template default.
  Color get effectivePrimary => primaryColor.trim().isEmpty
      ? templateEnum.primary
      : parseHexColor(primaryColor, templateEnum.primary);
  Color get effectiveSecondary => secondaryColor.trim().isEmpty
      ? templateEnum.secondary
      : parseHexColor(secondaryColor, templateEnum.secondary);
  Color get fgColor => parseHexColor(textColor, Colors.white);

  /// The gradient colours for gradient text — admin's picks, or a default
  /// derived from the template accent.
  List<Color> get effectiveTextGradient {
    final picked = [
      for (final h in textGradientColors)
        parseHexColor(h, templateEnum.accent),
    ];
    if (textFillEnum == BannerTextFill.gradient2) {
      if (picked.length >= 2) return picked.take(2).toList();
      return [Colors.white, templateEnum.accent];
    }
    if (picked.length >= 3) return picked;
    return [Colors.white, templateEnum.accent, Colors.white];
  }

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
      template: d['template'] ?? 'red_premium',
      // Legacy docs stored the background in 'backgroundColor' — honour it as
      // the primary override so old banners keep their colour.
      primaryColor: d['primaryColor'] ?? d['backgroundColor'] ?? '',
      secondaryColor: d['secondaryColor'] ?? '',
      textColor: d['textColor'] ?? '#FFFFFF',
      backgroundStyle: d['backgroundStyle'] ?? 'gradient',
      textFill: d['textFill'] ?? 'solid',
      textGradientColors: [
        for (final c in (d['textGradientColors'] as List? ?? const []))
          c.toString(),
      ],
      fontFamily: d['fontFamily'] ?? 'Poppins',
      logoStyle: d['logoStyle'] ?? 'zodiac_wheel',
      fontSize: toDouble(d['fontSize'], 0),
      textAlign: d['textAlign'] ?? 'left',
      enabled: d['enabled'] ?? true,
      order: d['order'] is int ? d['order'] : (int.tryParse('${d['order']}') ?? 0),
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
        'template': template,
        'primaryColor': primaryColor,
        'secondaryColor': secondaryColor,
        'textColor': textColor,
        'backgroundStyle': backgroundStyle,
        'textFill': textFill,
        'textGradientColors': textGradientColors,
        'fontFamily': fontFamily,
        'logoStyle': logoStyle,
        'fontSize': fontSize,
        'textAlign': textAlign,
        'enabled': enabled,
        'order': order,
        'createdAt': Timestamp.fromDate(createdAt),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };
}
