import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageDescriptor, ImmutableBuffer;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Alignment;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Works out WHERE a photo should be anchored so the person's face stays in the
/// centre of the visible crop — the "face-centred rendering" used by the Home,
/// Matches and View Profile photos.
///
/// How it fits together:
///   • the image is drawn with `BoxFit.cover`, which fills the box and crops the
///     overflow; Flutter's `alignment` decides WHICH part survives;
///   • this resolver converts a detected face's centre into exactly that
///     alignment, biased slightly upward so the crown of the head and the chin
///     both stay inside the frame;
///   • detection runs ON DEVICE against the file `cached_network_image` already
///     downloaded, so no photo ever leaves the phone and nothing is fetched
///     twice;
///   • every failure — no face, an unsupported platform, ML Kit unavailable,
///     the file not cached yet — falls back to a plain centre crop.
///
/// Results are memoised per URL for the app's lifetime and detection is
/// serialised through a single queue, so scrolling a list of profiles never
/// spawns a burst of detectors.
class FaceCropResolver {
  FaceCropResolver._();

  /// The shared instance. A single detector queue keeps memory flat.
  static final FaceCropResolver instance = FaceCropResolver._();

  /// The plain centre crop used whenever detection cannot help.
  static const Alignment fallback = Alignment.center;

  /// How far ABOVE the face centre the crop is anchored, as a fraction of the
  /// image height. A little headroom is what stops a tight crop from shaving
  /// the top of the head while still keeping the chin in frame.
  static const double _headroom = 0.05;

  final Map<String, Alignment> _cache = {};
  final Map<String, Future<Alignment>> _inFlight = {};

  /// Already-known alignment for [url], or null when it has not been resolved
  /// yet. Lets a widget paint the correct crop on its FIRST frame when the photo
  /// has been seen before (e.g. swiping back through the Matches pager).
  Alignment? cached(String url) => _cache[url.trim()];

  /// Resolves the face-centred alignment for [url]. Never throws; returns
  /// [fallback] when a face cannot be located.
  Future<Alignment> resolve(String url) {
    final key = url.trim();
    if (key.isEmpty) return Future.value(fallback);
    final known = _cache[key];
    if (known != null) return Future.value(known);
    return _inFlight[key] ??= _resolve(key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<Alignment> _resolve(String url) async {
    // ML Kit ships only for Android and iOS. Everywhere else (and in tests) the
    // plain centre crop is the correct, silent answer.
    if (!_supportsFaceDetection) return _remember(url, fallback);

    // Deliberately no `.timeout()` here: these calls are bounded by the cache
    // manager / HTTP client themselves, and a timeout would leave a pending
    // timer behind for a purely cosmetic background task (which is also what
    // widget tests trip over). A failure just means "centre crop".
    File? file;
    try {
      final info = await DefaultCacheManager().getFileFromCache(url);
      // `getSingleFile` returns the cached file when present and otherwise
      // downloads it once — the same download CachedNetworkImage is already
      // doing, deduplicated by the cache manager.
      file = info?.file ?? await DefaultCacheManager().getSingleFile(url);
    } catch (e) {
      debugPrint('[FaceCrop] photo not available for detection: $e');
      return _remember(url, fallback);
    }

    // Serialise detection — several cards resolving at once would otherwise
    // hold several native detectors open simultaneously.
    return _queue(() => _detect(url, file!));
  }

  Future<Alignment> _detect(String url, File file) async {
    FaceDetector? detector;
    try {
      detector = FaceDetector(
        options: FaceDetectorOptions(
          // `fast` is the right trade-off for a browse feed: the bounding box
          // is all we need and it must not stall scrolling.
          performanceMode: FaceDetectorMode.fast,
          enableLandmarks: false,
          enableClassification: false,
        ),
      );
      final faces =
          await detector.processImage(InputImage.fromFilePath(file.path));
      if (faces.isEmpty) return _remember(url, fallback);

      // Largest face wins — with several people in frame the profile owner is
      // almost always the most prominent one.
      var best = faces.first;
      for (final face in faces) {
        final b = face.boundingBox, bb = best.boundingBox;
        if (b.width * b.height > bb.width * bb.height) best = face;
      }

      final size = await _imageSize(file);
      if (size == null) return _remember(url, fallback);
      final (width, height) = size;
      if (width <= 0 || height <= 0) return _remember(url, fallback);

      final box = best.boundingBox;
      // A box outside the decoded bounds means ML Kit and the decoder disagree
      // about orientation — cropping on it would frame the wrong region.
      if (box.width <= 0 ||
          box.height <= 0 ||
          box.right > width + 1 ||
          box.bottom > height + 1) {
        return _remember(url, fallback);
      }

      final fx = (box.center.dx / width).clamp(0.0, 1.0);
      final fy = ((box.center.dy / height) - _headroom).clamp(0.0, 1.0);
      // Alignment runs -1 (top/left) … 1 (bottom/right); a fraction f of the
      // source maps to f * 2 - 1.
      final alignment = Alignment(
        (fx * 2 - 1).clamp(-1.0, 1.0),
        (fy * 2 - 1).clamp(-1.0, 1.0),
      );
      debugPrint('[FaceCrop] face-centred alignment $alignment for $url');
      return _remember(url, alignment);
    } catch (e) {
      debugPrint('[FaceCrop] detection unavailable (centre crop): $e');
      return _remember(url, fallback);
    } finally {
      await detector?.close();
    }
  }

  /// Decoded pixel size of [file] without keeping the bitmap around.
  Future<(double, double)?> _imageSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final descriptor = await ImageDescriptor.encoded(
          await ImmutableBuffer.fromUint8List(bytes));
      final size = (descriptor.width.toDouble(), descriptor.height.toDouble());
      descriptor.dispose();
      return size;
    } catch (e) {
      debugPrint('[FaceCrop] could not read image size: $e');
      return null;
    }
  }

  Alignment _remember(String url, Alignment alignment) {
    _cache[url] = alignment;
    return alignment;
  }

  // ── Single-slot work queue ────────────────────────────────────────────────
  Future<void> _tail = Future.value();

  Future<T> _queue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  static bool get _supportsFaceDetection =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Test seam: drops every memoised alignment.
  @visibleForTesting
  void clearCache() => _cache.clear();
}
