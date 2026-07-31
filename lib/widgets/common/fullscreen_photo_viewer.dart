import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// Full-screen viewer for the ONE profile photo (§10).
///
/// Dark background, pinch-to-zoom, drag-to-pan, and an explicit close button
/// (the system Back gesture works too). There is deliberately NO gallery /
/// pager: every member has exactly one profile photo.
class FullScreenPhotoViewer extends StatelessWidget {
  final String url;

  /// Shown while the network image loads and when it fails — keeps the viewer
  /// from flashing an empty black screen.
  final String? heroTag;

  const FullScreenPhotoViewer({super.key, required this.url, this.heroTag});

  /// Opens the viewer for [url]. A blank url is ignored so callers can wire
  /// this straight onto a tap handler without pre-checking.
  static void open(BuildContext context, String url, {String? heroTag}) {
    if (url.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FullScreenPhotoViewer(url: url, heroTag: heroTag),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PhotoView(
              imageProvider: CachedNetworkImageProvider(url),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
              initialScale: PhotoViewComputedScale.contained,
              heroAttributes:
                  heroTag == null ? null : PhotoViewHeroAttributes(tag: heroTag!),
              loadingBuilder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 72),
              ),
            ),
          ),
          // Close action — always reachable regardless of the zoom level.
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            right: 8,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
