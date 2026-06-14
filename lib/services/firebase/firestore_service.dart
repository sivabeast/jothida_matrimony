import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../core/config/admin_config.dart';
import '../../models/profile_model.dart';
import '../../models/interest_model.dart';
import '../../models/subscription_model.dart';
import '../../models/report_model.dart';
import '../../models/account_deletion_request_model.dart';
import '../../models/notification_model.dart';
import '../../models/user_model.dart';
import '../../models/dashboard_analytics.dart';
import '../../models/admin_activity.dart';

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
            // Auto-assign super_admin to whitelisted accounts; everyone else
            // defaults to 'user'.
            role: AdminConfig.roleForEmail(user.email),
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
          // (no duplicate document). Also auto-promote a configured Super Admin
          // account if its document was created before being whitelisted.
          final existing = snap.data() as Map<String, dynamic>?;
          final currentRole = existing?['role'];
          final isWhitelisted = AdminConfig.isSuperAdminEmail(user.email);
          final promoteSuperAdmin =
              isWhitelisted && currentRole != AdminConfig.roleSuperAdmin;
          // The whitelist is the single source of truth: an account that still
          // holds super_admin but is no longer whitelisted is demoted to a
          // normal user, so revoking access just means editing the whitelist.
          final demoteSuperAdmin =
              !isWhitelisted && currentRole == AdminConfig.roleSuperAdmin;
          if (promoteSuperAdmin) {
            debugPrint('[Firestore] ${user.uid}: promoting ${user.email} '
                '→ super_admin');
          }
          if (demoteSuperAdmin) {
            debugPrint('[Firestore] ${user.uid}: ${user.email} no longer '
                'whitelisted → demoting super_admin to user');
          }
          txn.update(docRef, {
            'lastLoginAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            if (loginProvider != null) 'loginProvider': loginProvider,
            if (promoteSuperAdmin) 'role': AdminConfig.roleSuperAdmin,
            if (demoteSuperAdmin) 'role': AdminConfig.roleUser,
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
        // Role is assigned in createOrUpdateUserOnLogin (which honours the
        // Super Admin whitelist); don't overwrite it here.
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

  /// Keeps the denormalized `users/{uid}.photoUrl` in sync with the profile
  /// photo so the home header, chats and anywhere else reading it show the same
  /// image. Pass null to clear it (photo removed).
  Future<void> updateUserPhoto(String uid, String? url) => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .set({
        'photoUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ── Profiles ──────────────────────────────────────────────────────────────
  Future<String> createProfile(ProfileModel profile) async {
    final doc = _db.collection(AppConstants.profilesCollection).doc();
    final batch = _db.batch();
    // Public profile — note ProfileModel.toFirestore() no longer includes
    // contact details.
    batch.set(doc, profile.copyWith().toFirestore());
    // Contact details go into the access-gated `contacts/{userId}` collection
    // so they are never exposed by profile browsing.
    if (profile.userId.isNotEmpty &&
        (profile.contact.mobileNumber.isNotEmpty ||
            (profile.contact.whatsappNumber ?? '').isNotEmpty)) {
      batch.set(
        _db.collection(AppConstants.contactsCollection).doc(profile.userId),
        {
          ...profile.contact.toMap(),
          'userId': profile.userId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
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
    // These server-side filters MUST mirror the `profiles` security rule, which
    // only allows reading another user's profile when
    // status == 'approved' && isActive == true. Firestore rejects a query with
    // permission-denied unless its filters guarantee every matched document is
    // readable — so filtering by gender ALONE (the old behaviour) made the whole
    // Matches feed fail to load. All three are equality filters, so they need
    // only Firestore's automatic single-field indexes (NO composite index).
    // Remaining rules (self, married, age, city, …) are applied client-side in
    // DiscoverNotifier.
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('gender', isEqualTo: gender)
        .where('status', isEqualTo: 'approved')
        .where('isActive', isEqualTo: true)
        .limit(limit)
        .get();
    final list = snap.docs.map((d) => ProfileModel.fromFirestore(d)).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
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

  Future<InterestModel?> getInterestById(String interestId) async {
    final doc = await _db
        .collection(AppConstants.interestsCollection)
        .doc(interestId)
        .get();
    if (!doc.exists) return null;
    return InterestModel.fromFirestore(doc);
  }

  /// Accepts an interest, then records a `connections/{pair}` document so BOTH
  /// users can read each other's gated contact details.
  ///
  /// Two SEQUENTIAL writes (not a batch): Firestore security rules evaluate the
  /// connection-create against the *committed* interest, so the interest must
  /// already be 'accepted' before the connection is written.
  Future<void> acceptInterestAndConnect(InterestModel interest) async {
    await updateInterestStatus(interest.id, AppConstants.interestAccepted);
    final a = interest.senderId;
    final b = interest.receiverId;
    final pair = a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';
    await _db.collection(AppConstants.connectionsCollection).doc(pair).set({
      'uids': [a, b],
      'interestId': interest.id,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Contacts (gated phone / WhatsApp) ──────────────────────────────────────
  /// Reads a user's contact details. The Firestore rules only permit this when
  /// the caller is the owner, an admin, or has an accepted connection with the
  /// owner; otherwise a permission error is thrown (treated as "locked" by UI).
  Future<ContactDetails?> getContact(String userId) async {
    final doc = await _db
        .collection(AppConstants.contactsCollection)
        .doc(userId)
        .get();
    if (!doc.exists) return null;
    return ContactDetails.fromMap(doc.data()!);
  }

  /// Creates/updates the caller's own contact details.
  Future<void> saveContact(String userId, ContactDetails contact) => _db
      .collection(AppConstants.contactsCollection)
      .doc(userId)
      .set({
        ...contact.toMap(),
        'userId': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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

  /// Re-enables a suspended (blocked) user and reactivates their profile(s).
  Future<void> unblockUser(String userId) async {
    await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .update({'isBlocked': false});
    final profiles = await _db
        .collection(AppConstants.profilesCollection)
        .where('userId', isEqualTo: userId)
        .get();
    for (final doc in profiles.docs) {
      await doc.reference.update({'status': 'approved', 'isActive': true});
    }
  }

  /// Permanently deletes a user account document and any associated profile
  /// documents. (Chats / interests are left for a backend cleanup job.)
  Future<void> deleteUser(String userId) async {
    debugPrint('[Firestore] 🗑 deleteUser($userId)');
    final profiles = await _db
        .collection(AppConstants.profilesCollection)
        .where('userId', isEqualTo: userId)
        .get();
    final batch = _db.batch();
    for (final doc in profiles.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_db.collection(AppConstants.usersCollection).doc(userId));
    await batch.commit();
  }

  /// Recent platform events (newest first, max [limit]) for the Dashboard
  /// activity feed: new users, new astrologers, new subscriptions and new
  /// account-deletion requests. Each source is guarded independently.
  Future<List<AdminActivity>> getRecentActivity({int limit = 5}) async {
    final items = <AdminActivity>[];
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;

    try {
      final s = await _db
          .collection(AppConstants.usersCollection)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      for (final d in s.docs) {
        final m = d.data();
        items.add(AdminActivity(
          type: AdminActivityType.user,
          title: (m['displayName'] ?? m['email'] ?? 'New user').toString(),
          subtitle: 'New user registered',
          time: ts(m['createdAt']) ?? DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('[Activity] users failed: $e');
    }

    try {
      final s = await _db
          .collection(AppConstants.astrologersCollection)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      for (final d in s.docs) {
        final m = d.data();
        items.add(AdminActivity(
          type: AdminActivityType.astrologer,
          title: (m['fullName'] ?? 'New astrologer').toString(),
          subtitle: 'New astrologer registered',
          time: ts(m['createdAt']) ?? DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('[Activity] astrologers failed: $e');
    }

    try {
      final s = await _db
          .collection(AppConstants.subscriptionsCollection)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      for (final d in s.docs) {
        final m = d.data();
        final amount = (m['amountPaid'] is num) ? (m['amountPaid'] as num).toInt() : 0;
        items.add(AdminActivity(
          type: AdminActivityType.subscription,
          title: '${m['plan'] ?? 'Plan'} · ₹$amount',
          subtitle: 'New subscription purchased',
          time: ts(m['createdAt']) ?? DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('[Activity] subscriptions failed: $e');
    }

    try {
      final s = await _db
          .collection(AppConstants.accountDeletionRequestsCollection)
          .orderBy('requestDate', descending: true)
          .limit(limit)
          .get();
      for (final d in s.docs) {
        final m = d.data();
        items.add(AdminActivity(
          type: AdminActivityType.deletion,
          title: (m['userName'] ?? m['email'] ?? 'User').toString(),
          subtitle: 'New account deletion request',
          time: ts(m['requestDate']) ?? DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('[Activity] deletion requests failed: $e');
    }

    items.sort((a, b) => b.time.compareTo(a.time));
    return items.take(limit).toList();
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
    final married = await _db
        .collection(AppConstants.profilesCollection)
        .where('isMarried', isEqualTo: true)
        .count()
        .get();
    final pendingDeletions = await _db
        .collection(AppConstants.accountDeletionRequestsCollection)
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    final astrologers =
        await _db.collection(AppConstants.astrologersCollection).count().get();
    final consultations = await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .count()
        .get();

    return {
      'totalUsers': users.count,
      'totalProfiles': profiles.count,
      'pendingProfiles': pendingProfiles.count,
      'totalReports': reports.count,
      'marriedUsers': married.count,
      'pendingDeletions': pendingDeletions.count,
      'totalAstrologers': astrologers.count,
      'totalConsultations': consultations.count,
    };
  }

  /// Full business-dashboard analytics computed in one pass. Each section is
  /// guarded independently so a single failing query never blanks the whole
  /// dashboard — it just leaves that section at zero and logs the cause.
  Future<DashboardAnalytics> getDashboardAnalytics() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);
    final yearStart = DateTime(now.year, 1, 1);

    int toInt(dynamic v) => v is num ? v.toInt() : 0;
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;

    // ── Revenue + subscriptions (from `subscriptions`) ──────────────────────
    int revToday = 0, revWeek = 0, revMonth = 0, revYear = 0, revTotal = 0;
    int monthlySubs = 0, yearlySubs = 0;
    int activePremium = 0, expiredPremium = 0, cancelledSubs = 0;
    final daily = List<int>.filled(7, 0);
    final weekly = List<int>.filled(6, 0);
    final monthly = List<int>.filled(6, 0);
    final yearly = List<int>.filled(4, 0);
    try {
      final subs =
          await _db.collection(AppConstants.subscriptionsCollection).get();
      debugPrint('[Analytics] subscriptions: ${subs.docs.length}');
      for (final d in subs.docs) {
        final m = d.data();
        final amount = toInt(m['amountPaid']);
        revTotal += amount;
        final created = ts(m['createdAt']);
        final start = ts(m['startDate']);
        final end = ts(m['endDate']);
        final isActive = m['isActive'] ?? true;

        if (created != null) {
          if (!created.isBefore(todayStart)) revToday += amount;
          if (!created.isBefore(weekStart)) revWeek += amount;
          if (!created.isBefore(monthStart)) revMonth += amount;
          if (!created.isBefore(yearStart)) revYear += amount;

          final createdDay =
              DateTime(created.year, created.month, created.day);
          final dayDiff = todayStart.difference(createdDay).inDays;
          if (dayDiff >= 0 && dayDiff < 7) daily[6 - dayDiff] += amount;
          final weekDiff = dayDiff ~/ 7;
          if (weekDiff >= 0 && weekDiff < 6) weekly[5 - weekDiff] += amount;
          final monthDiff =
              (now.year - created.year) * 12 + (now.month - created.month);
          if (monthDiff >= 0 && monthDiff < 6) monthly[5 - monthDiff] += amount;
          final yearDiff = now.year - created.year;
          if (yearDiff >= 0 && yearDiff < 4) yearly[3 - yearDiff] += amount;
        }

        final expired = end != null && end.isBefore(now);
        if (expired) {
          expiredPremium++;
        } else if (isActive == true) {
          activePremium++;
        } else {
          cancelledSubs++;
        }
        if (start != null && end != null) {
          (end.difference(start).inDays >= 300 ? () => yearlySubs++ : () => monthlySubs++)();
        }
      }
    } catch (e) {
      debugPrint('[Analytics] ❌ subscriptions failed: $e');
    }

    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final revenueDaily = [
      for (var i = 0; i < 7; i++)
        RevenuePoint(
            wd[todayStart.subtract(Duration(days: 6 - i)).weekday - 1],
            daily[i]),
    ];
    final revenueWeekly = [
      for (var i = 0; i < 6; i++) RevenuePoint('W${i + 1}', weekly[i]),
    ];
    final revenueMonthly = [
      for (var i = 0; i < 6; i++)
        RevenuePoint(mo[DateTime(now.year, now.month - (5 - i), 1).month - 1],
            monthly[i]),
    ];
    final revenueYearly = [
      for (var i = 0; i < 4; i++)
        RevenuePoint('${now.year - (3 - i)}', yearly[i]),
    ];

    // ── Consultations (from `astrologer_requests`) ──────────────────────────
    int cToday = 0, cWeek = 0, cMonth = 0, cCompleted = 0, cCancelled = 0;
    final consultByAstro = <String, int>{};
    try {
      final reqs = await _db
          .collection(AppConstants.astrologerRequestsCollection)
          .get();
      for (final d in reqs.docs) {
        final m = d.data();
        final created = ts(m['createdAt']);
        final status = m['status'] ?? '';
        if (created != null) {
          if (!created.isBefore(todayStart)) cToday++;
          if (!created.isBefore(weekStart)) cWeek++;
          if (!created.isBefore(monthStart)) cMonth++;
        }
        if (status == 'completed') cCompleted++;
        if (status == 'rejected') cCancelled++;
        final aid = (m['astrologerId'] ?? '') as String;
        if (aid.isNotEmpty) {
          consultByAstro[aid] = (consultByAstro[aid] ?? 0) + 1;
        }
      }
    } catch (e) {
      debugPrint('[Analytics] ❌ consultations failed: $e');
    }

    // ── Astrologers (from `astrologers`) ────────────────────────────────────
    int totalAstro = 0, pendingAstro = 0, verifiedAstro = 0;
    var topRated = <AstrologerStatRow>[];
    var mostConsulted = <AstrologerStatRow>[];
    try {
      final astro =
          await _db.collection(AppConstants.astrologersCollection).get();
      totalAstro = astro.docs.length;
      final rows = <(String, AstrologerStatRow)>[];
      for (final d in astro.docs) {
        final m = d.data();
        final status = m['status'] ?? 'pending';
        if (status == 'approved') {
          verifiedAstro++;
        } else if (status == 'pending') {
          pendingAstro++;
        }
        final row = AstrologerStatRow(
          name: (m['fullName'] ?? '—') as String,
          rating: (m['rating'] ?? 0).toDouble(),
          reviewCount: toInt(m['reviewCount']),
          consultations: consultByAstro[d.id] ?? 0,
        );
        rows.add((d.id, row));
      }
      topRated = [...rows.map((e) => e.$2)]
        ..sort((a, b) => b.rating.compareTo(a.rating));
      topRated = topRated.take(5).toList();
      mostConsulted = [...rows.map((e) => e.$2)]
        ..sort((a, b) => b.consultations.compareTo(a.consultations));
      mostConsulted =
          mostConsulted.where((r) => r.consultations > 0).take(5).toList();
    } catch (e) {
      debugPrint('[Analytics] ❌ astrologers failed: $e');
    }

    // ── Counts (cheap aggregate queries) ────────────────────────────────────
    Future<int> countOf(Query q) async {
      try {
        return (await q.count().get()).count ?? 0;
      } catch (e) {
        debugPrint('[Analytics] ❌ count failed: $e');
        return 0;
      }
    }

    final users = _db.collection(AppConstants.usersCollection);
    final profiles = _db.collection(AppConstants.profilesCollection);
    final interests = _db.collection(AppConstants.interestsCollection);

    final totalUsers = await countOf(users);
    final newToday =
        await countOf(users.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart)));
    final newWeek =
        await countOf(users.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart)));
    final newMonth =
        await countOf(users.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart)));
    final dau = await countOf(
        users.where('lastLoginAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart)));
    final mau = await countOf(
        users.where('lastLoginAt', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart)));
    final totalProfiles = await countOf(profiles);
    final marriedUsers =
        await countOf(profiles.where('isMarried', isEqualTo: true));
    final matches =
        await countOf(interests.where('status', isEqualTo: AppConstants.interestAccepted));

    int totalMessages = 0;
    try {
      totalMessages = (await _db
                  .collectionGroup(AppConstants.messagesSubcollection)
                  .count()
                  .get())
              .count ??
          0;
    } catch (e) {
      debugPrint('[Analytics] ❌ messages count failed (needs index?): $e');
    }

    final marriageRate =
        totalProfiles > 0 ? (marriedUsers / totalProfiles) * 100 : 0.0;

    return DashboardAnalytics(
      totalUsers: totalUsers,
      totalAstrologers: totalAstro,
      totalMatches: matches,
      totalMessages: totalMessages,
      premiumSubscribers: activePremium,
      marriedUsers: marriedUsers,
      revenueToday: revToday,
      revenueWeek: revWeek,
      revenueMonth: revMonth,
      revenueYear: revYear,
      revenueTotal: revTotal,
      revenueDaily: revenueDaily,
      revenueWeekly: revenueWeekly,
      revenueMonthly: revenueMonthly,
      revenueYearly: revenueYearly,
      monthlySubscribers: monthlySubs,
      yearlySubscribers: yearlySubs,
      activePremium: activePremium,
      expiredPremium: expiredPremium,
      cancelledSubscriptions: cancelledSubs,
      newUsersToday: newToday,
      newUsersWeek: newWeek,
      newUsersMonth: newMonth,
      dailyActiveUsers: dau,
      monthlyActiveUsers: mau,
      pendingAstrologers: pendingAstro,
      verifiedAstrologers: verifiedAstro,
      topRatedAstrologers: topRated,
      mostConsultedAstrologers: mostConsulted,
      consultationsToday: cToday,
      consultationsWeek: cWeek,
      consultationsMonth: cMonth,
      consultationsCompleted: cCompleted,
      consultationsCancelled: cCancelled,
      successfulMatches: matches,
      marriageSuccessRate: marriageRate,
    );
  }

  // ── Marriage ───────────────────────────────────────────────────────────────
  /// Marks a profile as married → leaves active matchmaking (isActive false)
  /// while keeping the record and existing chats intact.
  Future<void> markProfileMarried(String profileId) =>
      _db.collection(AppConstants.profilesCollection).doc(profileId).update({
        'isMarried': true,
        'isActive': false,
        'marriedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<List<ProfileModel>> getMarriedProfiles({int limit = 100}) async {
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('isMarried', isEqualTo: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => ProfileModel.fromFirestore(d)).toList();
  }

  // ── Account deletion requests ──────────────────────────────────────────────
  Future<void> submitDeletionRequest(AccountDeletionRequest req) async {
    await _db
        .collection(AppConstants.accountDeletionRequestsCollection)
        .doc(req.id)
        .set(req.toFirestore());
    await _db.collection(AppConstants.usersCollection).doc(req.userId).update({
      'deletionRequested': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<AccountDeletionRequest>> getDeletionRequests() async {
    final snap = await _db
        .collection(AppConstants.accountDeletionRequestsCollection)
        .orderBy('requestDate', descending: true)
        .get();
    return snap.docs
        .map((d) => AccountDeletionRequest.fromFirestore(d))
        .toList();
  }

  /// Approve → permanently remove the user's Firestore data and mark the
  /// request approved. NOTE: deleting the Firebase Auth account itself requires
  /// the Admin SDK (a Cloud Function) triggered on this status flip.
  Future<void> approveDeletionRequest(AccountDeletionRequest req) async {
    final batch = _db.batch();
    final profiles = await _db
        .collection(AppConstants.profilesCollection)
        .where('userId', isEqualTo: req.userId)
        .get();
    for (final doc in profiles.docs) {
      batch.delete(doc.reference);
    }
    final sent = await _db
        .collection(AppConstants.interestsCollection)
        .where('senderId', isEqualTo: req.userId)
        .get();
    for (final doc in sent.docs) {
      batch.delete(doc.reference);
    }
    final received = await _db
        .collection(AppConstants.interestsCollection)
        .where('receiverId', isEqualTo: req.userId)
        .get();
    for (final doc in received.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_db.collection(AppConstants.usersCollection).doc(req.userId));
    batch.update(
      _db.collection(AppConstants.accountDeletionRequestsCollection).doc(req.id),
      {'status': 'approved', 'resolvedAt': FieldValue.serverTimestamp()},
    );
    await batch.commit();
  }

  Future<void> rejectDeletionRequest(String requestId, String userId) async {
    final batch = _db.batch();
    batch.update(
      _db
          .collection(AppConstants.accountDeletionRequestsCollection)
          .doc(requestId),
      {'status': 'rejected', 'resolvedAt': FieldValue.serverTimestamp()},
    );
    batch.update(
      _db.collection(AppConstants.usersCollection).doc(userId),
      {'deletionRequested': false, 'updatedAt': FieldValue.serverTimestamp()},
    );
    await batch.commit();
  }
}
