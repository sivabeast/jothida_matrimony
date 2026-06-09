import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/profile_model.dart';
import '../services/firebase/firestore_service.dart';
import '../services/firebase/storage_service.dart';

class ProfileRepository {
  final FirestoreService _firestore;
  final StorageService _storage;

  ProfileRepository(this._firestore, this._storage);

  Future<String> createProfile(ProfileModel profile) => _firestore.createProfile(profile);

  Future<void> updateProfile(String profileId, Map<String, dynamic> data) =>
      _firestore.updateProfile(profileId, data);

  Future<ProfileModel?> getProfile(String profileId) => _firestore.getProfile(profileId);

  Future<ProfileModel?> getProfileByUserId(String userId) => _firestore.getProfileByUserId(userId);

  Stream<ProfileModel?> watchProfile(String profileId) => _firestore.watchProfile(profileId);

  Future<List<ProfileModel>> searchProfiles({
    required String gender,
    int? minAge,
    int? maxAge,
    String? religion,
    String? caste,
    String? rasi,
    String? nakshatra,
    String? city,
    DocumentSnapshot? lastDoc,
    int limit = 20,
  }) =>
      _firestore.searchProfiles(
        gender: gender,
        minAge: minAge,
        maxAge: maxAge,
        religion: religion,
        caste: caste,
        rasi: rasi,
        nakshatra: nakshatra,
        city: city,
        lastDoc: lastDoc,
        limit: limit,
      );

  Future<List<String>> uploadPhotos({
    required String userId,
    required List<File> files,
    void Function(double)? onProgress,
  }) =>
      _storage.uploadMultiplePhotos(userId: userId, files: files, onProgress: onProgress);

  Future<String> uploadHoroscopePdf({
    required String userId,
    required File file,
  }) =>
      _storage.uploadHoroscopePdf(userId: userId, file: file);

  Future<void> incrementViewCount(String profileId) => _firestore.incrementViewCount(profileId);
}
