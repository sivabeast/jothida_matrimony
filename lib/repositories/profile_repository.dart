import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/profile_model.dart';
import '../services/firebase/firestore_service.dart';
import '../services/storage_service.dart';

class ProfileRepository {
  final FirestoreService _firestore;
  final StorageService _storage;

  ProfileRepository(this._firestore, this._storage);

  Future<String> createProfile(ProfileModel profile) => _firestore.createProfile(profile);

  Future<void> updateProfile(String profileId, Map<String, dynamic> data) =>
      _firestore.updateProfile(profileId, data);

  Future<ProfileModel?> getProfile(String profileId) => _firestore.getProfile(profileId);

  Future<ProfileModel?> getProfileByUserId(String userId) => _firestore.getProfileByUserId(userId);

  /// Another user's PUBLIC profile by UID (approved + active only) — safe to
  /// query for non-owners. See [FirestoreService.getApprovedProfileByUserId].
  Future<ProfileModel?> getApprovedProfileByUserId(String userId) =>
      _firestore.getApprovedProfileByUserId(userId);

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
    int limit = 60,
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
    void Function(double)? onProgress,
  }) =>
      _storage.uploadHoroscopePdf(userId: userId, file: file, onProgress: onProgress);

  /// Replaces a single profile photo (e.g. from an "Edit profile" screen)
  /// and updates the `photos` array on the profile document.
  Future<String> updateProfilePhoto({
    required String userId,
    required String profileId,
    required File file,
    required int index,
    required List<String> currentPhotos,
    void Function(double)? onProgress,
  }) async {
    final url = await _storage.updateProfilePhoto(
      userId: userId,
      file: file,
      index: index,
      onProgress: onProgress,
    );
    final photos = [...currentPhotos];
    if (index < photos.length) {
      photos[index] = url;
    } else {
      photos.add(url);
    }
    await _firestore.updateProfile(profileId, {'photos': photos});
    return url;
  }

  Future<void> incrementViewCount(String profileId) => _firestore.incrementViewCount(profileId);

  /// Reads another user's contact details. Succeeds only when the caller is the
  /// owner, an admin, or has a mutually-accepted connection — otherwise the
  /// Firestore rules reject the read (surfaced as a permission error the UI
  /// treats as "locked").
  Future<ContactDetails?> getContact(String userId) => _firestore.getContact(userId);

  /// Creates/updates the caller's own contact details in the gated
  /// `contacts/{userId}` collection.
  Future<void> saveContact(String userId, ContactDetails contact) =>
      _firestore.saveContact(userId, contact);
}
