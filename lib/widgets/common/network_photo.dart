import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../services/cloudinary/cloudinary_asset_id.dart';

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

  /// Replaces the default icon placeholder — shown for an empty URL AND for a
  /// photo that fails to load, so a missing image looks exactly like "no
  /// photo" (e.g. an initial letter in an avatar) rather than a broken box.
  final Widget? fallback;

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
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return _fallback();
    final known = width;
    if (known != null && known.isFinite) {
      return _image(context, trimmed, known);
    }
    return LayoutBuilder(
      builder: (context, box) => _image(context, trimmed, box.maxWidth),
    );
  }

  /// Downloads a DISPLAY-SIZED copy of a Cloudinary image rather than the
  /// full-resolution original (see [cloudinaryDisplayUrl]); if that ever
  /// fails — a Cloudinary account with strict transformations, say — the
  /// original URL is loaded instead, so a photo can never disappear because
  /// of the optimisation.
  Widget _image(BuildContext context, String original, double logicalWidth) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final sized = cloudinaryDisplayUrl(original,
        width: logicalWidth.isFinite ? logicalWidth * dpr : 0);
    Widget load(String src, Widget Function() onError) => CachedNetworkImage(
          imageUrl: src,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          useOldImageOnUrlChange: true,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => _loading(),
          errorWidget: (_, failedUrl, error) {
            // A photo that does not load must be diagnosable, not just a
            // placeholder: the URL and the actual error (404 for a deleted
            // asset, a blocked transformation, no network…) are logged.
            debugPrint('[NetworkPhoto] load failed for $failedUrl: $error');
            return onError();
          },
        );
    if (sized == original) return load(original, _fallback);
    return load(sized, () => load(original, _fallback));
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

  Widget _fallback() => fallback != null
      ? SizedBox(width: width, height: height, child: fallback)
      : Container(
          width: width,
          height: height,
          color: fallbackBg ?? AppColors.primary.withOpacity(0.08),
          alignment: Alignment.center,
          child: Icon(fallbackIcon,
              size: fallbackIconSize,
              color: AppColors.primary.withOpacity(0.55)),
        );
}

/// A circular profile photo — the drop-in for
/// `CircleAvatar(backgroundImage: NetworkImage(url), child: placeholder)`.
///
/// That pattern is why photos "did not show" on several screens: a bare
/// `NetworkImage` is not cached, and when it fails `CircleAvatar` paints an
/// EMPTY coloured circle — the placeholder child is only used when there is no
/// URL at all, so a broken or slow photo looked exactly like a missing one and
/// nothing was logged. This renders through [NetworkPhoto] instead: cached,
/// display-sized with an automatic fallback to the original URL, and the SAME
/// placeholder for "no photo" and "photo failed to load". Same size, colour and
/// shape as the avatar it replaces.
class PhotoAvatar extends StatelessWidget {
  final String url;
  final double radius;
  final Color? backgroundColor;

  /// Shown when there is no photo or it cannot be loaded (an icon, an initial).
  final Widget placeholder;

  const PhotoAvatar({
    super.key,
    required this.url,
    required this.radius,
    required this.placeholder,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final side = radius * 2;
    final trimmed = url.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: trimmed.isEmpty
          ? placeholder
          : ClipOval(
              child: NetworkPhoto(
                url: trimmed,
                width: side,
                height: side,
                fit: BoxFit.cover,
                fallback: Container(
                  color: backgroundColor,
                  alignment: Alignment.center,
                  child: placeholder,
                ),
              ),
            ),
    );
  }
}

/// Shared [ImageProvider] for places that need a raw provider (e.g.
/// `DecorationImage`) rather than a widget.
///
/// Prefer [PhotoAvatar] / [NetworkPhoto]: an [ImageProvider] has no error
/// fallback, which is why this always loads the ORIGINAL URL — never a
/// resized variant that could fail with nothing to fall back to. Cached on
/// disk, unlike a bare `NetworkImage`. Returns null for an empty URL.
ImageProvider? cachedPhotoProvider(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  return CachedNetworkImageProvider(trimmed);
}

/// Forgets everything the device has cached for [url] (spec §25).
///
/// Every profile photo is cached twice over: in Flutter's in-memory
/// [ImageCache] and on disk by `cached_network_image`. Both survive the
/// Firestore document changing, so after replacing or removing a photo the app
/// happily kept painting the old bytes — the image looked unchanged even though
/// the reference had already moved on.
///
/// Call this with the URL that is going AWAY, right before/after the new one is
/// stored. Best-effort and never throws: failing to clear a cache must not
/// break the save that triggered it.
Future<void> evictCachedImage(String? url) async {
  final trimmed = (url ?? '').trim();
  if (trimmed.isEmpty) return;
  try {
    // In-memory: both provider shapes the app uses for the same URL.
    PaintingBinding.instance.imageCache
        .evict(CachedNetworkImageProvider(trimmed));
    PaintingBinding.instance.imageCache.evict(NetworkImage(trimmed));
  } catch (_) {
    // A test binding without an image cache, or an unparseable URL.
  }
  try {
    // On disk.
    await CachedNetworkImage.evictFromCache(trimmed);
  } catch (_) {
    // No cache manager available (unit tests) — nothing to clear.
  }
}
