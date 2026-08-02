import 'package:flutter/material.dart';

import '../../core/utils/face_crop_resolver.dart';
import 'network_photo.dart';

/// A profile photo whose crop is centred on the member's FACE.
///
/// Drop-in replacement for [NetworkPhoto] on every surface that shows a cropped
/// portrait — Home cards, the Matches browser and the View Profile header — so
/// all three frame a person identically:
///
///   • the face is centred in the visible area,
///   • the top of the head and the chin are never cut off (the anchor keeps a
///     little headroom),
///   • when no face is found — or the platform has no on-device detector — it
///     falls back to a normal centre crop, exactly like before.
///
/// Detection is on-device, memoised per URL and serialised
/// ([FaceCropResolver]), so a scrolling list costs one detection per NEW photo
/// and nothing thereafter. Opening a photo full-screen still shows the ORIGINAL
/// uncropped image — this widget only affects the cropped thumbnail/hero.
class FaceCenteredPhoto extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Alignment used until (and unless) a face is located.
  final Alignment fallbackAlignment;

  final IconData fallbackIcon;
  final double fallbackIconSize;
  final Color? fallbackBg;
  final bool showLoadingSpinner;

  const FaceCenteredPhoto({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallbackAlignment = Alignment.center,
    this.fallbackIcon = Icons.person,
    this.fallbackIconSize = 44,
    this.fallbackBg,
    this.showLoadingSpinner = false,
  });

  @override
  State<FaceCenteredPhoto> createState() => _FaceCenteredPhotoState();
}

class _FaceCenteredPhotoState extends State<FaceCenteredPhoto> {
  late Alignment _alignment = _initialAlignment;

  Alignment get _initialAlignment =>
      FaceCropResolver.instance.cached(widget.url) ?? widget.fallbackAlignment;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant FaceCenteredPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _alignment = _initialAlignment;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = widget.url.trim();
    if (url.isEmpty) return;
    if (FaceCropResolver.instance.cached(url) != null) return;
    final alignment = await FaceCropResolver.instance.resolve(url);
    // The photo may have been swapped (pager) or the widget disposed while the
    // detector was running — only apply a result that still belongs here.
    if (!mounted || widget.url.trim() != url || alignment == _alignment) return;
    setState(() => _alignment = alignment);
  }

  @override
  Widget build(BuildContext context) {
    return NetworkPhoto(
      url: widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: _alignment,
      fallbackIcon: widget.fallbackIcon,
      fallbackIconSize: widget.fallbackIconSize,
      fallbackBg: widget.fallbackBg,
      showLoadingSpinner: widget.showLoadingSpinner,
    );
  }
}
