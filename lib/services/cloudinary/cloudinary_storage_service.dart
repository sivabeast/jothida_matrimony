import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../storage_service.dart';
import 'cloudinary_exception.dart';
import 'cloudinary_response.dart';

/// [StorageService] implementation backed by Cloudinary **unsigned uploads**.
///
/// Only the cloud name and an unsigned upload preset are needed on the
/// client — never embed the Cloudinary **API secret** in the app. With an
/// unsigned preset, deleting/overwriting assets normally requires a signed
/// admin-API call from a trusted server, so [deleteFile] and
/// [deleteProfilePhotos] are no-ops here (see their doc comments).
///
/// Flow: pick image → [uploadProfilePhoto]/[uploadMultiplePhotos] → Cloudinary
/// returns `secure_url` → caller saves that URL into Firestore
/// (`profiles/{id}.photos` and/or `users/{uid}.photoUrl`).
class CloudinaryStorageService implements StorageService {
  CloudinaryStorageService({
    this.cloudName = 'dh8hzjx5q',
    this.uploadPreset = 'matrimony_profiles',
    this.maxRetries = 3,
    http.Client? client,
  }) : _client = client;

  /// Cloudinary "Cloud name" (visible, not a secret).
  final String cloudName;

  /// Unsigned upload preset configured in the Cloudinary console
  /// (Settings → Upload → Upload presets). Must have **Signing mode:
  /// Unsigned**.
  final String uploadPreset;

  /// Number of attempts before giving up on a single file upload.
  final int maxRetries;

  /// Optional injected client (for testing). A fresh [http.Client] is
  /// created per request otherwise.
  final http.Client? _client;

  Uri _endpoint(String resourceType) =>
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload');

  // ── Public API ────────────────────────────────────────────────────────

  @override
  Future<String> uploadProfilePhoto({
    required String userId,
    required File file,
    required int index,
    void Function(double progress)? onProgress,
  }) {
    return _uploadWithRetry(
      file: file,
      resourceType: 'image',
      folder: 'jothida_matrimony/profiles/$userId/photos',
      publicId: 'photo_$index',
      onProgress: onProgress,
    );
  }

  @override
  Future<List<String>> uploadMultiplePhotos({
    required String userId,
    required List<File> files,
    void Function(double progress)? onProgress,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final url = await uploadProfilePhoto(
        userId: userId,
        file: files[i],
        index: i,
        onProgress: onProgress == null
            ? null
            : (p) => onProgress((i + p) / files.length),
      );
      urls.add(url);
    }
    return urls;
  }

  @override
  Future<String> uploadHoroscopePdf({
    required String userId,
    required File file,
    void Function(double progress)? onProgress,
  }) {
    return _uploadWithRetry(
      file: file,
      // PDFs must go through Cloudinary's "raw" delivery type.
      resourceType: 'raw',
      folder: 'jothida_matrimony/profiles/$userId/horoscope',
      publicId: 'horoscope',
      onProgress: onProgress,
    );
  }

  @override
  Future<String> uploadHoroscopeImage({
    required String userId,
    required File file,
    required int index,
  }) {
    return _uploadWithRetry(
      file: file,
      resourceType: 'image',
      folder: 'jothida_matrimony/profiles/$userId/horoscope',
      publicId: 'image_$index',
    );
  }

  @override
  Future<String> uploadIdProof({
    required String userId,
    required File file,
    required String docType,
  }) {
    return _uploadWithRetry(
      file: file,
      resourceType: 'image',
      folder: 'jothida_matrimony/profiles/$userId/id_proof',
      publicId: docType.toLowerCase(),
    );
  }

  @override
  Future<String> updateProfilePhoto({
    required String userId,
    required File file,
    required int index,
    void Function(double progress)? onProgress,
  }) {
    // Re-uploading with the same folder/public_id replaces the asset as long
    // as the upload preset has "Unique filename" off and "Overwrite" on
    // (Cloudinary console → Upload presets → matrimony_profiles). The
    // returned secure_url includes a fresh `version` segment, so callers
    // should overwrite the stored URL (no extra cache-busting needed).
    return uploadProfilePhoto(userId: userId, file: file, index: index, onProgress: onProgress);
  }

