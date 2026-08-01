import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/image_crop.dart' as crop;
import '../../core/utils/l10n_ext.dart';

/// MANDATORY 1:1 square crop screen with SMART FACE DETECTION (§11).
///
/// The member picks an image of ANY aspect ratio — portrait, landscape, 1:1,
/// 4:5, 9:16 — and this screen turns it into the single square profile photo:
///
///   1. **Auto** — on-device face detection runs first and pre-positions the
///      square around the largest face with natural portrait headroom, so the
///      common case needs no work at all.
///   2. **Manual** — the member can always drag to reposition, pinch or use the
///      zoom buttons, and Reset to start over. When no face is found (or
///      detection fails) the screen simply opens in this mode with a hint.
///   3. **Preview** — "Preview" shows exactly what other members will see;
///      the photo is only returned after the member confirms with
///      "Use this photo". "Adjust again" goes back to step 2.
///
/// Nothing is saved until that confirmation, and the export keeps the source
/// resolution up to [crop.ImageCrop.outputSize] so quality is not thrown away.
///
/// Returns the cropped JPEG [File] via `Navigator.pop`, or `null` when the
/// member backs out (in which case the caller must NOT save anything).
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

  /// Face detection is still running (the frame shows a subtle progress hint).
  bool _detecting = true;

  /// A face was found and the square was centred on it.
  bool _faceCentred = false;

  /// The square crop the detector chose, in image FRACTIONS. Applied to the
  /// viewer once the frame size is known, and re-applied by "Reset".
  crop.Rect? _autoCrop;

  /// The confirmed-preview candidate. While non-null the screen shows the
  /// preview step instead of the editor.
  File? _preview;

  /// Frame side used for the last layout — needed to convert between the
  /// viewer matrix and crop fractions.
  double _side = 0;

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
        _detectFace();
      },
      onError: (e, __) {
        if (mounted) {
          setState(() {
            _decodeError = e;
            _detecting = false;
          });
        }
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  // ── Smart face detection ───────────────────────────────────────────────────

  /// How much wider than the detected face the square should be. 2.6× frames
  /// the head and shoulders the way a portrait normally is cropped.
  static const double _faceZoomOut = 2.6;

  /// Runs on-device detection and, when a usable face is found, records the
  /// square that centres on it. Any failure silently falls back to manual
  /// cropping — detection is a convenience, never a gate.
  Future<void> _detectFace() async {
    final image = _decoded;
    if (image == null) return;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();

    FaceDetector? detector;
    try {
      detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          // Landmarks/classification are not needed — the bounding box alone
          // decides the crop, and skipping them keeps detection fast.
          enableLandmarks: false,
          enableClassification: false,
        ),
      );
      final faces = await detector
          .processImage(InputImage.fromFilePath(widget.source.path));

      // Largest face wins — with several people in frame, the profile owner is
      // almost always the most prominent one.
      Face? best;
      for (final face in faces) {
        final box = face.boundingBox;
        // Guard against a coordinate space that doesn't match the decoded
        // (EXIF-baked) dimensions: an out-of-bounds box would crop the wrong
        // region, so treat it as "not detected" and let the member position it.
        if (box.right > iw + 1 || box.bottom > ih + 1) continue;
        if (box.width <= 0 || box.height <= 0) continue;
        if (best == null ||
            box.width * box.height >
                best.boundingBox.width * best.boundingBox.height) {
          best = face;
        }
      }
      if (best != null) _autoCrop = _squareAroundFace(best.boundingBox, iw, ih);
    } catch (_) {
      // Detection unavailable on this device / unsupported file — manual mode.
    } finally {
      await detector?.close();
    }

    if (!mounted) return;
    setState(() {
      _detecting = false;
      _faceCentred = _autoCrop != null;
    });
    _applyAutoCrop();
  }

  /// The square (in image fractions) that frames [face] like a portrait:
  /// centred horizontally on the face, with the face sitting slightly above the
  /// middle, and always fully inside the image.
  crop.Rect _squareAroundFace(Rect face, double iw, double ih) {
    final shortest = math.min(iw, ih);
    final size = (math.max(face.width, face.height) * _faceZoomOut)
        .clamp(math.min(shortest, 1.0), shortest)
        .toDouble();
    final half = size / 2;

    var cx = face.center.dx;
    // Pushing the crop centre DOWN leaves headroom above the face, which is how
    // a portrait is normally framed.
    var cy = face.center.dy + size * 0.06;

    cx = cx.clamp(half, math.max(half, iw - half)).toDouble();
    cy = cy.clamp(half, math.max(half, ih - half)).toDouble();

    return crop.Rect(
      ((cx - half) / iw).clamp(0.0, 1.0).toDouble(),
      ((cy - half) / ih).clamp(0.0, 1.0).toDouble(),
      (size / iw).clamp(0.0, 1.0).toDouble(),
      (size / ih).clamp(0.0, 1.0).toDouble(),
    );
  }

  // ── Viewer ↔ crop-rectangle conversion ─────────────────────────────────────

  /// Layout geometry of the image inside the [side]-wide square frame. The
  /// image is laid out to COVER the frame, so its shorter edge exactly fills it
  /// and the longer edge overflows symmetrically.
  ({double displayW, double displayH, double ox, double oy})? _layout(
      double side) {
    final image = _decoded;
    if (image == null || side <= 0) return null;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final cover = side / math.min(iw, ih);
    final displayW = iw * cover;
    final displayH = ih * cover;
    return (
      displayW: displayW,
      displayH: displayH,
      ox: (side - displayW) / 2,
      oy: (side - displayH) / 2,
    );
  }

  /// Translates the current pan/zoom into the normalised crop rectangle the
  /// square frame is showing.
  crop.Rect _cropRect(double side) {
    final geo = _layout(side);
    if (geo == null) return crop.Rect.full;

    final m = _controller.value;
    final k = m.getMaxScaleOnAxis();
    final tx = m.storage[12];
    final ty = m.storage[13];

    final left = ((-tx / k) - geo.ox) / geo.displayW;
    final top = ((-ty / k) - geo.oy) / geo.displayH;
    final width = (side / k) / geo.displayW;
    final height = (side / k) / geo.displayH;

    double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
    return crop.Rect(
      clamp01(left),
      clamp01(top),
      clamp01(width),
      clamp01(height),
    );
  }

  /// The inverse of [_cropRect]: positions the viewer so the frame shows
  /// exactly [rect]. Used to apply the face-centred crop.
  void _setCropRect(crop.Rect rect, double side) {
    final geo = _layout(side);
    if (geo == null) return;
    final visibleW = rect.width * geo.displayW;
    if (visibleW <= 0) return;
    // side / k == visible width in layout space.
    final k = (side / visibleW).clamp(1.0, 5.0).toDouble();
    final tx = -k * (geo.ox + rect.left * geo.displayW);
    final ty = -k * (geo.oy + rect.top * geo.displayH);
    _controller.value = Matrix4.identity()
      ..scaleByDouble(k, k, 1.0, 1.0)
      ..setTranslationRaw(tx, ty, 0);
  }

  /// Applies the detected square once both the image and the frame size are
  /// known (they arrive in either order).
  void _applyAutoCrop() {
    final rect = _autoCrop;
    if (rect == null || _side <= 0 || _decoded == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setCropRect(rect, _side);
    });
  }

  // ── Manual controls ────────────────────────────────────────────────────────

  void _zoomBy(double factor) {
    final m = _controller.value.clone();
    final current = m.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, 5.0).toDouble();
    if ((target - current).abs() < 0.001) return;

    // Zoom about the CENTRE of the frame so the subject stays put.
    final c = _side / 2;
    final ratio = target / current;
    final tx = m.storage[12];
    final ty = m.storage[13];
    m
      ..setEntry(0, 0, target)
      ..setEntry(1, 1, target)
      ..setTranslationRaw(
          c - (c - tx) * ratio, c - (c - ty) * ratio, 0);
    setState(() => _controller.value = _clampToImage(m));
  }

  /// Keeps the frame filled: never lets the pan expose an edge of the image.
  Matrix4 _clampToImage(Matrix4 m) {
    final geo = _layout(_side);
    if (geo == null) return m;
    final k = m.getMaxScaleOnAxis();
    final minTx = _side - (geo.ox + geo.displayW) * k;
    final maxTx = -geo.ox * k;
    final minTy = _side - (geo.oy + geo.displayH) * k;
    final maxTy = -geo.oy * k;
    final tx = m.storage[12].clamp(math.min(minTx, maxTx), math.max(minTx, maxTx));
    final ty = m.storage[13].clamp(math.min(minTy, maxTy), math.max(minTy, maxTy));
    return m.clone()..setTranslationRaw(tx.toDouble(), ty.toDouble(), 0);
  }

  void _reset() {
    final rect = _autoCrop;
    setState(() {
      if (rect != null) {
        _setCropRect(rect, _side);
      } else {
        _controller.value = Matrix4.identity();
      }
    });
  }

  // ── Preview / confirm ──────────────────────────────────────────────────────

  /// Produces the square and moves to the preview step. Nothing is returned to
  /// the caller until the member confirms.
  Future<void> _makePreview() async {
    if (_busy || _decoded == null) return;
    setState(() => _busy = true);
    try {
      final file = await crop.ImageCrop.cropSquare(
        source: widget.source,
        cropRect: _cropRect(_side),
      );
      if (!mounted) return;
      setState(() {
        _preview = file;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.couldNotCropPhoto)));
    }
  }

  void _confirm() => Navigator.of(context).pop(_preview);

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final previewing = _preview != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(previewing ? l10n.photoPreviewTitle : l10n.cropPhotoTitle),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The square frame is as wide as the screen allows, with a small
            // gutter so the frame border is always visible.
            final side = (constraints.maxWidth - 32)
                .clamp(120.0, math.max(120.0, constraints.maxHeight - 250))
                .toDouble();
            if (side != _side) {
              _side = side;
              _applyAutoCrop();
            }
            return previewing ? _previewStep(side) : _editorStep(side);
          },
        ),
      ),
    );
  }

  // ── Step 1/2: position the square ──────────────────────────────────────────
  Widget _editorStep(double side) {
    final l10n = context.l10n;
    final hint = _detecting
        ? l10n.detectingFace
        : (_faceCentred ? l10n.faceCenteredHint : l10n.adjustPhotoHint);

    return Column(
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_detecting)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white70),
                  ),
                )
              else if (_faceCentred)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.face_retouching_natural,
                      size: 16, color: AppColors.success),
                ),
              Flexible(
                child: Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Center(
            child: _decodeError != null
                ? Text(l10n.couldNotCropPhoto,
                    style: const TextStyle(color: Colors.white70))
                : _decoded == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : _frame(side),
          ),
        ),
        if (_decoded != null) _zoomBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _decoded == null || _busy ? null : _makePreview,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.visibility_outlined),
              label: Text(l10n.previewPhoto),
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
  }

  /// Zoom in / out / reset — explicit controls next to the pinch gesture, so
  /// zooming does not depend on a two-finger gesture (§11).
  Widget _zoomBar() {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _roundAction(
              icon: Icons.zoom_out,
              tooltip: l10n.zoomOut,
              onTap: () => _zoomBy(1 / 1.25)),
          const SizedBox(width: 14),
          _roundAction(
              icon: Icons.refresh, tooltip: l10n.resetCrop, onTap: _reset),
          const SizedBox(width: 14),
          _roundAction(
              icon: Icons.zoom_in,
              tooltip: l10n.zoomIn,
              onTap: () => _zoomBy(1.25)),
        ],
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white12,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      );

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
              // `high` keeps the on-screen preview faithful to the exported
              // square, which is encoded from the ORIGINAL pixels (§11).
              child: Image.file(widget.source, filterQuality: FilterQuality.high),
            ),
          ),
        ),
      );

  // ── Step 3: confirm ────────────────────────────────────────────────────────
  Widget _previewStep(double side) {
    final l10n = context.l10n;
    return Column(
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            l10n.photoPreviewHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(_preview!,
                  width: side,
                  height: side,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check),
                  label: Text(l10n.usePhoto),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _preview = null),
                  icon: const Icon(Icons.tune),
                  label: Text(l10n.adjustAgain),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
