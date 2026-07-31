import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Square (1:1) crop + optimisation helpers for the ONE profile photo every
/// member has (§1).
///
/// The app accepts a source image of ANY aspect ratio, then forces the user
/// through the [SquareCropScreen] before saving. This file does the actual
/// pixel work: it takes the normalised crop rectangle the crop screen produced
/// and turns it into a compact, good-quality square JPEG on disk.
class ImageCrop {
  ImageCrop._();

  /// Longest edge of the exported square. 1080 keeps a crisp image on every
  /// phone (and on the admin panel / website) while staying small enough that
  /// the upload is quick on a mobile connection.
  static const int outputSize = 1080;

  /// JPEG quality of the exported square — visually lossless at this size but
  /// roughly a third of the bytes of a quality-100 encode.
  static const int jpegQuality = 88;

  /// Crops [source] to the square described by [cropRect] (values are
  /// FRACTIONS of the decoded image's width/height, i.e. 0..1), resizes the
  /// result to at most [outputSize]×[outputSize] and writes it out as a JPEG.
  ///
  /// Returns the new file. The original is never modified. Throws
  /// [ImageCropException] when the picked file cannot be decoded.
  static Future<File> cropSquare({
    required File source,
    required Rect cropRect,
  }) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const ImageCropException('unsupported-image');
    }
    // `bakeOrientation` applies the EXIF rotation, so a photo shot in portrait
    // is cropped in the same orientation the user saw in the crop screen.
    final oriented = img.bakeOrientation(decoded);

    final side = math.max(
      1,
      (math.min(cropRect.width * oriented.width,
              cropRect.height * oriented.height))
          .round(),
    );
    final x = (cropRect.left * oriented.width)
        .round()
        .clamp(0, math.max(0, oriented.width - side))
        .toInt();
    final y = (cropRect.top * oriented.height)
        .round()
        .clamp(0, math.max(0, oriented.height - side))
        .toInt();

    var square = img.copyCrop(oriented, x: x, y: y, width: side, height: side);
    if (square.width > outputSize) {
      square = img.copyResize(
        square,
        width: outputSize,
        height: outputSize,
        interpolation: img.Interpolation.average,
      );
    }

    final out = await _outputFile();
    await out.writeAsBytes(
      Uint8List.fromList(img.encodeJpg(square, quality: jpegQuality)),
      flush: true,
    );
    debugPrint('[ImageCrop] ${source.path} (${oriented.width}x'
        '${oriented.height}) → ${out.path} (${square.width}x${square.height}, '
        '${await out.length()} bytes)');
    return out;
  }

  /// Decoded pixel size of [file], or null when it cannot be read. Used by the
  /// crop screen to lay the image out before any cropping happens.
  static Future<Size?> decodedSize(File file) async {
    try {
      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) return null;
      final oriented = img.bakeOrientation(decoded);
      return Size(oriented.width.toDouble(), oriented.height.toDouble());
    } catch (e) {
      debugPrint('[ImageCrop] decodedSize failed: $e');
      return null;
    }
  }

  static Future<File> _outputFile() async {
    final dir = await getTemporaryDirectory();
    final name = 'profile_square_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return File('${dir.path}${Platform.pathSeparator}$name');
  }
}

/// Raised when a picked file is not an image this device can decode.
class ImageCropException implements Exception {
  final String code;
  const ImageCropException(this.code);
  @override
  String toString() => 'ImageCropException($code)';
}

/// Minimal geometry types so this file stays independent of `dart:ui` /
/// Flutter widgets (it is also exercised directly by unit tests).
class Rect {
  final double left;
  final double top;
  final double width;
  final double height;
  const Rect(this.left, this.top, this.width, this.height);

  /// The full image (no crop).
  static const Rect full = Rect(0, 0, 1, 1);
}

class Size {
  final double width;
  final double height;
  const Size(this.width, this.height);
}
