import 'package:flutter/material.dart';

import 'login_illustrations.dart';

/// Swappable artwork for the two role cards on the Welcome screen (§15).
///
/// The client will supply their own image for each role. Rather than hard-code
/// one now, this widget renders `assets/images/<role>.png` when that file
/// exists and falls back to the built-in illustration when it does not — so the
/// welcome screen looks finished today, and swapping in the real artwork is
/// literally "drop the PNG in `assets/images/` and rebuild". No code change, no
/// pubspec change (the whole `assets/images/` folder is already bundled).
///
/// Drop-in file names:
///   • `assets/images/role_matrimony.png` — திருமணப் பயனர் card
///   • `assets/images/role_family.png`    — குடும்ப உறுப்பினர் card
///
/// Any aspect ratio works: the image is cover-cropped into the circle the card
/// layout already uses, so the card layout itself is untouched.
class RoleCardArtwork extends StatelessWidget {
  /// Asset that replaces the built-in illustration once it is added.
  final String assetPath;

  /// Rendered while [assetPath] is not bundled yet.
  final Widget placeholder;

  final double size;

  const RoleCardArtwork({
    super.key,
    required this.assetPath,
    required this.placeholder,
    this.size = 76,
  });

  /// The matrimony ("Marriage User") role card.
  factory RoleCardArtwork.matrimony({double size = 76}) => RoleCardArtwork(
        assetPath: 'assets/images/role_matrimony.png',
        size: size,
        placeholder:
            CoupleIllustrationCircle(size: size, showFloatingHearts: false),
      );

  /// The family-member role card.
  factory RoleCardArtwork.family({double size = 76}) => RoleCardArtwork(
        assetPath: 'assets/images/role_family.png',
        size: size,
        placeholder:
            FamilyIllustrationCircle(size: size, showFloatingHearts: false),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The asset is optional — until it is added, show the illustration.
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
