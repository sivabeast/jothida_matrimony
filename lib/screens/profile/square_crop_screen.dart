import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/image_crop.dart' as crop;
import '../../core/utils/l10n_ext.dart';

/// MANDATORY 1:1 square crop screen (§1).
///
/// Every profile photo goes through this screen: the member picks an image of
/// ANY aspect ratio, positions/zooms it inside the square frame and taps
/// "Crop & Save". Only the cropped square is uploaded — there is no "skip
/// crop" path and no way to save the original rectangle.
///
/// Returns the cropped, optimised JPEG [File] via `Navigator.pop`, or `null`
/// when the member backs out (in which case the caller must NOT save anything).
class SquareCropScreen extends StatefulWidget {
  final File source;
  const SquareCropScreen({super.key, required this.source});

  /// Opens the crop screen for [source] and resolves to the cropped square,
  /// or null when the user cancelled.
  static Future<File?> open(BuildContext context, File source) =>
      Navigator.of(context).push<File>(
        MaterialPageRoute(builder: (_) => SquareCropScreen(source: source)),
      );

  @override
  State<SquareCropScreen> createState() => _SquareCropScreenState();
}

class _SquareCropScreenState extends State<SquareCropScreen> {
  final TransformationController _controller = TransformationController();

  /// Intrinsic pixel size of the picked image (null until decoded).
  ui.Image? _decoded;
  Object? _decodeError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reads the intrinsic dimensions through the engine decoder (fast — no full
  /// re-encode) so the square frame can be laid out before any cropping.
  void _resolveImage() {
    final stream = FileImage(widget.source).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() => _decoded = info.image);
        stream.removeListener(listener);
      },
      onError: (e, __) {
        if (mounted) setState(() => _decodeError = e);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  /// Translates the current pan/zoom into the normalised crop rectangle the
  /// square frame is showing.
  ///
  /// The image is laid out to COVER the [side]-wide square frame, so its
  /// shorter edge exactly fills the frame and the longer edge overflows
  /// symmetrically. The interactive matrix then maps frame coordinates back
  /// onto that layout; dividing by the laid-out size yields 0..1 fractions of
  /// the original image.
  crop.Rect _cropRect(double side) {
    final image = _decoded;
    if (image == null) return crop.Rect.full;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final cover = side / (iw < ih ? iw : ih);
    final displayW = iw * cover;
    final displayH = ih * cover;
    final ox = (side - displayW) / 2;
    final oy = (side - displayH) / 2;

    final m = _controller.value;
    final k = m.getMaxScaleOnAxis();
    final tx = m.storage[12];
    final ty = m.storage[13];

    final left = ((-tx / k) - ox) / displayW;
    final top = ((-ty / k) - oy) / displayH;
    final width = (side / k) / displayW;
    final height = (side / k) / displayH;

    double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
    return crop.Rect(
      clamp01(left),
      clamp01(top),
      clamp01(width),
      clamp01(height),
    );
  }

  Future<void> _confirm(double side) async {
    if (_busy || _decoded == null) return;
    setState(() => _busy = true);
    try {
      final file = await crop.ImageCrop.cropSquare(
        source: widget.source,
        cropRect: _cropRect(side),
      );
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.couldNotCropPhoto)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.cropPhotoTitle),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The square frame is as wide as the screen allows, with a small
            // gutter so the frame border is always visible.
            final side = (constraints.maxWidth - 32)
                .clamp(120.0, constraints.maxHeight - 200)
                .toDouble();
            return Column(
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l10n.cropPhotoHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: _decodeError != null
                        ? Text(l10n.couldNotCropPhoto,
                            style: const TextStyle(color: Colors.white70))
                        : _decoded == null
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : _frame(side),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed:
                          _decoded == null || _busy ? null : () => _confirm(side),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.crop),
                      label: Text(l10n.cropAndSave),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade700,
                        disabledForegroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The square viewport: pan/zoom the covered image inside a 1:1 frame.
  Widget _frame(double side) => Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: 5,
          clipBehavior: Clip.none,
          child: SizedBox(
            width: side,
            height: side,
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: Image.file(widget.source, filterQuality: FilterQuality.medium),
            ),
          ),
        ),
      );
}
