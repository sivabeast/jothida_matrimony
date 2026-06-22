import 'dart:async';
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
      // Unique per upload (timestamp suffix) so replacing the profile photo
      // ALWAYS yields a new secure_url. With a fixed public_id the URL stayed
      // identical, and Flutter's image cache kept serving the OLD photo — so
      // changing the photo appeared to do nothing.
      publicId: 'photo_${index}_${DateTime.now().millisecondsSinceEpoch}',
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
  Future<String> uploadHoroscopeDoc({
    required String userId,
    required File file,
    required bool isPdf,
  }) {
    return _uploadWithRetry(
      file: file,
      // PDFs go through Cloudinary's "raw" delivery type; images via "image".
      resourceType: isPdf ? 'raw' : 'image',
      folder: 'jothida_matrimony/profiles/$userId/horoscope',
      // Unique per upload so multiple images / PDFs never overwrite each other.
      publicId:
          '${isPdf ? 'pdf' : 'img'}_${DateTime.now().millisecondsSinceEpoch}',
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
    // Delegates to [uploadProfilePhoto], which uses a UNIQUE public_id per
    // upload — so each replacement returns a brand-new secure_url that can
    // never collide with the cached previous image (no dependency on the
    // preset's overwrite setting).
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

  /// Per-attempt network timeout. Cloudinary uploads from a mobile network
  /// can be slow; this just turns an indefinite hang into a retryable
  /// [CloudinaryUploadException] instead of the UI spinning forever.
  static const _uploadTimeout = Duration(seconds: 60);

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

    final sizeBytes = await file.length();
    debugPrint(
      'CloudinaryStorageService: starting upload of ${file.path} '
      '($sizeBytes bytes) -> $folder/$publicId (resourceType=$resourceType)',
    );

    Object? lastError;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        onProgress?.call(0);
        debugPrint(
          'CloudinaryStorageService: attempt $attempt/$maxRetries for '
          '$folder/$publicId',
        );
        final url = await _uploadOnce(
          file: file,
          resourceType: resourceType,
          folder: folder,
          publicId: publicId,
          onProgress: onProgress,
        );
        onProgress?.call(1);
        debugPrint(
          'CloudinaryStorageService: upload succeeded for $folder/$publicId '
          '-> $url',
        );
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

    final client = _client ?? http.Client();
    final ownsClient = _client == null;
    final http.Response response;
    try {
      // IMPORTANT: the response body must be fully read *before* the client
      // is closed. http.Client.close() force-closes the underlying socket,
      // which previously caused
      // "ClientException: Connection closed while receiving data" because
      // the client was closed right after send() returned (i.e. as soon as
      // headers arrived), aborting the body stream that
      // http.Response.fromStream() was about to read.
      final streamedResponse =
          await _send(client, request, onProgress).timeout(_uploadTimeout);
      response = await http.Response.fromStream(streamedResponse)
          .timeout(_uploadTimeout);
    } on TimeoutException catch (e) {
      throw CloudinaryUploadException('Upload timed out: $e');
    } on http.ClientException catch (e) {
      // Network-level failure (connection dropped, DNS, TLS, etc.) — worth
      // retrying.
      throw CloudinaryUploadException('Network error: $e');
    } finally {
      if (ownsClient) client.close();
    }

    debugPrint(
      'CloudinaryStorageService: $folder/$publicId -> '
      'HTTP ${response.statusCode}',
    );

    if (response.statusCode == 200) {
      final json = CloudinaryResponse.fromJsonString(response.body);
      if (json.secureUrl == null) {
        debugPrint(
          'CloudinaryStorageService: ⚠ 200 OK but secure_url missing '
          'for $folder/$publicId — full body: ${response.body}',
        );
        throw CloudinaryUploadException(
          'Cloudinary response missing secure_url: ${response.body}',
        );
      }
      debugPrint(
        'CloudinaryStorageService: ✅ secure_url received for '
        '$folder/$publicId → ${json.secureUrl}',
      );
      return json.secureUrl!;
    }

    final message = CloudinaryResponse.errorMessage(response.body) ??
        'HTTP ${response.statusCode}: ${response.body}';
    debugPrint(
      'CloudinaryStorageService: ❌ upload error for $folder/$publicId '
      '→ HTTP ${response.statusCode}  body: ${response.body}',
    );
    // 4xx (bad preset, validation, file too large) won't succeed on retry;
    // 5xx / network-ish errors are worth retrying.
    final retryable = response.statusCode >= 500;
    throw CloudinaryUploadException(message, statusCode: response.statusCode, isRetryable: retryable);
  }

  /// Sends [request] using [client], streaming the file body so [onProgress]
  /// can be called with the fraction of bytes uploaded so far (0..1).
  ///
  /// Does NOT close [client] — the caller is responsible for closing it once
  /// the response body has been fully read.
  Future<http.StreamedResponse> _send(
    http.Client client,
    http.MultipartRequest request,
    void Function(double progress)? onProgress,
  ) async {
    if (onProgress == null) {
      return client.send(request);
    }

    final totalBytes = request.contentLength;
    var bytesSent = 0;

    // ── FIX: finalize() BEFORE copying headers ─────────────────────────────
    // http.MultipartRequest.finalize() writes the
    // "Content-Type: multipart/form-data; boundary=<uuid>" header onto
    // request.headers as a side-effect.  If we copy request.headers BEFORE
    // calling finalize() — as the original code did — the Content-Type is
    // absent from streamedRequest.  Cloudinary then cannot parse the body
    // and returns HTTP 400 ("Unable to parse multipart body" / "upload
    // preset not found"), causing the upload to fail on every attempt.
    // Calling finalize() first ensures the Content-Type is present when
    // we call addAll().
    final bodyStream = request.finalize();

    final streamedRequest = http.StreamedRequest(request.method, request.url)
      ..headers.addAll(request.headers) // now includes Content-Type
      ..contentLength = totalBytes;

    debugPrint(
      'CloudinaryStorageService._send: Content-Type = '
      '${streamedRequest.headers['content-type'] ?? '⚠ MISSING'}  '
      'contentLength=$totalBytes',
    );

    bodyStream.listen(
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

    return client.send(streamedRequest);
  }
}
