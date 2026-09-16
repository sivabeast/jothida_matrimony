import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../storage_service.dart';

/// Firebase Storage implementation of [StorageService].
///
/// Not used by default — the app currently uploads profile media to
/// Cloudinary via [CloudinaryStorageService] (see
/// `lib/services/cloudinary/cloudinary_storage_service.dart`) because
/// Firebase Storage requires the project to be on the Blaze billing plan.
/// To switch back, change `storageServiceProvider` in
/// `lib/providers/service_providers.dart` to `FirebaseStorageService()` —
/// no other code needs to change.
class FirebaseStorageService implements StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  Future<String> uploadProfilePhoto({
    required String userId,
    required File file,
    required int index,
    void Function(double)? onProgress,
  }) async {
    final ref = _storage.ref('profiles/$userId/photos/photo_$index.jpg');
    final task = ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    if (onProgress != null) {
      task.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress(progress);
      });
    }
    await task;
    return await ref.getDownloadURL();
  }

  @override
  Future<List<String>> uploadMultiplePhotos({
    required String userId,
    required List<File> files,
    void Function(double)? onProgress,
  }) async {
    final urls = <String>[];
    for (int i = 0; i < files.length; i++) {
      final url = await uploadProfilePhoto(
        userId: userId,
        file: files[i],
        index: i,
        onProgress: (p) => onProgress?.call((i + p) / files.length),
      );
      urls.add(url);
    }
    return urls;
  }

  @override
  Future<String> uploadHoroscopePdf({
    required String userId,
    required File file,
    void Function(double)? onProgress,
  }) async {
    final ref = _storage.ref('profiles/$userId/horoscope/horoscope.pdf');
    final task = ref.putFile(file, SettableMetadata(contentType: 'application/pdf'));
    if (onProgress != null) {
      task.snapshotEvents.listen((snapshot) {
        onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
      });
    }
    await task;
    return await ref.getDownloadURL();
  }

  @override
  Future<String> uploadHoroscopeImage({
    required String userId,
    required File file,
    required int index,
  }) async {
    final ref = _storage.ref('profiles/$userId/horoscope/image_$index.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  @override
  Future<String> uploadHoroscopeDoc({
    required String userId,
    required File file,
    required bool isPdf,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = isPdf ? 'pdf' : 'jpg';
    final ref = _storage
        .ref('profiles/$userId/horoscope/${isPdf ? 'pdf' : 'img'}_$ts.$ext');
    await ref.putFile(
      file,
      SettableMetadata(
          contentType: isPdf ? 'application/pdf' : 'image/jpeg'),
    );
    return await ref.getDownloadURL();
  }

  @override
  Future<String> uploadIdProof({
    required String userId,
    required File file,
    required String docType,
  }) async {
    final ref = _storage.ref('profiles/$userId/id_proof/${docType.toLowerCase()}.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  @override
  Future<String> uploadChatAttachment({
    required String threadId,
    required File file,
    required bool isImage,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = file.path.split('.').last.toLowerCase();
    final ref = _storage
        .ref('chat/$threadId/${isImage ? 'img' : 'doc'}_$ts.$ext');
    await ref.putFile(
      file,
      SettableMetadata(
          contentType: isImage ? 'image/jpeg' : 'application/octet-stream'),
    );
    return await ref.getDownloadURL();
  }

  @override
  Future<String> uploadWeddingDocument({
    required String weddingId,
    required File file,
    required bool isImage,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = file.path.split('.').last.toLowerCase();
    final ref = _storage
        .ref('weddings/$weddingId/${isImage ? 'img' : 'doc'}_$ts.$ext');
    await ref.putFile(
      file,
      SettableMetadata(
          contentType: isImage ? 'image/jpeg' : 'application/octet-stream'),
    );
    return await ref.getDownloadURL();
  }

  @override
  Future<String> updateProfilePhoto({
    required String userId,
    required File file,
    required int index,
    void Function(double)? onProgress,
  }) {
    // Same path/index overwrites the existing object in Firebase Storage.
    return uploadProfilePhoto(userId: userId, file: file, index: index, onProgress: onProgress);
  }

  @override
  Future<void> deleteFile(String downloadUrl) async {
    try {
      final ref = _storage.refFromURL(downloadUrl);
      await ref.delete();
    } catch (e) {
      debugPrint('FirebaseStorageService.deleteFile error: $e');
    }
  }

  /// Deletes EVERY file under `profiles/{userId}/` in Firebase Storage —
  /// photos, horoscope documents and ID proofs uploaded before media moved to
  /// Cloudinary — for account deletion.
  ///
  /// Scoped to the one member's own folder, so nothing belonging to anyone else
  /// can be touched; the storage rules only allow the owner to write (and
  /// delete) there anyway. Returns the number of files deleted, or -1 when
  /// Storage could not be reached. Never throws.
  static Future<int> deleteUserFolder(String userId,
      {FirebaseStorage? storage}) async {
    if (userId.trim().isEmpty) return 0;
    var deleted = 0;
    Future<void> sweep(Reference folder) async {
      final list = await folder.listAll().timeout(const Duration(seconds: 15));
      for (final item in list.items) {
        await item.delete().timeout(const Duration(seconds: 15));
        deleted++;
      }
      for (final sub in list.prefixes) {
        await sweep(sub);
      }
    }

    try {
      final bucket = storage ?? FirebaseStorage.instance;
      await sweep(bucket.ref('profiles/${userId.trim()}'));
      debugPrint('FirebaseStorageService.deleteUserFolder($userId): '
          '$deleted file(s) deleted.');
      return deleted;
    } catch (e) {
      debugPrint('FirebaseStorageService.deleteUserFolder($userId) '
          'incomplete after $deleted file(s): $e');
      return -1;
    }
  }

  @override
  Future<void> deleteProfilePhotos(String userId) async {
    try {
      final ref = _storage.ref('profiles/$userId/photos');
      final list = await ref.listAll();
      await Future.wait(list.items.map((item) => item.delete()));
    } catch (e) {
      debugPrint('FirebaseStorageService.deleteProfilePhotos error: $e');
    }
  }
}
