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

  /// LIVE stream of the user's own profile — see
  /// [FirestoreService.watchProfileByUserId] (admin↔user sync backbone).
  Stream<ProfileModel?> watchProfileByUserId(String userId) =>
      _firestore.watchProfileByUserId(userId);

  /// Another user's PUBLIC profile by UID (approved + active only) — safe to
  /// query for non-owners. See [FirestoreService.getApprovedProfileByUserId].
  Future<ProfileModel?> getApprovedProfileByUserId(String userId) =>
      _firestore.getApprovedProfileByUserId(userId);

  Stream<ProfileModel?> watchApprovedProfileByUserId(String userId) =>
      _firestore.watchApprovedProfileByUserId(userId);

  Stream<ProfileModel?> watchProfile(String profileId) => _firestore.watchProfile(profileId);

  // FULL reads — the public document with the member's private copy (hidden
  // photo / salary / horoscope) merged back in. For the OWNER and for admins
  // and staff only; see core/utils/profile_privacy.dart.
  Stream<ProfileModel?> watchFullProfile(String profileId) =>
      _firestore.watchFullProfile(profileId);
  Future<ProfileModel?> getFullProfile(String profileId) =>
      _firestore.getFullProfile(profileId);
  Stream<ProfileModel?> watchFullProfileByUserId(String userId) =>
      _firestore.watchFullProfileByUserId(userId);
  Future<ProfileModel?> getFullProfileByUserId(String userId) =>
      _firestore.getFullProfileByUserId(userId);
  Future<ContactDetails?> getFullContact(String userId) =>
      _firestore.getFullContact(userId);
  Stream<ContactDetails?> watchFullContact(String userId) =>
      _firestore.watchFullContact(userId);

  Future<MemberPrivacyRepair> reconcileMemberPrivacy(String profileId,
          {bool adminRepair = false}) =>
      _firestore.reconcileMemberPrivacy(profileId, adminRepair: adminRepair);

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

  /// Cursor-paginated, createdAt-ordered search (Matches feed + Home
  /// "Recommended"). Gender is the only matching filter applied at the DB level.
  Future<ProfilePage> searchProfilesPage({
    required String gender,
    int limit = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) =>
      _firestore.searchProfilesPage(
        gender: gender,
        limit: limit,
        startAfter: startAfter,
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

  /// Uploads a horoscope document (image or PDF) with a unique id — supports
  /// MULTIPLE horoscope images and PDFs per profile.
  Future<String> uploadHoroscopeDoc({
    required String userId,
    required File file,
    required bool isPdf,
  }) =>
      _storage.uploadHoroscopeDoc(userId: userId, file: file, isPdf: isPdf);

  // REMOVED: `updateProfilePhoto`.
  //
  // It uploaded a new image and then wrote it to a `photos` ARRAY on the
  // profile document — a field `ProfileModel.fromFirestore` does not read. The
  // stored photo is `profilePhotoUrl` (one photo per member, §1), so anything
  // saved through that method uploaded correctly to Cloudinary and then never
  // appeared anywhere in the app: exactly the "images are uploaded but not
  // fetched/displayed" symptom, waiting for the next caller to hit it.
  //
  // Photo replacement belongs to `ProfileEditController.save`, which is the one
  // path that writes the right field AND does everything else a new photo
  // implies — the `users/{uid}.photoUrl` mirror, the chat participant refresh
  // (§2), deleting the Cloudinary asset it replaced (§6/§24) and evicting its
  // cached bytes (§25). A second, half-correct way to do the same thing is how
  // those stopped being applied consistently in the first place.

  Future<void> incrementViewCount(String profileId) => _firestore.incrementViewCount(profileId);

  /// Reads another user's contact details. Succeeds only when the caller is the
  /// owner, an admin, or has a mutually-accepted connection — otherwise the
  /// Firestore rules reject the read (surfaced as a permission error the UI
  /// treats as "locked").
  Future<ContactDetails?> getContact(String userId) => _firestore.getContact(userId);

  /// LIVE contact details — see [FirestoreService.watchContact].
  Stream<ContactDetails?> watchContact(String userId) =>
      _firestore.watchContact(userId);

  /// Creates/updates the caller's own contact details in the gated
  /// `contacts/{userId}` collection (phone numbers split per "Hide Phone
  /// Number").
  Future<void> saveContact(String userId, ContactDetails contact) =>
      _firestore.saveContact(userId, contact);
}
