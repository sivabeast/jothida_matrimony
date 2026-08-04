import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../core/config/admin_config.dart';
import '../../core/services/firestore_sync.dart';
import '../../core/utils/login_identifier.dart';
import '../../models/aadhaar_details.dart';
import '../../models/blocked_entry.dart';
import '../../models/profile_model.dart';
import '../../models/interest_model.dart';
import '../../models/report_model.dart';
import '../../models/notification_model.dart';
import '../../models/announcement_model.dart';
import '../../models/banner_model.dart';
import '../../models/user_model.dart';
import '../../models/dashboard_analytics.dart';

/// A single page of search results plus the cursor for the next page.
typedef ProfilePage = ({
  List<ProfileModel> profiles,
  DocumentSnapshot<Map<String, dynamic>>? lastDoc,
  bool hasMore,
});

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Users ───────────────────────────────────────────────────────────────────
  /// Creates the user document on first login, or just refreshes `lastLoginAt`
  /// for a returning user — never creates a duplicate.
  ///
  /// Stored fields: uid (doc id), email, displayName (name), photoUrl,
  /// loginProvider, createdAt, lastLoginAt, isProfileComplete
  /// (profileCompleted), plus the app's account metadata.
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
            // A phone-only account signs in through a synthesized,
            // non-deliverable address — never store that as the member's
            // e-mail; the account simply has none until they add one.
            email: LoginIdentifier.isPhoneAuthEmail(user.email)
                ? null
                : user.email,
            phone: phone ?? user.phoneNumber,
            displayName: user.displayName,
            photoUrl: user.photoURL,
            loginProvider: loginProvider,
            // Auto-assign super_admin / dedicated-admin to whitelisted
            // accounts; everyone else defaults to 'user'.
            role: AdminConfig.roleForEmail(user.email),
            // A DEDICATED admin never onboards (§2) — flagging the account as
            // "complete" keeps the profile-completion gate from ever pointing
            // it at the wizard, so no matrimony profile is created for it.
            isProfileComplete: AdminConfig.isDedicatedAdminEmail(user.email),
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
          final existing = snap.data();
          final currentRole = existing?['role'];
          final isSuper = AdminConfig.isSuperAdminEmail(user.email);
          final isDedicated = AdminConfig.isDedicatedAdminEmail(user.email);
          final promoteSuperAdmin =
              isSuper && currentRole != AdminConfig.roleSuperAdmin;
          // A DEDICATED admin (§2) is pinned to the plain 'admin' role, which
          // the router uses to confine it to the Admin Dashboard.
          final promoteDedicated =
              isDedicated && currentRole != AdminConfig.roleAdmin;
          // The whitelist is the single source of truth: an account that still
          // holds a privileged role but is no longer whitelisted is demoted to
          // a normal user, so revoking access just means editing the whitelist.
          final demoteToUser = !isSuper &&
              !isDedicated &&
              (currentRole == AdminConfig.roleSuperAdmin ||
                  currentRole == AdminConfig.roleAdmin);
          if (promoteSuperAdmin) {
            debugPrint('[Firestore] ${user.uid}: promoting ${user.email} '
                '→ super_admin');
          }
          if (promoteDedicated) {
            debugPrint('[Firestore] ${user.uid}: pinning ${user.email} '
                '→ admin (dedicated admin account)');
          }
          if (demoteToUser) {
            debugPrint('[Firestore] ${user.uid}: ${user.email} no longer '
                'whitelisted → demoting to user');
          }
          txn.update(docRef, {
            'lastLoginAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            if (loginProvider != null) 'loginProvider': loginProvider,
            if (promoteSuperAdmin) 'role': AdminConfig.roleSuperAdmin,
            if (promoteDedicated) 'role': AdminConfig.roleAdmin,
            if (demoteToUser) 'role': AdminConfig.roleUser,
            // Keeps the dedicated admin out of the onboarding gate for good,
            // including accounts created before this rule existed.
            if (isDedicated) 'isProfileComplete': true,
          });
        }
      });
    } catch (e, st) {
      debugPrint('[Firestore] createOrUpdateUserOnLogin(${user.uid}) '
          'transaction FAILED: $e\n$st');
      rethrow;
    }

    debugPrint('[Firestore] ${user.uid}: transaction committed, re-reading doc...');

    // ── Employee role auto-detection ─────────────────────────────────────────
    // If this Gmail was provisioned by the admin as an employee (astrology_team
    // registry), flag the `astrologer` role on login (from ANY entry point) and
    // link the uid, so the router opens the Employee Portal and never the
    // matrimony pages. Super-admin accounts are excluded — admin and employee
    // stay separate.
    if (user.email != null && !AdminConfig.isPrivilegedEmail(user.email)) {
      try {
        final teamKey = user.email!.trim().toLowerCase();
        final teamRef = _db.collection('astrology_team').doc(teamKey);
        final teamDoc = await teamRef.get();
        if (teamDoc.exists && teamDoc.data()?['active'] != false) {
          await docRef.set({'role': 'astrologer'}, SetOptions(merge: true));
          await teamRef.set(
              {'uid': user.uid, 'lastLoginAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
          // Backfill the uid onto any requests assigned to this Gmail BEFORE the
          // astrologer's first login, so `astrologerId == uid` holds too.
          final assigned = await _db
              .collection('astrologer_requests')
              .where('astrologerEmail', isEqualTo: teamKey)
              .get();
          for (final d in assigned.docs) {
            if ((d.data()['astrologerUid'] ?? '').toString().isEmpty) {
              await d.reference.update(
                  {'astrologerId': user.uid, 'astrologerUid': user.uid});
            }
          }
        }
      } catch (e) {
        debugPrint('[Firestore] astrologer role auto-detect failed: $e');
      }
    }

    final fresh = await docRef.get();
    debugPrint('[Firestore] ${user.uid}: doc read OK '
        '(exists=${fresh.exists})');
    return UserModel.fromFirestore(fresh);
  }

  /// Saves the essential registration details collected on the Create Account
  /// form (name, mobile, gender, DOB, and optionally e-mail/location) onto
  /// `users/{uid}`.
  ///
  /// [email] is the member's REAL address. It is written only when non-empty so
  /// a phone-only account (whose Firebase credential uses a synthesized,
  /// non-deliverable address) never advertises that internal address as its
  /// contact e-mail, and an existing value is never blanked.
  Future<void> saveUserRegistrationDetails(
    String uid, {
    required String name,
    required String phone,
    required String gender,
    required DateTime dateOfBirth,
    String location = '',
    String email = '',
  }) =>
      _db.collection(AppConstants.usersCollection).doc(uid).set({
        'displayName': name,
        'phone': phone,
        'gender': gender,
        'dateOfBirth': Timestamp.fromDate(dateOfBirth),
        if (location.trim().isNotEmpty) 'location': location.trim(),
        if (email.trim().isNotEmpty) 'email': email.trim().toLowerCase(),
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

  /// Merges [data] into `users/{uid}`. Used for account-level settings that
  /// are mirrored from elsewhere (e.g. the privacy switches, whose source of
  /// truth is the public profile document).
  Future<void> updateUser(String uid, Map<String, dynamic> data) => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .set({...data, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));

  // (updateUserSubscription was removed — the app has NO subscription system;
  // all matrimony features are free and only per-booking astrology is paid.)

  // ── Profiles ──────────────────────────────────────────────────────────────
  Future<String> createProfile(ProfileModel profile) async {
    final doc = _db.collection(AppConstants.profilesCollection).doc();
    // 1) Save the public profile FIRST. ProfileModel.toFirestore() no longer
    //    includes contact details. This write succeeds under the standard
    //    profile-create rule, so onboarding can never be blocked by the
    //    separate contact write below.
    await doc.set(profile.copyWith().toFirestore());

    // 2) Store contact details in the access-gated `contacts/{userId}`
    //    collection. This is intentionally NON-FATAL: if the `contacts`
    //    security rule hasn't been deployed yet (firebase deploy --only
    //    firestore:rules), the write is denied — but the profile must still
    //    save, so we log and continue instead of failing the whole save.
    if (profile.userId.isNotEmpty &&
        (profile.contact.mobileNumber.isNotEmpty ||
            (profile.contact.whatsappNumber ?? '').isNotEmpty)) {
      try {
        await saveContact(profile.userId, profile.contact);
      } catch (e) {
        debugPrint('[FirestoreService] contact save skipped ($e). '
            'Deploy firestore.rules to enable the contacts collection.');
      }
    }
    return doc.id;
  }

  Future<void> updateProfile(String profileId, Map<String, dynamic> data) =>
      _db.collection(AppConstants.profilesCollection).doc(profileId).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ── Test data (dummy profiles) — spec §3 ──────────────────────────────────
  // The admin "Test Data" tool seeds realistic profiles for end-to-end testing
  // and removes them again afterwards. Each is written under its own stable id
  // (so re-seeding overwrites rather than duplicates) and force-tagged
  // `isDummy: true` so it can be filtered/bulk-deleted here or in the console.

  /// Write [profiles] to the `profiles` collection. Returns the number written.
  Future<int> seedDummyProfiles(List<ProfileModel> profiles) async {
    final col = _db.collection(AppConstants.profilesCollection);
    for (var i = 0; i < profiles.length; i += 400) {
      final batch = _db.batch();
      for (final p in profiles.skip(i).take(400)) {
        final map = p.toFirestore()..['isDummy'] = true;
        batch.set(col.doc(p.id), map);
      }
      await batch.commit();
    }
    return profiles.length;
  }

  /// How many dummy profiles currently exist (`isDummy == true`).
  Future<int> countDummyProfiles() async {
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('isDummy', isEqualTo: true)
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Delete EVERY dummy profile. Returns the number removed.
  Future<int> deleteDummyProfiles() async {
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('isDummy', isEqualTo: true)
        .get();
    var removed = 0;
    for (var i = 0; i < snap.docs.length; i += 400) {
      final batch = _db.batch();
      for (final d in snap.docs.skip(i).take(400)) {
        batch.delete(d.reference);
        removed++;
      }
      await batch.commit();
    }
    return removed;
  }

  Future<ProfileModel?> getProfile(String profileId) async {
    final doc = await _db.collection(AppConstants.profilesCollection).doc(profileId).get();
    if (!doc.exists) return null;
    return ProfileModel.fromFirestore(doc);
  }

  /// Admin moderation: permanently delete a reported profile document.
  Future<void> deleteProfileById(String profileId) =>
      _db.collection(AppConstants.profilesCollection).doc(profileId).delete();

  Future<ProfileModel?> getProfileByUserId(String userId) async {
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ProfileModel.fromFirestore(snap.docs.first);
  }

  /// LIVE stream of the signed-in user's OWN profile (query by userId). This
  /// is the admin↔user sync backbone: any edit the admin makes on the profile
  /// document (details, horoscope, photos, Aadhaar, preferences…) reaches the
  /// user app in real time — no re-login, no stale one-shot cache.
  Stream<ProfileModel?> watchProfileByUserId(String userId) => _db
      .collection(AppConstants.profilesCollection)
      .where('userId', isEqualTo: userId)
      .limit(1)
      .snapshots()
      .map((s) =>
          s.docs.isEmpty ? null : ProfileModel.fromFirestore(s.docs.first));

  /// Look up ANOTHER user's public profile by their UID.
  ///
  /// Unlike [getProfileByUserId] (used for the signed-in user's OWN profile,
  /// which the rule allows via the `userId == auth.uid` owner path), this MUST
  /// mirror the `profiles` read rule's public path — status == 'approved' &&
  /// isActive == true — because Firestore validates a query against its filter
  /// constraints, not its results. Filtering by userId alone would be rejected
  /// with permission-denied for anyone but the owner/admin. All three are
  /// equality filters, so only automatic single-field indexes are needed.
  Future<ProfileModel?> getApprovedProfileByUserId(String userId) async {
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'approved')
        .where('isActive', isEqualTo: true)
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
    int limit = 60,
  }) async {
    // These server-side filters MUST mirror the `profiles` security rule, which
    // only allows reading another user's profile when
    // status == 'approved' && isActive == true. Firestore rejects a query with
    // permission-denied unless its filters guarantee every matched document is
    // readable — so status + isActive are ALWAYS applied. Gender is optional:
    // pass an empty string to load EVERY approved profile (the Matches page shows
    // all members, no gender filter). All are equality filters, so they need only
    // Firestore's automatic single-field indexes (NO composite index). Remaining
    // rules (self, married, city, …) are applied client-side in DiscoverNotifier.
    Query<Map<String, dynamic>> query = _db
        .collection(AppConstants.profilesCollection)
        .where('status', isEqualTo: 'approved')
        .where('isActive', isEqualTo: true);
    if (gender.isNotEmpty) {
      query = query.where('gender', isEqualTo: gender);
    }
    final snap = await query.limit(limit).get();
    final list = snap.docs.map((d) => ProfileModel.fromFirestore(d)).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Cursor-paginated search ordered by `createdAt` DESC (newest first) — the
  /// query the Matches feed and Home "Recommended" section use:
  ///
  ///   where(status==approved) where(isActive==true) where(gender==X)
  ///   orderBy(createdAt, desc).startAfter(cursor).limit(n)
  ///
  /// This needs a composite index (see firestore.indexes.json). If that index
  /// is still building / missing, we fall back to a single unordered page so the
  /// feed degrades gracefully instead of erroring out.
  Future<ProfilePage> searchProfilesPage({
    required String gender,
    int limit = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> base = _db
        .collection(AppConstants.profilesCollection)
        .where('status', isEqualTo: 'approved')
        .where('isActive', isEqualTo: true);
    if (gender.isNotEmpty) {
      base = base.where('gender', isEqualTo: gender);
    }

    try {
      Query<Map<String, dynamic>> q = base.orderBy('createdAt', descending: true);
      if (startAfter != null) q = q.startAfterDocument(startAfter);
      final snap = await q.limit(limit).get();
      final profiles =
          snap.docs.map((d) => ProfileModel.fromFirestore(d)).toList();
      return (
        profiles: profiles,
        lastDoc: snap.docs.isEmpty ? null : snap.docs.last,
        hasMore: snap.docs.length == limit,
      );
    } on FirebaseException catch (e) {
      // Missing or still-building composite index → unordered fallback so the
      // feed isn't blanked. (One page only; no cursor.)
      if (e.code == 'failed-precondition') {
        debugPrint('[FirestoreService] searchProfilesPage index unavailable '
            '(${e.message}); falling back to unordered fetch.');
        final snap = await base.limit(limit).get();
        final profiles = snap.docs
            .map((d) => ProfileModel.fromFirestore(d))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return (profiles: profiles, lastDoc: null, hasMore: false);
      }
      rethrow;
    }
  }

  // Fail-safe: a non-owner viewing a profile bumps viewCount, but if the rule
  // (or deploy) disallows it we must NOT let that surface as a screen error.
  Future<void> incrementViewCount(String profileId) async {
    try {
      await _db
          .collection(AppConstants.profilesCollection)
          .doc(profileId)
          .update({'viewCount': FieldValue.increment(1)});
    } catch (e) {
      debugPrint('[FirestoreService] viewCount increment skipped: $e');
    }
  }

  // ── Interests ─────────────────────────────────────────────────────────────
  Future<void> sendInterest(InterestModel interest) => _db
      .collection(AppConstants.interestsCollection)
      .doc(interest.id)
      .set(interest.toFirestore());

  Future<void> updateInterestStatus(String interestId, String status) => _db
      .collection(AppConstants.interestsCollection)
      .doc(interestId)
      .update({'status': status, 'respondedAt': FieldValue.serverTimestamp()});

  /// Deletes an interest document — used by the sender to withdraw (unsend) a
  /// pending interest. Firestore rules permit either party to delete.
  Future<void> deleteInterest(String interestId) => _db
      .collection(AppConstants.interestsCollection)
      .doc(interestId)
      .delete();

  // NOTE: no server-side `orderBy` — combining a `where` equality with
  // `orderBy('sentAt')` on a different field requires a composite index, and
  // without it the stream throws `failed-precondition` and the Interests page
  // errors out. We sort by `sentAt` client-side instead so it always loads.
  Stream<List<InterestModel>> watchSentInterests(String userId) => _db
      .collection(AppConstants.interestsCollection)
      .where('senderId', isEqualTo: userId)
      .snapshots()
      .map((s) {
        final list = s.docs.map((d) => InterestModel.fromFirestore(d)).toList();
        list.sort((a, b) => b.sentAt.compareTo(a.sentAt));
        return list;
      });

  Stream<List<InterestModel>> watchReceivedInterests(String userId) => _db
      .collection(AppConstants.interestsCollection)
      .where('receiverId', isEqualTo: userId)
      .snapshots()
      .map((s) {
        final list = s.docs.map((d) => InterestModel.fromFirestore(d)).toList();
        list.sort((a, b) => b.sentAt.compareTo(a.sentAt));
        return list;
      });

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
    // Accepting the interest is the important part and must always succeed.
    await updateInterestStatus(interest.id, AppConstants.interestAccepted);
    await createConnection(interest);
  }

  /// Creates the `connections/{pair}` document that unlocks contact details for
  /// BOTH users of an accepted interest. Idempotent (merge) and NON-FATAL, so
  /// it doubles as a backfill for interests that were accepted before this
  /// existed (or before firestore.rules was deployed). Security rules only
  /// allow the write when the referenced interest is actually accepted.
  Future<void> createConnection(InterestModel interest) async {
    final a = interest.senderId;
    final b = interest.receiverId;
    final pair = a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';
    try {
      await _db.collection(AppConstants.connectionsCollection).doc(pair).set({
        'uids': [a, b],
        'interestId': interest.id,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[FirestoreService] connection write skipped ($e). '
          'Deploy firestore.rules to enable contact unlock.');
    }
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

  /// LIVE contact details for [userId] — the record written by the Contact
  /// Details step of profile creation and by every later edit.
  ///
  /// Streaming (rather than a one-shot read) is what makes the View Profile
  /// contact section update by itself the moment the owner edits their contact
  /// details, with no refresh and no second source of truth.
  Stream<ContactDetails?> watchContact(String userId) => FirestoreSync.docStream(
        _db.collection(AppConstants.contactsCollection).doc(userId),
        fromDoc: (d) => ContactDetails.fromMap(d.data() ?? const {}),
        label: 'contact',
      );

  /// Creates/updates the caller's own contact details.
  Future<void> saveContact(String userId, ContactDetails contact) => _db
      .collection(AppConstants.contactsCollection)
      .doc(userId)
      .set({
        ...contact.toMap(),
        'userId': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ── Aadhaar verification (gated aadhaar/{userId}) ─────────────────────────
  /// Saves/updates a user's Aadhaar record. A USER save always resets
  /// [verified] to false (the security rules enforce this too) — only an admin
  /// re-verifies after an edit.
  Future<void> saveAadhaar(AadhaarDetails details) => _db
      .collection(AppConstants.aadhaarCollection)
      .doc(details.userId)
      .set(details.toFirestore(), SetOptions(merge: true));

  /// Live Aadhaar record for [userId] (owner or admin — rules-gated).
  Stream<AadhaarDetails?> watchAadhaar(String userId) => _db
      .collection(AppConstants.aadhaarCollection)
      .doc(userId)
      .snapshots()
      .map((d) => d.exists ? AadhaarDetails.fromFirestore(d) : null);

  /// One-shot Aadhaar fetch (admin review / edit prefill).
  Future<AadhaarDetails?> getAadhaar(String userId) async {
    final d = await _db
        .collection(AppConstants.aadhaarCollection)
        .doc(userId)
        .get();
    return d.exists ? AadhaarDetails.fromFirestore(d) : null;
  }

  /// ADMIN action: marks the Aadhaar record verified/unverified and mirrors
  /// the outcome onto the profile's public `isVerified` badge.
  Future<void> setAadhaarVerified({
    required String userId,
    required String profileId,
    required bool verified,
  }) async {
    await _db.collection(AppConstants.aadhaarCollection).doc(userId).set({
      'verified': verified,
      'verifiedAt': verified ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (profileId.isNotEmpty) {
      await _db
          .collection(AppConstants.profilesCollection)
          .doc(profileId)
          .update({'isVerified': verified});
    }
  }

  // ── Reports ───────────────────────────────────────────────────────────────
  Future<void> submitReport(ReportModel report) async {
    await _db
        .collection(AppConstants.reportsCollection)
        .doc(report.id)
        .set(report.toFirestore());
    // Bump the reported profile's report count — only for profile reports that
    // reference a real profile (chat reports have no profile id, and the bump
    // is non-fatal so a denied/missing update never loses the report itself).
    if (report.reportedProfileId.trim().isNotEmpty) {
      try {
        await _db
            .collection(AppConstants.profilesCollection)
            .doc(report.reportedProfileId)
            .update({'reportCount': FieldValue.increment(1)});
      } catch (e) {
        debugPrint('[FirestoreService] reportCount bump skipped: $e');
      }
    }
  }

  /// All reports, newest first, for the admin Report Management page.
  Stream<List<ReportModel>> watchAllReports() => _db
      .collection(AppConstants.reportsCollection)
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map(ReportModel.fromFirestore).toList());

  /// Admin: change a report's moderation status (spec §8 actions). Keeps the
  /// legacy [isResolved] flag in sync so older screens still read correctly.
  Future<void> updateReportStatus(String reportId, String status,
      {String? adminNotes}) {
    final resolved =
        status == 'resolved' || status == 'rejected' || status == 'deleted';
    return _db.collection(AppConstants.reportsCollection).doc(reportId).update({
      'status': status,
      'isResolved': resolved,
      if (adminNotes != null) 'adminNotes': adminNotes,
      'resolvedAt': resolved ? FieldValue.serverTimestamp() : null,
    });
  }

  Future<void> deleteReport(String reportId) =>
      _db.collection(AppConstants.reportsCollection).doc(reportId).delete();

  /// Count of reports still awaiting review (status == 'pending') — drives the
  /// admin dashboard's "Pending Reports" badge.
  Future<int> countPendingReports() async {
    final snap = await _db
        .collection(AppConstants.reportsCollection)
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ── Blocks (user ↔ user, spec §6) ─────────────────────────────────────────
  // A block is one directional doc `blocks/{blocker}__{blocked}`. Matches /
  // search hide anyone in EITHER direction; interest & chat are refused too.

  String _blockId(String blocker, String blocked) => '${blocker}__$blocked';

  Future<void> blockUserId(String blockerUid, String blockedUid) => _db
      .collection(AppConstants.blocksCollection)
      .doc(_blockId(blockerUid, blockedUid))
      .set({
        'blockerUid': blockerUid,
        'blockedUid': blockedUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> unblockUserId(String blockerUid, String blockedUid) => _db
      .collection(AppConstants.blocksCollection)
      .doc(_blockId(blockerUid, blockedUid))
      .delete();

  /// UIDs the signed-in user has blocked.
  Stream<Set<String>> watchBlockedByMe(String myUid) => _db
      .collection(AppConstants.blocksCollection)
      .where('blockerUid', isEqualTo: myUid)
      .snapshots()
      .map((s) => s.docs.map((d) => d['blockedUid'] as String? ?? '').toSet()
        ..removeWhere((e) => e.isEmpty));

  /// UIDs that have blocked the signed-in user.
  Stream<Set<String>> watchWhoBlockedMe(String myUid) => _db
      .collection(AppConstants.blocksCollection)
      .where('blockedUid', isEqualTo: myUid)
      .snapshots()
      .map((s) => s.docs.map((d) => d['blockerUid'] as String? ?? '').toSet()
        ..removeWhere((e) => e.isEmpty));

  /// The signed-in user's blocks WITH the block date, newest first — for the
  /// user-facing Blocked Users page. (Distinct from [watchBlockedByMe], which
  /// returns just the id set used by the feed/search hide logic.)
  Stream<List<BlockedEntry>> watchMyBlocks(String myUid) => _db
      .collection(AppConstants.blocksCollection)
      .where('blockerUid', isEqualTo: myUid)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => BlockedEntry(
                  uid: (d['blockedUid'] as String?) ?? '',
                  blockedAt: (d['createdAt'] as Timestamp?)?.toDate(),
                ))
            .where((e) => e.uid.isNotEmpty)
            .toList();
        list.sort((a, b) => (b.blockedAt ?? DateTime(0))
            .compareTo(a.blockedAt ?? DateTime(0)));
        return list;
      });

  /// The signed-in user's OWN submitted reports (user-facing Reported Users
  /// page). No server `orderBy` (avoids a composite index); sorted client-side.
  /// Firestore rules must allow a user to read reports where
  /// `reporterUserId == request.auth.uid`.
  Stream<List<ReportModel>> watchMyReports(String reporterUid) => _db
      .collection(AppConstants.reportsCollection)
      .where('reporterUserId', isEqualTo: reporterUid)
      .snapshots()
      .map((s) {
        final list = s.docs.map(ReportModel.fromFirestore).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  // ── Notifications ─────────────────────────────────────────────────────────
  Future<void> saveNotification(NotificationModel notification) => _db
      .collection(AppConstants.notificationsCollection)
      .doc(notification.id)
      .set(notification.toFirestore());

  /// Creates an in-app notification for [userId]. Used by the client-side
  /// event hooks (interest sent/accepted/rejected, profile approved, report
  /// ready, appointment confirmed, admin profile update).
  ///
  /// When [id] is given the document id is DETERMINISTIC: one event can only
  /// ever produce one notification (duplicate writes become rules-denied
  /// updates and are swallowed by best-effort callers), and server-side
  /// cleanup (e.g. interest withdrawn) can delete it by the same id. The
  /// `notifications`-onCreate Cloud Function delivers the FCM push.
  Future<void> createNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
    String? id,
    String senderId = '',
    String targetScreen = '',
    String targetId = '',
  }) {
    final doc = <String, dynamic>{
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      if (data != null) 'data': data,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'senderId': senderId,
      'targetScreen': targetScreen,
      'targetId': targetId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final col = _db.collection(AppConstants.notificationsCollection);
    return id == null || id.isEmpty ? col.add(doc) : col.doc(id).set(doc);
  }

  /// Deletes a notification by its deterministic id — used when the event it
  /// announced was undone (e.g. a pending interest withdrawn). Best-effort at
  /// call sites; rules only allow the OWNER to delete, so the server-side
  /// `interests`-onDelete Cloud Function is the reliable cleanup path.
  Future<void> deleteNotificationById(String id) => _db
      .collection(AppConstants.notificationsCollection)
      .doc(id)
      .delete();

  /// Marks EVERY unread notification of [userId] read in one batch — called
  /// when the user opens the Notifications page, so the badge count drops to
  /// zero the moment the page is seen.
  Future<void> markAllNotificationsRead(String userId) async {
    final snap = await _db
        .collection(AppConstants.notificationsCollection)
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'isRead': true});
    }
    await batch.commit();
  }

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

  // ── Admin activity log ──────────────────────────────────────────────────────
  /// Records one admin action in the immutable `admin_logs` audit trail.
  /// Best-effort — an audit hiccup must never fail the action itself.
  Future<void> logAdminAction({
    required String adminUid,
    required String action,
    String targetUid = '',
    String targetProfileId = '',
    String details = '',
  }) async {
    try {
      await _db.collection(AppConstants.adminLogsCollection).add({
        'adminUid': adminUid,
        'action': action,
        'targetUid': targetUid,
        'targetProfileId': targetProfileId,
        'details': details,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Firestore] logAdminAction($action) failed (non-fatal): $e');
    }
  }

  /// Latest admin actions, newest first (admin-only per rules).
  Stream<List<Map<String, dynamic>>> watchAdminLogs({int limit = 200}) => _db
      .collection(AppConstants.adminLogsCollection)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [
            for (final d in s.docs) {'id': d.id, ...d.data()},
          ]);

  /// Cheap aggregate totals for the CRM dashboard — collections too large to
  /// stream whole (users beyond the 300-row admin list, all notifications).
  /// One count() read each; the dashboard refreshes them periodically.
  Future<({int totalUsers, int totalNotifications})>
      getAdminAggregateCounts() async {
    Future<int> countOf(String collection) async {
      try {
        final agg =
            await _db.collection(collection).count().get();
        return agg.count ?? 0;
      } catch (e) {
        debugPrint('[Firestore] count($collection) failed: $e');
        return 0;
      }
    }

    final users = await countOf(AppConstants.usersCollection);
    final notifications = await countOf(AppConstants.notificationsCollection);
    return (totalUsers: users, totalNotifications: notifications);
  }

  // ── Announcements (admin broadcast → all users & astrologers) ───────────────
  /// Live active announcements, newest first. Filters `isActive` only and sorts
  /// client-side (no composite index needed).
  Stream<List<AnnouncementModel>> watchAnnouncements() => _db
      .collection(AppConstants.announcementsCollection)
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map((s) {
        final list =
            s.docs.map(AnnouncementModel.fromFirestore).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  /// One announcement by id — live, null when deleted/missing. Backs the
  /// deep-linked `/announcement/:id` screen.
  Stream<AnnouncementModel?> watchAnnouncement(String id) => _db
      .collection(AppConstants.announcementsCollection)
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? AnnouncementModel.fromFirestore(d) : null);

  /// All announcements (any status) for the admin management screen.
  Stream<List<AnnouncementModel>> watchAllAnnouncements() => _db
      .collection(AppConstants.announcementsCollection)
      .snapshots()
      .map((s) {
        final list =
            s.docs.map(AnnouncementModel.fromFirestore).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  /// Creating an ACTIVE announcement also triggers the announcements-onCreate
  /// Cloud Function, which pushes it to the audience topic.
  Future<void> createAnnouncement({
    required String title,
    required String message,
    String audience = 'users',
    String type = 'general',
    String actionUrl = '',
    String actionLabel = '',
    String imageUrl = '',
    String priority = 'normal',
  }) =>
      _db.collection(AppConstants.announcementsCollection).add({
        'title': title,
        'message': message,
        'createdBy': 'admin',
        'isActive': true,
        'audience': audience,
        'type': type,
        'actionUrl': actionUrl,
        'actionLabel': actionLabel,
        'imageUrl': imageUrl,
        'priority': priority,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateAnnouncement(
    String id, {
    required String title,
    required String message,
    required bool isActive,
    String type = 'general',
    String actionUrl = '',
    String actionLabel = '',
    String imageUrl = '',
    String priority = 'normal',
  }) =>
      _db.collection(AppConstants.announcementsCollection).doc(id).update({
        'title': title,
        'message': message,
        'isActive': isActive,
        'type': type,
        'actionUrl': actionUrl,
        'actionLabel': actionLabel,
        'imageUrl': imageUrl,
        'priority': priority,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Sends one per-user notification to EVERY uid in [uids] in a single batch —
  /// the admin "Send to Selected Users / Employees" flow.
  Future<void> createNotificationsBatch({
    required List<String> uids,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    final batch = _db.batch();
    for (final uid in uids) {
      if (uid.trim().isEmpty) continue;
      batch.set(
          _db.collection(AppConstants.notificationsCollection).doc(), {
        'userId': uid,
        'title': title,
        'body': body,
        'type': type,
        if (data != null) 'data': data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> deleteAnnouncement(String id) => _db
      .collection(AppConstants.announcementsCollection)
      .doc(id)
      .delete();

  // ── Home banners (admin-managed carousel) ──────────────────────────────────
  /// PUBLISHED banners only (enabled == true), sorted by display order. Sorting
  /// is client-side so no composite index is required.
  Stream<List<HomeBannerModel>> watchActiveBanners() => _db
      .collection(AppConstants.bannersCollection)
      .where('enabled', isEqualTo: true)
      .snapshots()
      .map((s) {
        final list = s.docs.map(HomeBannerModel.fromFirestore).toList();
        list.sort((a, b) => a.order.compareTo(b.order));
        return list;
      });

  /// ALL banners (any status) for the admin management screen, by order.
  Stream<List<HomeBannerModel>> watchAllBanners() => _db
      .collection(AppConstants.bannersCollection)
      .snapshots()
      .map((s) {
        final list = s.docs.map(HomeBannerModel.fromFirestore).toList();
        list.sort((a, b) => a.order.compareTo(b.order));
        return list;
      });

  Future<void> createBanner(HomeBannerModel banner) => _db
      .collection(AppConstants.bannersCollection)
      .add(banner.toFirestore()
        ..['createdAt'] = FieldValue.serverTimestamp());

  Future<void> updateBanner(String id, Map<String, dynamic> fields) => _db
      .collection(AppConstants.bannersCollection)
      .doc(id)
      .update({...fields, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> deleteBanner(String id) =>
      _db.collection(AppConstants.bannersCollection).doc(id).delete();

  /// Swaps the display order of two banners atomically (Move Up / Move Down).
  Future<void> swapBannerOrder(
      String idA, int orderA, String idB, int orderB) async {
    final batch = _db.batch();
    final col = _db.collection(AppConstants.bannersCollection);
    batch.update(col.doc(idA), {'order': orderB});
    batch.update(col.doc(idB), {'order': orderA});
    await batch.commit();
  }

  // ── Admin ─────────────────────────────────────────────────────────────────
  Future<List<UserModel>> getAllUsers({int limit = 50}) async {
    // IMPORTANT: do NOT `orderBy('createdAt')` here. A Firestore orderBy
    // silently EXCLUDES any document that is missing the field (or has it as a
    // non-orderable type) — which made the admin Users list come back empty for
    // seeded / imported users that have no createdAt. Fetch unordered (returns
    // every doc the admin can read), parse each doc defensively so one bad
    // record can't blank the whole list, then sort newest-first client-side.
    final snap =
        await _db.collection(AppConstants.usersCollection).limit(limit).get();
    final users = <UserModel>[];
    for (final d in snap.docs) {
      try {
        final u = UserModel.fromFirestore(d);
        // MATRIMONY USERS ONLY: employee/astrologer and admin accounts are
        // managed in their own modules and must never appear in the Users
        // list. (Docs without a role parse as 'user', so legacy members are
        // kept.) Filtered client-side because a Firestore `where role ==`
        // would silently drop docs missing the field.
        if (u.role == 'user') users.add(u);
      } catch (e) {
        debugPrint('[getAllUsers] skipped malformed user ${d.id}: $e');
      }
    }
    users.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return users;
  }

  Future<List<ProfileModel>> getPendingProfiles() async {
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt')
        .get();
    return snap.docs.map((d) => ProfileModel.fromFirestore(d)).toList();
  }

  /// Every profile (newest first), for the admin Users management list — joined
  /// with the `users` docs to surface age / district / photo on each user card.
  /// Admins may read all profiles (see the `profiles` read rule), and a single
  /// `orderBy` needs no composite index.
  Future<List<ProfileModel>> getAllProfiles({int limit = 300}) async {
    // Unordered for the same reason as [getAllUsers] — an orderBy would drop
    // profiles missing createdAt. Parse defensively and sort client-side.
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .limit(limit)
        .get();
    final list = <ProfileModel>[];
    for (final d in snap.docs) {
      try {
        list.add(ProfileModel.fromFirestore(d));
      } catch (e) {
        debugPrint('[getAllProfiles] skipped malformed profile ${d.id}: $e');
      }
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ── Realtime admin lists (spec §1-3) ───────────────────────────────────────
  // Stream variants of the getAll* reads above, so the admin Users / Profiles
  // screens re-render the instant a record is added, edited or DELETED —
  // instead of showing a one-shot snapshot that goes stale until a manual
  // refresh. Defensive per-doc parsing + client-side sort are centralized in
  // [FirestoreSync.collectionStream].

  /// Realtime [getAllUsers] — matrimony users only, newest-first.
  Stream<List<UserModel>> watchAllUsers({int limit = 300}) =>
      FirestoreSync.collectionStream<UserModel>(
        _db.collection(AppConstants.usersCollection).limit(limit),
        fromDoc: UserModel.fromFirestore,
        where: (u) => u.role == 'user',
        sort: (a, b) => b.createdAt.compareTo(a.createdAt),
        label: 'allUsers',
      );

  /// Realtime [getAllProfiles] — every profile, newest-first. The limit
  /// bounds runaway reads while keeping the admin dashboard's profile stats
  /// accurate far beyond the visible list size.
  Stream<List<ProfileModel>> watchAllProfiles({int limit = 1000}) =>
      FirestoreSync.collectionStream<ProfileModel>(
        _db.collection(AppConstants.profilesCollection).limit(limit),
        fromDoc: ProfileModel.fromFirestore,
        sort: (a, b) => b.createdAt.compareTo(a.createdAt),
        label: 'allProfiles',
      );

  /// Realtime [getPendingProfiles] — oldest-first (FIFO moderation). Sorted
  /// client-side to avoid the where + orderBy composite index.
  Stream<List<ProfileModel>> watchPendingProfiles() =>
      FirestoreSync.collectionStream<ProfileModel>(
        _db
            .collection(AppConstants.profilesCollection)
            .where('status', isEqualTo: 'pending'),
        fromDoc: ProfileModel.fromFirestore,
        sort: (a, b) => a.createdAt.compareTo(b.createdAt),
        label: 'pendingProfiles',
      );

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
        // Remember the pre-suspension status so Activate can restore it —
        // unconditionally approving would silently skip the review queue for
        // a pending/rejected profile.
        final prior = (doc.data()['status'] ?? 'approved').toString();
        doc.reference.update({
          'status': 'blocked',
          'isActive': false,
          if (prior != 'blocked') 'statusBeforeBlock': prior,
        });
      }
    });
  }

  /// Re-enables a suspended (blocked) user and restores their profile(s) to
  /// the status they had BEFORE the suspension (legacy docs without the
  /// marker restore to 'approved', matching the old behaviour).
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
      final prior =
          (doc.data()['statusBeforeBlock'] ?? 'approved').toString();
      await doc.reference.update({
        'status': prior == 'blocked' ? 'approved' : prior,
        'isActive': true,
        'statusBeforeBlock': FieldValue.delete(),
      });
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

  // ── Self-service account deletion (immediate, no admin approval) ────────────

  /// Permanently deletes ALL Firestore data owned by a normal user: profile(s),
  /// interests (sent + received, any status), contact details, match
  /// connections, notifications, horoscope-report requests, Aadhaar
  /// verification, any stale deletion request, and finally the `users/{uid}`
  /// document. Each step is independently guarded so a single failure (e.g. a
  /// rules-blocked collection) can never abort the rest — the user document is
  /// always removed LAST so the account reads as "deleted" even if an earlier
  /// step was denied.
  ///
  /// Once `users/{uid}` is gone, the same Gmail signing in again lands on the
  /// "no existing doc → create new user (isProfileComplete=false)" branch of
  /// [createOrUpdateUserOnLogin], i.e. it is treated as a brand-new member and
  /// sent through Profile Creation.
  Future<void> deleteUserAccountData(String uid) async {
    debugPrint('[Firestore] 🗑 deleteUserAccountData($uid)');
    await _deleteWhere(AppConstants.profilesCollection, 'userId', uid);
    await _deleteWhere(AppConstants.interestsCollection, 'senderId', uid);
    await _deleteWhere(AppConstants.interestsCollection, 'receiverId', uid);
    await _deleteWhere(AppConstants.notificationsCollection, 'userId', uid);
    await _deleteWhere(
        AppConstants.accountDeletionRequestsCollection, 'userId', uid);
    // Horoscope-report / appointment bookings this member created. Owned by
    // them per the rules, so the delete is permitted.
    await _deleteWhere(
        AppConstants.astrologerRequestsCollection, 'userId', uid);
    await _deleteWhere(AppConstants.consultationsCollection, 'userId', uid);
    await _deleteArrayContains(
        AppConstants.connectionsCollection, 'uids', uid);
    await _deleteDocSafe(AppConstants.contactsCollection, uid);
    // Sensitive KYC record — must not outlive the account.
    await _deleteDocSafe(AppConstants.aadhaarCollection, uid);
    await _deleteDocSafe(AppConstants.usersCollection, uid);
  }

  /// Permanently deletes ALL Firestore data owned by an astrologer: their
  /// `astrologers/{uid}` account (services / certificates are embedded in that
  /// document), the `astrologers/{uid}/reviews` subcollection (Firestore does
  /// NOT cascade-delete subcollections, so it must be cleared explicitly), every
  /// `astrologer_requests` addressed to them, any stale deletion request, and
  /// the `users/{uid}` role document.
  Future<void> deleteAstrologerAccountData(String uid) async {
    debugPrint('[Firestore] 🗑 deleteAstrologerAccountData($uid)');
    await _deleteWhere(
        AppConstants.astrologerRequestsCollection, 'astrologerId', uid);
    // Reviews about this astrologer live in astrologers/{uid}/reviews.
    await _deleteSubcollection(
        AppConstants.astrologersCollection, uid,
        AppConstants.astrologerReviewsSubcollection);
    await _deleteWhere(
        AppConstants.accountDeletionRequestsCollection, 'userId', uid);
    await _deleteDocSafe(AppConstants.astrologersCollection, uid);
    await _deleteDocSafe(AppConstants.usersCollection, uid);
  }

  /// Deletes every document in the `{parentCollection}/{parentId}/{sub}`
  /// subcollection. Guarded so a failure (e.g. rules) can't abort the wider
  /// account-deletion sequence.
  Future<void> _deleteSubcollection(
      String parentCollection, String parentId, String sub) async {
    try {
      final snap = await _db
          .collection(parentCollection)
          .doc(parentId)
          .collection(sub)
          .get();
      await _deleteDocs(snap.docs);
    } catch (e) {
      debugPrint('[Firestore] deleteSubcollection('
          '$parentCollection/$parentId/$sub) skipped: $e');
    }
  }

  /// Deletes every document in [collection] where [field] == [value].
  Future<void> _deleteWhere(String collection, String field, String value) async {
    try {
      final snap =
          await _db.collection(collection).where(field, isEqualTo: value).get();
      await _deleteDocs(snap.docs);
    } catch (e) {
      debugPrint('[Firestore] deleteWhere($collection.$field==$value) skipped: $e');
    }
  }

  /// Deletes every document in [collection] whose [arrayField] contains [value].
  Future<void> _deleteArrayContains(
      String collection, String arrayField, String value) async {
    try {
      final snap = await _db
          .collection(collection)
          .where(arrayField, arrayContains: value)
          .get();
      await _deleteDocs(snap.docs);
    } catch (e) {
      debugPrint('[Firestore] deleteArrayContains($collection.$arrayField) skipped: $e');
    }
  }

  /// Commits deletes in chunks that stay under Firestore's 500-write batch cap.
  Future<void> _deleteDocs(List<QueryDocumentSnapshot> docs) async {
    const chunk = 450;
    for (var i = 0; i < docs.length; i += chunk) {
      final batch = _db.batch();
      for (final d in docs.skip(i).take(chunk)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  /// Deletes a single document, swallowing a missing-doc / permission error.
  Future<void> _deleteDocSafe(String collection, String id) async {
    try {
      await _db.collection(collection).doc(id).delete();
    } catch (e) {
      debugPrint('[Firestore] delete $collection/$id skipped: $e');
    }
  }

  Future<Map<String, dynamic>> getAdminStats() async {
    // "Total Users" counts MATRIMONY users only. Employee/astrologer and admin
    // accounts live in the users collection too (shared sign-in), so subtract
    // them from the raw count — docs with NO role field are legacy members and
    // must stay counted, which is why this isn't a `where role == 'user'`.
    final users = await _db.collection(AppConstants.usersCollection).count().get();
    var nonMemberAccounts = 0;
    for (final role in ['astrologer', 'admin', 'super_admin']) {
      try {
        nonMemberAccounts += (await _db
                    .collection(AppConstants.usersCollection)
                    .where('role', isEqualTo: role)
                    .count()
                    .get())
                .count ??
            0;
      } catch (e) {
        debugPrint('[AdminStats] role count($role) failed (→0): $e');
      }
    }
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
    final astrologers =
        await _db.collection(AppConstants.astrologersCollection).count().get();
    final consultations = await _db
        .collection(AppConstants.astrologerRequestsCollection)
        .count()
        .get();

    // ── Dashboard breakdowns ────────────────────────────────────────────────
    // Each guarded so a single denied/failed aggregate (e.g. an interests count
    // before the admin read rule is deployed) degrades to 0 instead of blanking
    // the whole dashboard.
    final usersCol = _db.collection(AppConstants.usersCollection);
    Future<int> safeCount(Query q) async {
      try {
        return (await q.count().get()).count ?? 0;
      } catch (e) {
        debugPrint('[AdminStats] count failed (→0): $e');
        return 0;
      }
    }

    final maleUsers = await safeCount(usersCol.where('gender', isEqualTo: 'Male'));
    final femaleUsers =
        await safeCount(usersCol.where('gender', isEqualTo: 'Female'));
    final blockedUsers =
        await safeCount(usersCol.where('isBlocked', isEqualTo: true));
    final totalInterests =
        await safeCount(_db.collection(AppConstants.interestsCollection));
    final totalMatches = await safeCount(_db
        .collection(AppConstants.interestsCollection)
        .where('status', isEqualTo: AppConstants.interestAccepted));

    final totalUsers =
        ((users.count ?? 0) - nonMemberAccounts).clamp(0, users.count ?? 0);

    return {
      'totalUsers': totalUsers,
      'totalProfiles': profiles.count,
      'pendingProfiles': pendingProfiles.count,
      'totalReports': reports.count,
      'marriedUsers': married.count,
      'totalAstrologers': astrologers.count,
      'totalConsultations': consultations.count,
      // Breakdowns for the mobile dashboard.
      'maleUsers': maleUsers,
      'femaleUsers': femaleUsers,
      'activeUsers': (totalUsers - blockedUsers).clamp(0, totalUsers),
      'totalInterests': totalInterests,
      'totalMatches': totalMatches,
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

    // ── Revenue ──────────────────────────────────────────────────────────────
    // The USER subscription system was removed — the legacy `subscriptions`
    // collection is no longer read; user-subscription revenue and premium
    // counts stay at 0. Only astrologer-plan and per-booking astrology-service
    // revenue is computed below.
    const int revToday = 0, revWeek = 0, revMonth = 0, revYear = 0,
        revTotal = 0;
    const int monthlySubs = 0, yearlySubs = 0;
    const int activePremium = 0, expiredPremium = 0, cancelledSubs = 0;
    const int usersExpiringToday = 0;
    // Astrologer subscription revenue (from `astrologers.subscriptionAmount`).
    int astroRevToday = 0, astroRevWeek = 0, astroRevMonth = 0,
        astroRevYear = 0, astroRevTotal = 0;
    // Subscription-expiry alerts (astrologer plans only now).
    final next7 = todayStart.add(const Duration(days: 7));
    int astrosExpiringToday = 0, expiring7 = 0;
    // Combined revenue-trend buckets (astrologer subs + paid services).
    final daily = List<int>.filled(7, 0);
    final weekly = List<int>.filled(6, 0);
    final monthly = List<int>.filled(6, 0);
    final yearly = List<int>.filled(4, 0);

    // ── Consultations (from `astrologer_requests`) ──────────────────────────
    int cToday = 0, cWeek = 0, cMonth = 0, cCompleted = 0, cCancelled = 0;
    // PAID astrology-service revenue (horoscope reports + appointments) — the
    // app's real per-service income now that all matrimony features are free.
    int svcRevToday = 0, svcRevWeek = 0, svcRevMonth = 0, svcRevYear = 0,
        svcRevTotal = 0;
    final consultByAstro = <String, int>{};
    // Completed-report count + consultation revenue per astrologer (leaderboard).
    final completedByAstro = <String, int>{};
    final revenueByAstro = <String, int>{};
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
        final amount = toInt(m['amount']);
        if (m['paid'] == true && amount > 0) {
          svcRevTotal += amount;
          final paidAt = ts(m['paidAt']) ?? created;
          if (paidAt != null) {
            if (!paidAt.isBefore(todayStart)) svcRevToday += amount;
            if (!paidAt.isBefore(weekStart)) svcRevWeek += amount;
            if (!paidAt.isBefore(monthStart)) svcRevMonth += amount;
            if (!paidAt.isBefore(yearStart)) svcRevYear += amount;
            // Feed the combined revenue-trend buckets (the buckets are meant to
            // combine astrologer subs + paid services — see their declaration).
            final paidDay = DateTime(paidAt.year, paidAt.month, paidAt.day);
            final dayDiff = todayStart.difference(paidDay).inDays;
            if (dayDiff >= 0 && dayDiff < 7) daily[6 - dayDiff] += amount;
            final weekDiff = dayDiff ~/ 7;
            if (weekDiff >= 0 && weekDiff < 6) weekly[5 - weekDiff] += amount;
            final monthDiff =
                (now.year - paidAt.year) * 12 + (now.month - paidAt.month);
            if (monthDiff >= 0 && monthDiff < 6) monthly[5 - monthDiff] += amount;
            final yearDiff = now.year - paidAt.year;
            if (yearDiff >= 0 && yearDiff < 4) yearly[3 - yearDiff] += amount;
          }
        }
        final aid = (m['astrologerId'] ?? '') as String;
        if (status == 'completed') {
          cCompleted++;
          if (aid.isNotEmpty) {
            completedByAstro[aid] = (completedByAstro[aid] ?? 0) + 1;
            revenueByAstro[aid] =
                (revenueByAstro[aid] ?? 0) + toInt(m['amount']);
          }
        }
        if (status == 'rejected') cCancelled++;
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
    // id → display info for the Top-Performers leaderboard.
    final astroInfo = <String, ({String name, String photoUrl, double rating})>{};
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

        // Astrologer subscription revenue (free/no-plan docs have amount 0).
        final subAmt = toInt(m['subscriptionAmount']);
        if (subAmt > 0) {
          astroRevTotal += subAmt;
          final act = ts(m['activatedAt']);
          if (act != null) {
            if (!act.isBefore(todayStart)) astroRevToday += subAmt;
            if (!act.isBefore(weekStart)) astroRevWeek += subAmt;
            if (!act.isBefore(monthStart)) astroRevMonth += subAmt;
            if (!act.isBefore(yearStart)) astroRevYear += subAmt;
            final actDay = DateTime(act.year, act.month, act.day);
            final dayDiff = todayStart.difference(actDay).inDays;
            if (dayDiff >= 0 && dayDiff < 7) daily[6 - dayDiff] += subAmt;
            final weekDiff = dayDiff ~/ 7;
            if (weekDiff >= 0 && weekDiff < 6) weekly[5 - weekDiff] += subAmt;
            final monthDiff =
                (now.year - act.year) * 12 + (now.month - act.month);
            if (monthDiff >= 0 && monthDiff < 6) monthly[5 - monthDiff] += subAmt;
            final yearDiff = now.year - act.year;
            if (yearDiff >= 0 && yearDiff < 4) yearly[3 - yearDiff] += subAmt;
          }
        }
        // Astrologer subscription expiry.
        final aexp = ts(m['subscriptionExpiry']);
        if (aexp != null && !aexp.isBefore(todayStart)) {
          final expDay = DateTime(aexp.year, aexp.month, aexp.day);
          if (expDay == todayStart) astrosExpiringToday++;
          if (aexp.isBefore(next7)) expiring7++;
        }

        astroInfo[d.id] = (
          name: (m['fullName'] ?? '—') as String,
          photoUrl: (m['photoUrl'] ?? '') as String,
          rating: (m['rating'] ?? 0).toDouble(),
        );
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

    // ── Revenue trend (combined user + astrologer, built after both passes) ──
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

    // ── Top performing astrologers (by completed reports, then revenue) ──────
    final topPerformers = <TopAstrologerRow>[
      for (final e in completedByAstro.entries)
        TopAstrologerRow(
          name: astroInfo[e.key]?.name ?? '—',
          photoUrl: astroInfo[e.key]?.photoUrl ?? '',
          completedReports: e.value,
          revenueGenerated: revenueByAstro[e.key] ?? 0,
          rating: astroInfo[e.key]?.rating ?? 0,
        ),
    ]..sort((a, b) {
        final c = b.completedReports.compareTo(a.completedReports);
        return c != 0 ? c : b.revenueGenerated.compareTo(a.revenueGenerated);
      });
    final topPerformersList = topPerformers.take(5).toList();

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
      // Combined revenue = user subs + astrologer subs + PAID astrology
      // services (horoscope reports & appointments).
      revenueToday: revToday + astroRevToday + svcRevToday,
      revenueWeek: revWeek + astroRevWeek + svcRevWeek,
      revenueMonth: revMonth + astroRevMonth + svcRevMonth,
      revenueYear: revYear + astroRevYear + svcRevYear,
      revenueTotal: revTotal + astroRevTotal + svcRevTotal,
      revenueDaily: revenueDaily,
      revenueWeekly: revenueWeekly,
      revenueMonthly: revenueMonthly,
      revenueYearly: revenueYearly,
      userRevenueToday: revToday,
      userRevenueMonth: revMonth,
      userRevenueTotal: revTotal,
      astroRevenueToday: astroRevToday,
      astroRevenueMonth: astroRevMonth,
      astroRevenueTotal: astroRevTotal,
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
      topPerformers: topPerformersList,
      usersExpiringToday: usersExpiringToday,
      astrologersExpiringToday: astrosExpiringToday,
      expiringNext7Days: expiring7,
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
  /// while keeping the record and existing chats intact. [via] records how the
  /// partner was found ('app' | 'other') from the confirmation flow.
  Future<void> markProfileMarried(String profileId, {String? via}) =>
      _db.collection(AppConstants.profilesCollection).doc(profileId).update({
        'isMarried': true,
        'isActive': false,
        if (via != null && via.isNotEmpty) 'marriedVia': via,
        'marriedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// UNDO for [markProfileMarried]: returns the profile to matchmaking (an
  /// accidental confirmation, or the plans changed). Clears the married
  /// stamps so the profile is exactly as before.
  Future<void> unmarkProfileMarried(String profileId) =>
      _db.collection(AppConstants.profilesCollection).doc(profileId).update({
        'isMarried': false,
        'isActive': true,
        'marriedVia': FieldValue.delete(),
        'marriedAt': FieldValue.delete(),
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

}
