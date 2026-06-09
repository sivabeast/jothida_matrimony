import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

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

  Future<String> uploadHoroscopeImage({
    required String userId,
    required File file,
    required int index,
  }) async {
    final ref = _storage.ref('profiles/$userId/horoscope/image_$index.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<String> uploadIdProof({
    required String userId,
    required File file,
    required String docType,
  }) async {
    final ref = _storage.ref('profiles/$userId/id_proof/${docType.toLowerCase()}.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<void> deleteFile(String downloadUrl) async {
    try {
      final ref = _storage.refFromURL(downloadUrl);
      await ref.delete();
    } catch (e) {
      debugPrint('StorageService.deleteFile error: $e');
    }
  }

  Future<void> deleteProfilePhotos(String userId) async {
    try {
      final ref = _storage.ref('profiles/$userId/photos');
      final list = await ref.listAll();
      await Future.wait(list.items.map((item) => item.delete()));
    } catch (e) {
      debugPrint('StorageService.deleteProfilePhotos error: $e');
    }
  }
}