  @override
  Future<void> deleteFile(String downloadUrl) async {
    // Deleting a Cloudinary asset requires a signed `destroy` request signed
    // with the API secret. That secret must never ship inside the Flutter
    // app, so this is intentionally a no-op on the client. Wire this up to a
    // small trusted backend (Cloud Function) if hard deletes are needed.
    debugPrint(
      'CloudinaryStorageService.deleteFile: skipped (requires a signed '
      'server-side request) for $downloadUrl',
    );
  }

  @override
  Future<void> deleteProfilePhotos(String userId) async {
    debugPrint(
      'CloudinaryStorageService.deleteProfilePhotos: skipped (requires a '
      'signed server-side request) for user $userId',
    );
  }

  // ── Internals ─────────────────────────────────────────────────────────

  Future<String> _uploadWithRetry({
    required File file,
    required String resourceType,
    required String folder,
    required String publicId,
    void Function(double progress)? onProgress,
  }) async {
    if (!await file.exists()) {
      throw CloudinaryUploadException('File does not exist: ${file.path}');
    }

    Object? lastError;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        onProgress?.call(0);
        final url = await _uploadOnce(
          file: file,
          resourceType: resourceType,
          folder: folder,
          publicId: publicId,
          onProgress: onProgress,
        );
        onProgress?.call(1);
        return url;
      } catch (e, st) {
        lastError = e;
        debugPrint(
          'CloudinaryStorageService: upload attempt $attempt/$maxRetries '
          'failed for $folder/$publicId: $e',
        );
        if (e is CloudinaryUploadException && !e.isRetryable) {
          break; // Don't retry on permanent errors (bad preset, 4xx, etc.)
        }
        if (attempt < maxRetries) {
          // Exponential backoff: 1s, 2s, 4s, ...
          await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
        } else {
          debugPrint(st.toString());
        }
      }
    }

    throw CloudinaryUploadException(
      'Upload failed after $maxRetries attempt(s): $lastError',
    );
  }

  Future<String> _uploadOnce({
    required File file,
    required String resourceType,
    required String folder,
    required String publicId,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.MultipartRequest('POST', _endpoint(resourceType))
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder'] = folder
      ..fields['public_id'] = publicId
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await _send(request, onProgress);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final json = CloudinaryResponse.fromJsonString(response.body);
      if (json.secureUrl == null) {
        throw CloudinaryUploadException(
          'Cloudinary response missing secure_url: ${response.body}',
        );
      }
      return json.secureUrl!;
    }

    final message = CloudinaryResponse.errorMessage(response.body) ??
        'HTTP ${response.statusCode}';
    // 4xx (bad preset, validation, file too large) won't succeed on retry;
    // 5xx / network-ish errors are worth retrying.
    final retryable = response.statusCode >= 500;
    throw CloudinaryUploadException(message, statusCode: response.statusCode, isRetryable: retryable);
  }

  /// Sends [request], streaming the file body so [onProgress] can be called
  /// with the fraction of bytes uploaded so far (0..1).
  Future<http.StreamedResponse> _send(
    http.MultipartRequest request,
    void Function(double progress)? onProgress,
  ) async {
    final client = _client ?? http.Client();
    final ownsClient = _client == null;

    if (onProgress == null) {
      try {
        return await client.send(request);
      } finally {
        if (ownsClient) client.close();
      }
    }

    final totalBytes = request.contentLength;
    var bytesSent = 0;

    final streamedRequest = http.StreamedRequest(request.method, request.url)
      ..headers.addAll(request.headers)
      ..contentLength = totalBytes;

    request.finalize().listen(
      (chunk) {
        bytesSent += chunk.length;
        if (totalBytes > 0) {
          onProgress((bytesSent / totalBytes).clamp(0.0, 1.0));
        }
        streamedRequest.sink.add(chunk);
      },
      onDone: streamedRequest.sink.close,
      onError: (Object e, StackTrace st) => streamedRequest.sink.addError(e, st),
      cancelOnError: true,
    );

    try {
      return await client.send(streamedRequest);
    } finally {
      if (ownsClient) client.close();
    }
  }
}
