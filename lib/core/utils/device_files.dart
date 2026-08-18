import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// A file that has been written to the phone.
class SavedFile {
  /// Where the member can find it, e.g. "Download/Priya_profile.pdf". Shown in
  /// the confirmation, not used to open anything.
  final String location;

  /// A real filesystem path holding the same bytes.
  ///
  /// The saved copy itself may live behind a MediaStore `content://` URI, which
  /// the share sheet cannot attach, so a second copy is kept in the app cache
  /// purely so "Share" has something to hand to WhatsApp.
  final String sharePath;

  const SavedFile({required this.location, required this.sharePath});
}

/// Saves generated files **straight into the phone's own storage**.
///
/// The profile download has to behave like a browser download — tap, then find
/// the file in Downloads — rather than "tap, pick an app, hope it saves". So
/// the save itself never goes through a share sheet. Sharing afterwards is a
/// separate, explicit choice the member makes from the confirmation dialog.
///
/// On Android this calls through to MediaStore (see `MainActivity.kt`), the
/// only sanctioned route into shared storage on API 29+, which needs no runtime
/// permission. Anywhere else — and if the platform call fails — it falls back
/// to the app's documents directory so a download still produces a file.
class DeviceFiles {
  DeviceFiles._();

  static const MethodChannel _channel =
      MethodChannel('com.jothida.jothida_matrimony/device_files');

  /// Writes [bytes] to the device Downloads folder.
  static Future<SavedFile?> saveToDownloads(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/pdf',
  }) =>
      _save('saveToDownloads', bytes, fileName: fileName, mimeType: mimeType);

  /// Writes [bytes] to the device gallery (Pictures/Jothida Matrimony).
  static Future<SavedFile?> saveToPictures(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'image/png',
  }) =>
      _save('saveToPictures', bytes, fileName: fileName, mimeType: mimeType);

  static Future<SavedFile?> _save(
    String method,
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    // Written first and unconditionally: this is what "Share" attaches, and it
    // must exist even when the MediaStore write is the one that succeeded.
    final sharePath = await _cacheCopy(bytes, fileName);

    if (Platform.isAndroid) {
      try {
        final location = await _channel.invokeMethod<String>(method, {
          'bytes': bytes,
          'fileName': fileName,
          'mimeType': mimeType,
        });
        if (location != null && location.isNotEmpty && sharePath != null) {
          return SavedFile(location: location, sharePath: sharePath);
        }
      } on PlatformException catch (e) {
        debugPrint('[DeviceFiles] $method failed (${e.code}): ${e.message}');
      } on MissingPluginException {
        debugPrint('[DeviceFiles] channel unavailable, using app storage.');
      }
    }

    // Fallback: app documents. Still a real file the member keeps and shares.
    final fallback = await _documentsCopy(bytes, fileName);
    if (fallback == null) return null;
    return SavedFile(location: fallback, sharePath: sharePath ?? fallback);
  }

  static Future<String?> _cacheCopy(Uint8List bytes, String fileName) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[DeviceFiles] cache copy failed: $e');
      return null;
    }
  }

  static Future<String?> _documentsCopy(Uint8List bytes, String fileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[DeviceFiles] documents write failed: $e');
      return null;
    }
  }
}
