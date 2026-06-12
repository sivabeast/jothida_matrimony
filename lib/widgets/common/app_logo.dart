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
