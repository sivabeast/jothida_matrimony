/// Thrown by [CloudinaryStorageService] when an upload fails (after retries
/// for retryable errors).
class CloudinaryUploadException implements Exception {
  CloudinaryUploadException(this.message, {this.statusCode, this.isRetryable = true});

  /// Human-readable message — either Cloudinary's own `error.message` or a
  /// local description (network error, missing file, etc.).
  final String message;

  /// HTTP status code returned by Cloudinary, if any.
  final int? statusCode;

  /// Whether retrying the same upload is likely to help. `4xx` responses
  /// (bad/missing upload preset, validation errors, file too large) are not
  /// retryable; network errors and `5xx` responses are.
  final bool isRetryable;

  @override
  String toString() => 'CloudinaryUploadException'
      '${statusCode != null ? '($statusCode)' : ''}: $message';
}
