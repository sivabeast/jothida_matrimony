import 'dart:convert';

/// Minimal parsed view of a Cloudinary `/upload` JSON response — only the
/// fields this app currently needs.
class CloudinaryResponse {
  const CloudinaryResponse({
    this.secureUrl,
    this.publicId,
    this.version,
    this.format,
    this.resourceType,
  });

  final String? secureUrl;
  final String? publicId;
  final int? version;
  final String? format;
  final String? resourceType;

  factory CloudinaryResponse.fromJsonString(String body) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    return CloudinaryResponse(
      secureUrl: map['secure_url'] as String?,
      publicId: map['public_id'] as String?,
      version: map['version'] as int?,
      format: map['format'] as String?,
      resourceType: map['resource_type'] as String?,
    );
  }

  /// Best-effort extraction of `error.message` from a non-200 response body.
  /// Returns null if the body isn't JSON or has no error message.
  static String? errorMessage(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final error = map['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
    } catch (_) {
      // Non-JSON body — ignore.
    }
    return null;
  }
}
