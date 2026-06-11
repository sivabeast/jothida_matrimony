import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../models/profile_model.dart';
import '../../models/interest_model.dart';
import '../../models/subscription_model.dart';
import '../../models/report_model.dart';
import '../../models/notification_model.dart';
import '../../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Users ───────────────────────────────────────────────────────────────────
  /// Creates the user document on first login, or just refreshes `lastLoginAt`
  /// for a returning user — never creates a duplicate.
  ///
  /// Stored fields: uid (doc id), email, displayName (name), photoUrl,
  /// loginProvider, createdAt, lastLoginAt, isProfileComplete
  /// (profileCompleted), membershipType, plus the app's account metadata.
  /// Returns the resulting [UserModel].
  ///
  /// [loginProvider] records how the user authenticated this time (e.g.
  /// `'google.com'`, `'password'`, `'phone'`). It is stored on first creation
  /// and refreshed on every subsequent login so it always reflects the most
  /// recently used sign-in method.
  Future<UserModel> createOrUpdateUserOnLogin(User user,
      {String? phone, String? loginProvider}) async {
    final docRef =
        _db.collection(AppConstants.usersCollection).doc(user.uid);

    debugPrint('[Firestore] createOrUpdateUserOnLogin(${user.uid}): '
        'starting transaction...');
    try {
      // A transaction makes the "create if new, else update lastLoginAt" step
      // atomic, so concurrent logins can't race into a duplicate write.
      await _db.runTransaction((txn) async {
        final snap = await txn.get(docRef);
        if (!snap.exists) {
          debugPrint('[Firestore] ${user.uid}: no existing doc → creating '
              'new user (isProfileComplete=false)');
          final now = DateTime.now();
          final newUser = UserModel(
            uid: user.uid,
            email: user.email,
            phone: phone ?? user.phoneNumber,
            displayName: user.displayName,
            photoUrl: user.photoURL,
            loginProvider: loginProvider,
            membershipType: 'free',
            isProfileComplete: false,
            isEmailVerified: user.emailVerified,
            createdAt: now,
            updatedAt: now,
            lastLoginAt: now,
          );
          // Use server timestamps for the audit fields once written.
          txn.set(docRef, {
            ...newUser.toFirestore(),
            'createdAt': FieldValue.serverTimestamp(),
            'lastLoginAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          debugPrint('[Firestore] ${user.uid}: existing doc found → '
              'refreshing lastLoginAt/loginProvider');
          // Existing user → bump lastLoginAt and refresh the login provider
          // (no duplicate document).
          txn.update(docRef, {
            'lastLoginAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            if (loginProvider != null) 'loginProvider': loginProvider,
          });
        }
      });
    } catch (e, st) {
      debugPrint('[Firestore] createOrUpdateUserOnLogin(${user.uid}) '
          'transaction FAILED: $e\n$st');
      rethrow;
    }

    debugPrint('[Firestore] ${user.uid}: transaction committed, re-reading doc...');
    final fresh = await docRef.get();
    debugPrint('[Firestore] ${user.uid}: doc read OK '
        '(exists=${fresh.exists})');
    return UserModel.fromFirestore(fresh);
  }

  /// Saves the essential registration details collected on the user signup
  /// form (name, mobile, gender, DOB, location) onto `users/{uid}`.
  Future<void> saveUserRegistrationDetails(
    String uid, {
    required String name,
    required String phone,
    required String gender,
    required DateTime dateOfBirth,
    required String location,
  }) =>
      _db.collection(AppConstants.usersCollection).doc(uid).set({
        'displayName': name,
        'phone': phone,
        'gender': gender,
        'dateOfBirth': Timestamp.fromDate(dateOfBirth),
        'location': location,
        'role': AppConstants.roleUser,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Stream<UserModel?> watchUser(String uid) => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);

  Future<UserModel?> getUser(String uid) async {
    final doc =
        await _db.collection(AppConstants.usersCollection).doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  Future<void> updateFcmToken(String uid, String token) => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .set({'fcmToken': token, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));

  /// Marks the user's profile as completed (gates Home access). Writes both
  /// `isProfileComplete` (app field) and `profileCompleted` (spec field).
  Future<void> markProfileCompleted(String uid) => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .set({
        'isProfileComplete': true,
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ── Profiles ──────────────────────────────────────────────────────────────
  Future<String> createProfile(ProfileModel profile) async {
    final doc = _db.collection(AppConstants.profilesCollection).doc();
    await doc.set(profile.copyWith().toFirestore());
    return doc.id;
  }

  Future<void> updateProfile(String profileId, Map<String, dynamic> data) =>
      _db.collection(AppConstants.profilesCollection).doc(profileId).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<ProfileModel?> getProfile(String profileId) async {
    final doc = await _db.collection(AppConstants.profilesCollection).doc(profileId).get();
    if (!doc.exists) return null;
    return ProfileModel.fromFirestore(doc);
  }

  Future<ProfileModel?> getProfileByUserId(String userId) async {
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ProfileModel.fromFirestore(snap.docs.first);
  }

  Stream<ProfileModel?> watchProfile(String profileId) =>
      _db.collection(AppConstants.profilesCollection).doc(profileId).snapshots().map(
            (doc) => doc.exists ? ProfileModel.fromFirestore(doc) : null,
          );

  Future<List<ProfileModel>> searchProfiles({
    required String gender,
    int? minAge,
    int? maxAge,
    String? religion,
    String? caste,
    String? rasi,
    String? nakshatra,
    String? city,
    String? state,
    DocumentSnapshot? lastDoc,
    int limit = 20,
  }) async {
    Query query = _db
        .collection(AppConstants.profilesCollection)
        .where('status', isEqualTo: 'approved')
        .where('isActive', isEqualTo: true)
        .where('gender', isEqualTo: gender);

    if (religion != null && religion != 'Any') {
      query = query.where('religion', isEqualTo: religion);
    }
    if (city != null && city.isNotEmpty) {
      query = query.where('city', isEqualTo: city);
    }

    query = query.orderBy('createdAt', descending: true).limit(limit);
    if (lastDoc != null) query = query.startAfterDocument(lastDoc);

    final snap = await query.get();
    return snap.docs.map((d) => ProfileModel.fromFirestore(d)).toList();
  }

  Future<void> incrementViewCount(String profileId) => _db
      .collection(AppConstants.profilesCollection)
      .doc(profileId)
      .update({'viewCount': FieldValue.increment(1)});

  // ── Interests ─────────────────────────────────────────────────────────────
  Future<void> sendInterest(InterestModel interest) => _db
      .collection(AppConstants.interestsCollection)
      .doc(interest.id)
      .set(interest.toFirestore());

  Future<void> updateInterestStatus(String interestId, String status) => _db
      .collection(AppConstants.interestsCollection)
      .doc(interestId)
      .update({'status': status, 'respondedAt': FieldValue.serverTimestamp()});

  Stream<List<InterestModel>> watchSentInterests(String userId) => _db
      .collection(AppConstants.interestsCollection)
      .where('senderId', isEqualTo: userId)
      .orderBy('sentAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => InterestModel.fromFirestore(d)).toList());

  Stream<List<InterestModel>> watchReceivedInterests(String userId) => _db
      .collection(AppConstants.interestsCollection)
      .where('receiverId', isEqualTo: userId)
      .orderBy('sentAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => InterestModel.fromFirestore(d)).toList());

  Future<InterestModel?> getInterestBetweenProfiles(
    String senderProfileId,
    String receiverProfileId,
  ) async {
    final snap = await _db
        .collection(AppConstants.interestsCollection)
        .where('senderProfileId', isEqualTo: senderProfileId)
        .where('receiverProfileId', isEqualTo: receiverProfileId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return InterestModel.fromFirestore(snap.docs.first);
  }

  // ── Subscriptions ─────────────────────────────────────────────────────────
  Future<void> saveSubscription(SubscriptionModel sub) => _db
      .collection(AppConstants.subscriptionsCollection)
      .doc(sub.id)
      .set(sub.toFirestore());

  Future<SubscriptionModel?> getActiveSubscription(String userId) async {
    final snap = await _db
        .collection(AppConstants.subscriptionsCollection)
        .where('userId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return SubscriptionModel.fromFirestore(snap.docs.first);
  }

  // ── Reports ───────────────────────────────────────────────────────────────
  Future<void> submitReport(ReportModel report) async {
    await _db.collection(AppConstants.reportsCollection).doc(report.id).set(report.toFirestore());
    // Update profile report count and alert level
    final count = await _getProfileReportCount(report.reportedProfileId);
    await _db.collection(AppConstants.profilesCollection).doc(report.reportedProfileId).update({
      'reportCount': FieldValue.increment(1),
    });
  }

  Future<int> _getProfileReportCount(String profileId) async {
    final snap = await _db
        .collection(AppConstants.reportsCollection)
        .where('reportedProfileId', isEqualTo: profileId)
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<List<ReportModel>> getAllReports() async {
    final snap = await _db
        .collection(AppConstants.reportsCollection)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => ReportModel.fromFirestore(d)).toList();
  }

  // ── Notifications ─────────────────────────────────────────────────────────
  Future<void> saveNotification(NotificationModel notification) => _db
      .collection(AppConstants.notificationsCollection)
      .doc(notification.id)
      .set(notification.toFirestore());

  Stream<List<NotificationModel>> watchNotifications(String userId) => _db
      .collection(AppConstants.notificationsCollection)
      .where('userId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map((d) => NotificationModel.fromFirestore(d)).toList());

  Future<void> markNotificationRead(String notificationId) => _db
      .collection(AppConstants.notificationsCollection)
      .doc(notificationId)
      .update({'isRead': true});

  // ── Admin ─────────────────────────────────────────────────────────────────
  Future<List<UserModel>> getAllUsers({int limit = 50}) async {
    final snap = await _db
        .collection(AppConstants.usersCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => UserModel.fromFirestore(d)).toList();
  }

  Future<List<ProfileModel>> getPendingProfiles() async {
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt')
        .get();
    return snap.docs.map((d) => ProfileModel.fromFirestore(d)).toList();
  }

  Future<void> approveProfile(String profileId) => _db
      .collection(AppConstants.profilesCollection)
      .doc(profileId)
      .update({'status': 'approved', 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> rejectProfile(String profileId, String reason) => _db
      .collection(AppConstants.profilesCollection)
      .doc(profileId)
      .update({'status': 'rejected', 'rejectionReason': reason, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> blockUser(String userId) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).update({'isBlocked': true});
    await _db
        .collection(AppConstants.profilesCollection)
        .where('userId', isEqualTo: userId)
        .get()
        .then((s) {
      for (final doc in s.docs) {
        doc.reference.update({'status': 'blocked', 'isActive': false});
      }
    });
  }

  Future<Map<String, dynamic>> getAdminStats() async {
    final users = await _db.collection(AppConstants.usersCollection).count().get();
    final profiles = await _db.collection(AppConstants.profilesCollection).count().get();
    final pendingProfiles = await _db
        .collection(AppConstants.profilesCollection)
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    final reports = await _db.collection(AppConstants.reportsCollection).count().get();

    return {
      'totalUsers': users.count,
      'totalProfiles': profiles.count,
      'pendingProfiles': pendingProfiles.count,
      'totalReports': reports.count,
    };
  }
}
