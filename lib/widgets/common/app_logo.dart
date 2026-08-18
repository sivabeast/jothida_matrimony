import 'package:flutter/material.dart';
import '../../core/constants/brand_assets.dart';
import '../../core/theme/app_colors.dart';

/// Physical pixels to decode [logical] logical pixels at on this screen.
///
/// Capped so a hi-DPI phone never asks for more than the master actually has —
/// requesting above the source size would decode the full bitmap anyway.
int _decodePx(BuildContext context, double logical) {
  final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
  return (logical * ratio).round().clamp(1, 1024);
}

/// The official Jothida Matrimony brand logo — [kAppLogoAsset], the SAME
/// artwork as the launcher / Play Store icon (spec §5).
///
/// Renders as a rounded medallion. A maroon/gold gradient fallback keeps the UI
/// intentional if the asset is ever missing. Use this (or [AppLauncherLogo])
/// everywhere instead of inline `Image.asset` calls, so the app can never show
/// two different marks.
class AppLogo extends StatelessWidget {
  final double size;

  /// Clip shape. Defaults to a **rounded square** with a moderate radius —
  /// never a sharp square, never a full circle — because the brand mark now
  /// carries a wordmark under the emblem, and a circular clip cuts the text
  /// off. Pass `circle: true` only where a round avatar is genuinely wanted.
  final bool circle;

  const AppLogo({super.key, this.size = 40, this.circle = false});

  @override
  Widget build(BuildContext context) {
    final radius = circle ? size / 2 : size * 0.24;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        kAppLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The master is 1024x1024 — ~4 MB once decoded — and this widget
        // renders it at 36-46px in app bars on nearly every screen. Without a
        // decode cap Flutter keeps the full-size bitmap in the image cache for
        // each distinct size, which is memory and jank for pixels nobody sees.
        cacheWidth: _decodePx(context, size),
        cacheHeight: _decodePx(context, size),
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

/// The same single logo presented as a premium rounded-square medallion — soft
/// maroon glow, hairline gold rim, brand-maroon plate behind the artwork — for
/// the surfaces where the app introduces *itself* (splash, login header).
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
        // Sits directly under the logo's own rounded corners, which are
        // transparent, so this must be the plate's maroon and NOT white —
        // white showed as four pale slivers once the gold logo was replaced
        // by the red one.
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(radius),
        border: elevated
            ? Border.all(
                color: AppColors.gold.withValues(alpha: 0.55), width: 1.4)
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
          kAppLogoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: _decodePx(context, size),
          cacheHeight: _decodePx(context, size),
          errorBuilder: (_, __, ___) => Container(
            decoration:
                const BoxDecoration(gradient: AppColors.primaryGradient),
            alignment: Alignment.center,
            child:
                Icon(Icons.favorite, color: AppColors.gold, size: size * 0.45),
          ),
        ),
      ),
    );
  }
}
