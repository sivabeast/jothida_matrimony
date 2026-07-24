import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A robust remote image with consistent empty-URL, loading and error handling.
///
/// Use this anywhere a network photo is shown (profile cards, astrologer
/// thumbnails, avatars) so a missing/slow/broken URL never renders a raw blank
/// box or throws. It guarantees:
///   • an EMPTY or whitespace URL shows the branded placeholder immediately
///     (never `Image.network('')`, which fails noisily),
///   • a calm tinted placeholder while the bytes download (optionally a small
///     progress spinner for large hero images),
///   • a branded fallback (tinted background + icon) on any decode/load error,
///   • no flash to blank when the URL changes ([useOldImageOnUrlChange]).
///
/// Backed by [CachedNetworkImage] so every photo is fetched **once** and served
/// from the on-disk cache on subsequent views (and across app launches). This is
/// the single place that makes profile photos, astrology media, banners and
/// thumbnails stop re-downloading on every visit.
///
/// The widget always fills the [width]/[height] it is given, so callers can rely
/// on a uniform footprint regardless of which state is showing — that is what
/// keeps cards the same height and the layout free of jumps.
class NetworkPhoto extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  /// Icon shown in the fallback/placeholder. Defaults to a person glyph.
  final IconData fallbackIcon;
  final double fallbackIconSize;

  /// Background colour for the placeholder/fallback. Defaults to a soft tint of
  /// the brand primary.
  final Color? fallbackBg;

  /// When true, the loading state shows a small circular progress indicator
  /// (nice for large hero images). For dense thumbnails leave it false so a row
  /// of cards isn't filled with spinners.
  final bool showLoadingSpinner;

  const NetworkPhoto({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallbackIcon = Icons.person,
    this.fallbackIconSize = 44,
    this.fallbackBg,
    this.showLoadingSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return _fallback();
    return CachedNetworkImage(
      imageUrl: trimmed,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      useOldImageOnUrlChange: true,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => _loading(),
      errorWidget: (_, __, ___) => _fallback(),
    );
  }

  Widget _loading() => Container(
        width: width,
        height: height,
        color: const Color(0xFFF1EAE1),
        alignment: Alignment.center,
        child: showLoadingSpinner
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary.withOpacity(0.45),
                ),
              )
            : null,
      );

  Widget _fallback() => Container(
        width: width,
        height: height,
        color: fallbackBg ?? AppColors.primary.withOpacity(0.08),
        alignment: Alignment.center,
        child: Icon(fallbackIcon,
            size: fallbackIconSize, color: AppColors.primary.withOpacity(0.55)),
      );
}

/// Shared [ImageProvider] for places that need a raw provider (e.g.
/// `CircleAvatar.backgroundImage` or `DecorationImage`) rather than a widget.
///
/// Prefer [NetworkPhoto] when you can. Use this only where an [ImageProvider] is
/// required so those spots still benefit from the on-disk cache instead of
/// re-downloading via a bare `NetworkImage`. Returns null for an empty URL so
/// callers can fall back to an icon/child.
ImageProvider? cachedPhotoProvider(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  return CachedNetworkImageProvider(trimmed);
}
