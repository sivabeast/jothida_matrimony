import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// The official Jothida Matrimony brand logo.
///
/// Renders `assets/images/app_logo.png` as a circular medallion (the emblem is
/// circular, so this trims the artwork's black corners and looks premium on any
/// background). A maroon/gold fallback keeps the UI intentional before the
/// asset is bundled. Use this everywhere instead of inline `Image.asset` calls.
class AppLogo extends StatelessWidget {
  final double size;

  /// When true (default) the logo is clipped to a circle; otherwise a rounded
  /// "squircle" is used (handy for app-bar chips).
  final bool circle;

  const AppLogo({super.key, this.size = 40, this.circle = true});

  @override
  Widget build(BuildContext context) {
    final radius = circle ? size / 2 : size * 0.24;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/images/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.gold, width: size * 0.03),
          ),
          child: Icon(Icons.favorite, color: AppColors.gold, size: size * 0.5),
        ),
      ),
    );
  }
}

/// The APPLICATION LAUNCHER icon — `assets/images/report_logo.png`, the exact
/// 1024×1024 master `flutter_launcher_icons` generates `ic_launcher` from (see
/// pubspec.yaml). Use this wherever the app must present *itself* (login
/// header, update popups) so the artwork always matches the icon on the user's
/// home screen; [AppLogo] stays the smaller in-app emblem.
///
/// Rendered as a premium rounded-square medallion: soft maroon glow, a hairline
/// gold rim and a subtle white plate behind the artwork, so it reads as a
/// finished app mark on any background instead of a bare image.
class AppLauncherLogo extends StatelessWidget {
  final double size;

  /// Draws the glow + gold rim. Turn off for dense surfaces (list rows).
  final bool elevated;

  const AppLauncherLogo({super.key, this.size = 96, this.elevated = true});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.26;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: elevated
            ? Border.all(color: AppColors.gold.withValues(alpha: 0.55), width: 1.4)
            : null,
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  blurRadius: size * 0.22,
                  offset: Offset(0, size * 0.07),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        // Inset by the border so the artwork never bleeds over the gold rim.
        borderRadius: BorderRadius.circular(radius - 1.4),
        child: Image.asset(
          'assets/images/report_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Falls back to the in-app emblem, then to the brand medallion, so a
          // missing asset can never leave a broken image in the UI.
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/images/app_logo.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
              alignment: Alignment.center,
              child: Icon(Icons.favorite,
                  color: AppColors.gold, size: size * 0.45),
            ),
          ),
        ),
      ),
    );
  }
}
