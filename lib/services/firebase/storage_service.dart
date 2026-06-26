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
