import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Saves generated files **straight into the phone's own storage**, with no
/// share sheet in between.
///
/// The profile download has to behave like a browser download — tap, then find
/// the file in Downloads — rather than "tap, pick an app, hope it saves". That
/// rules out `share_plus`, whose whole job is to hand the file to another app.
///
/// On Android this calls through to MediaStore (see `MainActivity.kt`), which
/// is the only sanctioned route into shared storage on API 29+ and needs no
/// runtime permission. Anywhere else — and if the platform call fails for any
/// reason — it falls back to the app's documents directory so a download still
/// produces a file the member can open, instead of failing outright.
class DeviceFiles {
  DeviceFiles._();

  static const MethodChannel _channel =
      MethodChannel('com.jothida.jothida_matrimony/device_files');

  /// Writes [bytes] to the device Downloads folder.
  ///
  /// Returns the human-readable location to show in the success message, or
  /// null when even the fallback failed.
  static Future<String?> saveToDownloads(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/pdf',
  }) =>
      _save('saveToDownloads', bytes,
          fileName: fileName, mimeType: mimeType);

  /// Writes [bytes] to the device gallery (Pictures/Jothida Matrimony).
  static Future<String?> saveToPictures(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'image/png',
  }) =>
      _save('saveToPictures', bytes, fileName: fileName, mimeType: mimeType);

  static Future<String?> _save(
    String method,
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>(method, {
          'bytes': bytes,
          'fileName': fileName,
          'mimeType': mimeType,
        });
        if (path != null && path.isNotEmpty) return path;
      } on PlatformException catch (e) {
        debugPrint('[DeviceFiles] $method failed (${e.code}): ${e.message}');
      } on MissingPluginException {
        // An older build of the app shell without the channel — fall through.
        debugPrint('[DeviceFiles] channel unavailable, using app storage.');
      }
    }
    return _fallback(bytes, fileName);
  }

  /// App-private documents directory. Always writable, never needs permission,
  /// and still a real file the member can open from inside the app.
  static Future<String?> _fallback(Uint8List bytes, String fileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[DeviceFiles] fallback write failed: $e');
      return null;
    }
  }
}
