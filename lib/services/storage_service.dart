import 'dart:io';

/// Abstraction over "wherever profile media is stored" so the rest of the
/// app (UI, providers, repositories) never talks to Firebase Storage,
/// Cloudinary, or any other backend directly.
///
/// Currently backed by [CloudinaryStorageService]
/// (see `lib/services/cloudinary/cloudinary_storage_service.dart`).
/// `FirebaseStorageService` (see `lib/services/firebase/storage_service.dart`)
/// implements the same interface and can be swapped back in via
/// `storageServiceProvider` in `lib/providers/service_providers.dart`
/// without touching any UI code.
abstract class StorageService {
  /// Uploads a single profile photo and returns its public URL.
  Future<String> uploadProfilePhoto({
    required String userId,
    required File file,
    required int index,
    void Function(double progress)? onProgress,
  });

  /// Uploads multiple profile photos, reporting overall progress (0..1)
  /// across all files combined.
  Future<List<String>> uploadMultiplePhotos({
    required String userId,
    required List<File> files,
    void Function(double progress)? onProgress,
  });

  /// Uploads the horoscope PDF and returns its public URL.
  Future<String> uploadHoroscopePdf({
    required String userId,
    required File file,
    void Function(double progress)? onProgress,
  });

  /// Uploads a horoscope chart/image and returns its public URL.
  Future<String> uploadHoroscopeImage({
    required String userId,
    required File file,
    required int index,
  });

  /// Uploads a horoscope document (image or PDF) under the user's horoscope
  /// folder with a UNIQUE id, so a profile can hold MULTIPLE horoscope images
  /// AND multiple horoscope PDFs without files overwriting one another.
  /// Returns the public URL.
  Future<String> uploadHoroscopeDoc({
    required String userId,
    required File file,
    required bool isPdf,
  });

  /// Uploads an ID-proof document and returns its public URL.
  Future<String> uploadIdProof({
    required String userId,
    required File file,
    required String docType,
  });

  /// Replaces an existing profile photo at [index] (e.g. from an "Edit
  /// profile photo" screen) and returns the new public URL.
  Future<String> updateProfilePhoto({
    required String userId,
    required File file,
    required int index,
    void Function(double progress)? onProgress,
  });

  /// Deletes a previously uploaded file given its public URL.
  Future<void> deleteFile(String downloadUrl);

  /// Deletes all of a user's profile photos.
  Future<void> deleteProfilePhotos(String userId);
}
