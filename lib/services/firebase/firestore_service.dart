import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../core/config/admin_config.dart';
import '../../core/services/firestore_sync.dart';
import '../../core/utils/login_identifier.dart';
import '../../core/utils/matrimony_photo.dart';
import '../../core/utils/profile_privacy.dart';
import '../../models/aadhaar_details.dart';
import '../../models/blocked_entry.dart';
import '../../models/profile_model.dart';
import '../../models/interest_model.dart';
import '../../models/report_model.dart';
import '../../models/notification_model.dart';
import '../../models/announcement_model.dart';
import '../../models/app_popup_model.dart';
import '../../models/app_update_config.dart';
import '../../models/banner_model.dart';
import '../../models/user_model.dart';
import '../../models/dashboard_analytics.dart';
import 'login_directory_service.dart';

/// Outcome of [FirestoreService.reconcileMemberPrivacy] for one member.
class MemberPrivacyRepair {
  final bool changed;
  final bool recoveredPhoto;
  final bool skipped;
  const MemberPrivacyRepair({required this.changed, required this.recoveredPhoto})
      : skipped = false;
  const MemberPrivacyRepair.skipped()
      : changed = false,
        recoveredPhoto = false,
        skipped = true;
}

/// Totals of the admin "Repair privacy & photos" action.
class PrivacyRepairSummary {
  final int total;
  final int changed;
  final int recoveredPhotos;
  final int skipped;
  final int failed;
  const PrivacyRepairSummary({
    required this.total,
    required this.changed,
    required this.recoveredPhotos,
    required this.skipped,
    required this.failed,
  });
}

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
            // Deliberately NOT `user.photoURL`. `photoUrl` is the denormalized
            // mirror of the member's MATRIMONY profile photo (§6/§17); seeding
            // it from the identity provider made a Google account picture show
            // up as a matrimony photo on Home, match cards and the admin view.
            // It stays null until the member uploads their own image.
            photoUrl: null,
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
  /// Creates the member's profile document — or REPLACES the one they already
  /// have, so an account can never end up owning two (spec §4/§23).
  ///
  /// The reuse matters most in exactly the case that used to break: an account
  /// is deleted, the auth record survives the delete (`requires-recent-login`,
  /// a refused re-authentication) so the same uid signs in again, and the
  /// member creates a "new" profile. Writing a fresh document there would leave
  /// the DELETED profile sitting in the collection under the same uid, free to
  /// be served instead of the new one. Reusing the existing document id means
  /// the new profile OVERWRITES the old data rather than living beside it.
  ///
  /// Any further stale documents found under the uid are removed in the same
  /// pass, so the invariant is restored rather than merely avoided.
  Future<String> createProfile(ProfileModel profile) async {
    final existing = await _profileDocsFor(profile.userId);
    final doc = existing.isEmpty
        ? _db.collection(AppConstants.profilesCollection).doc()
        : existing.first.reference;
    if (existing.length > 1) {
      debugPrint('[Firestore] createProfile: ${existing.length} existing '
          'profiles for userId=${profile.userId} — reusing ${doc.id} and '
          'deleting the rest.');
      await _deleteDocs(existing.skip(1).toList());
    }
    // 1) Save the profile FIRST. ProfileModel.toFirestore() no longer includes
    //    contact details, so onboarding can never be blocked by the separate
    //    contact write below.
    //
    //    The fields the member chose to hide are split off (see
    //    core/utils/profile_privacy.dart): their real values go to
    //    `profile_private/{uid}` and the member-readable document carries a
    //    blank for each. Both halves are ONE batch, so a hidden value can never
    //    be blanked without its private copy landing too.
    //
    //    `set` WITHOUT merge is deliberate when an id is being reused: the new
    //    profile must replace the old document wholesale, never inherit stray
    //    fields from whoever filled it in before.
    final data = profile.copyWith().toFirestore();
    var written = false;
    if (await _useSplitWrites(profile.userId,
        hidesSomething: _hidesAnyProfileField(profile.privacySettings))) {
      final split = splitProfileWrite(data, profile.privacySettings);
      final batch = _db.batch()
        ..set(doc, split.public)
        ..set(_privateProfileRef(profile.userId), {
          ...privateSnapshotOf(data),
          'userId': profile.userId,
          'profileId': doc.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      written = await _commitPrivacyBatch(batch, uid: profile.userId);
    }
    if (!written) {
      // The private collection is not usable (rules not deployed). Keep the
      // previous behaviour — the full profile on one document — rather than
      // lose a value; the next reconcile moves it once the rules are live.
      await doc.set(data);
    }
    debugPrint('[Firestore] createProfile: profiles/${doc.id} written for '
        'userId=${profile.userId} (profilePhotoUrl='
        '${(profile.profilePhotoUrl ?? '').isEmpty ? 'none' : 'set'}, '
        'privateCopy=$written)');

    // 2) Store contact details in the access-gated `contacts/{userId}`
    //    collection. This is intentionally NON-FATAL: if the `contacts`
    //    security rule hasn't been deployed yet (firebase deploy --only
    //    firestore:rules), the write is denied — but the profile must still
    //    save, so we log and continue instead of failing the whole save.
    //
    //    Written even with NO contact values: the record also carries the
    //    `profileId` pointer the security rules use to find this member's
    //    Public/Private contact-sharing choice (a uid alone cannot locate a
    //    profile document from inside a rule).
    if (profile.userId.isNotEmpty) {
      try {
        await saveContact(profile.userId, profile.contact,
            profileId: doc.id,
            hidePhone: profile.hidesPhone);
      } catch (e) {
        debugPrint('[FirestoreService] contact save skipped ($e). '
            'Deploy firestore.rules to enable the contacts collection.');
      }
    }
    return doc.id;
  }

  // ── Field privacy (server-side) ─────────────────────────────────────────────
  //
  // See core/utils/profile_privacy.dart for the model. In short: a hidden
  // photo / salary / horoscope / phone number is stored ONLY in a private
  // document the viewer cannot read, so a member cannot get it back out of the
  // API by skipping the screen that hides it.

  DocumentReference<Map<String, dynamic>> _privateProfileRef(String uid) =>
      _db.collection(AppConstants.profilePrivateCollection).doc(uid);

  DocumentReference<Map<String, dynamic>> _privateContactRef(String uid) =>
      _db.collection(AppConstants.contactPrivateCollection).doc(uid);

  /// Whether `profile_private` / `contact_private` can be used for [uid] —
  /// i.e. the firestore.rules that allow them are deployed. Remembered for the
  /// session once known.
  ///
  /// WHY THIS EXISTS (a photo URL could be lost): every write that touches a
  /// hideable field used to be ATTEMPTED as a private-copy batch and fall back
  /// to the plain write only when the server answered `permission-denied`. That
  /// answer is not instant, and the batch went through `commitWrite`, which
  /// treats "no server answer within 10 s" as success-queued-offline. On a slow
  /// connection — typically right after a photo upload — the refusal arrived
  /// AFTER the timeout: the app counted the save as done, the fallback never
  /// ran, the server then rolled the whole batch back, and the new
  /// `profilePhotoUrl` never reached Firestore although the image was already
  /// in Cloudinary. Asking first, with a READ that has no side effects, removes
  /// that race: a write is only ever sent in a shape the rules accept.
  final Map<String, bool> _privateStorageReady = {};

  Future<bool?> _privateStorageAvailable(String uid) async {
    final known = _privateStorageReady[uid];
    if (known != null) return known;
    try {
      await _privateProfileRef(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      return _privateStorageReady[uid] = true; // readable ⇒ rules deployed
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('[FirestoreService] profile_private is not readable '
            '(firestore.rules not deployed?) — using single-document writes.');
        return _privateStorageReady[uid] = false;
      }
      debugPrint('[FirestoreService] private storage check for $uid '
          'inconclusive (${e.code}).');
      return null;
    } catch (e) {
      debugPrint('[FirestoreService] private storage check for $uid '
          'inconclusive ($e).');
      return null; // offline / timed out — unknown, not remembered
    }
  }

  /// Whether a write for [uid] should use the private-copy split. Only when
  /// the private collections are known to work — or, when that cannot be told
  /// right now (offline), when the write carries a HIDDEN value, because
  /// writing that onto the member-readable document would expose it.
  Future<bool> _useSplitWrites(String uid, {required bool hidesSomething}) async {
    if (uid.trim().isEmpty) return false;
    final available = await _privateStorageAvailable(uid);
    return available ?? hidesSomething;
  }

  static bool _hidesAnyProfileField(Map<String, bool> privacy) =>
      ProfilePrivacy.isHidden(privacy, ProfilePrivacy.photo) ||
      ProfilePrivacy.isHidden(privacy, ProfilePrivacy.salary) ||
      ProfilePrivacy.isHidden(privacy, ProfilePrivacy.horoscope);

  /// Commits a batch that writes a private document. Returns false — instead
  /// of throwing — when the private collections are refused anyway, so the
  /// caller falls back to the single-document write without losing anything.
  ///
  /// A batch is atomic: when it is refused, NOTHING in it was applied, so the
  /// public document was not blanked either.
  Future<bool> _commitPrivacyBatch(WriteBatch batch, {String uid = ''}) async {
    try {
      await commitWrite(batch.commit(), timeout: const Duration(seconds: 20));
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('[FirestoreService] private field storage refused '
            '(${e.message}). Deploy firestore.rules — falling back to the '
            'single-document write.');
        if (uid.isNotEmpty) _privateStorageReady[uid] = false;
        return false;
      }
      rethrow;
    }
  }

  /// The private half of a profile, or null when it does not exist yet or the
  /// caller may not read it.
  Future<Map<String, dynamic>?> _readPrivateProfile(String uid) async {
    if (uid.trim().isEmpty) return null;
    try {
      final snap = await _privateProfileRef(uid).get();
      _privateStorageReady[uid] = true;
      return snap.exists ? snap.data() : null;
    } on FirebaseException catch (e) {
      debugPrint('[FirestoreService] profile_private/$uid unreadable: '
          '${e.code}');
      if (e.code == 'permission-denied') _privateStorageReady[uid] = false;
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readPrivateContact(String uid) async {
    if (uid.trim().isEmpty) return null;
    try {
      final snap = await _privateContactRef(uid).get();
      return snap.exists ? snap.data() : null;
    } on FirebaseException catch (e) {
      debugPrint('[FirestoreService] contact_private/$uid unreadable: '
          '${e.code}');
      return null;
    }
  }

  /// Every hideable value in a write must be a plain value for the projection
  /// to reason about it — a FieldValue sentinel (arrayUnion, delete…) cannot be
  /// copied into a snapshot. No caller does that today; this keeps a future one
  /// on the old path rather than corrupting data.
  static bool _hasSentinelInPrivateFields(Map<String, dynamic> data) =>
      data.entries.any((e) {
        final top = e.key.split('.').first;
        return (HiddenProfileField.privateKeys.contains(top) ||
                top == 'privacySettings') &&
            e.value is FieldValue;
      });

  /// Every profile document currently stored under [userId], newest first.
  ///
  /// Owner-scoped (`userId == request.auth.uid`) or admin, which is exactly who
  /// calls it. Returns empty — never throws — when the query is not permitted,
  /// so a create is never blocked by a lookup that was only there to keep the
  /// collection tidy.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _profileDocsFor(
      String userId) async {
    if (userId.trim().isEmpty) return const [];
    try {
      final snap = await _db
          .collection(AppConstants.profilesCollection)
          .where('userId', isEqualTo: userId)
          .get();
      final docs = snap.docs.toList()
        ..sort((a, b) => _createdAtOf(b).compareTo(_createdAtOf(a)));
      return docs;
    } catch (e) {
      debugPrint('[Firestore] existing-profile lookup for $userId '
          'skipped (non-fatal): $e');
      return const [];
    }
  }

  static DateTime _createdAtOf(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final v = d.data()['createdAt'];
    if (v is Timestamp) return v.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Updates a profile, keeping hidden fields out of the member-readable
  /// document.
  ///
  /// A write that touches no hideable field (and not the privacy switches) is
  /// the plain update it always was. Anything else is resolved against the
  /// member's FULL data — public document plus private copy — so a partial
  /// write (one horoscope key, say) can never leave the private copy holding a
  /// fragment, and a switch change re-projects every hideable field at once.
  Future<void> updateProfile(String profileId, Map<String, dynamic> data) async {
    final ref = _db.collection(AppConstants.profilesCollection).doc(profileId);
    // Bounded: with offline persistence a raw `update` only completes on a
    // SERVER acknowledgement, which is what left a photo save spinning forever
    // on a bad connection. A write still pending after the timeout is already
    // in the local cache (and on screen) and syncs by itself; a real refusal
    // still throws.
    Future<void> plainUpdate() => commitWrite(
        ref.update({...data, 'updatedAt': FieldValue.serverTimestamp()}),
        timeout: const Duration(seconds: 20));

    if (!touchesPrivateProfileFields(data) ||
        _hasSentinelInPrivateFields(data)) {
      await plainUpdate();
      if (data.containsKey('contactPrivacy')) {
        await _ensureContactPointerFor(profileId);
      }
      return;
    }

    final snap = await ref.get();
    final publicData = snap.data();
    final uid = '${publicData?['userId'] ?? ''}'.trim();
    if (publicData == null || uid.isEmpty) {
      await plainUpdate(); // surfaces not-found exactly as before
      return;
    }

    final privateData = await _readPrivateProfile(uid);
    final truth = applyProfileWrite(
        mergePrivateProfileData(publicData, privateData), data);
    final privacy = ProfilePrivacy.fromMap(truth['privacySettings']);
    if (!await _useSplitWrites(uid,
        hidesSomething: _hidesAnyProfileField(privacy))) {
      await plainUpdate();
      if (data.containsKey('privacySettings')) {
        await _reprojectContact(uid,
            profileId: profileId,
            hidePhone: ProfilePrivacy.isHidden(privacy, ProfilePrivacy.phone));
      }
      return;
    }

    // Hideable fields come from the projection (real value or blank); the
    // legacy photo arrays pass through as written — the projection overrides
    // them with a blank only while the photo is hidden.
    final publicPatch = <String, dynamic>{
      for (final e in data.entries)
        if (!HiddenProfileField.privateKeys.contains(e.key.split('.').first))
          e.key: e.value,
      ...projectPublicPrivateFields(truth, privacy),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = _db.batch()
      ..update(ref, publicPatch)
      ..set(_privateProfileRef(uid), {
        ...privateSnapshotOf(truth),
        'userId': uid,
        'profileId': profileId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    if (!await _commitPrivacyBatch(batch, uid: uid)) {
      await plainUpdate();
      return;
    }

    // A change to "Hide Phone Number" moves the numbers too.
    if (data.containsKey('privacySettings')) {
      await _reprojectContact(uid,
          profileId: profileId,
          hidePhone: ProfilePrivacy.isHidden(privacy, ProfilePrivacy.phone));
    }
  }

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
        .get();
    return newestProfileOf(snap.docs);
  }

  /// LIVE stream of the signed-in user's OWN profile (query by userId). This
  /// is the admin↔user sync backbone: any edit the admin makes on the profile
  /// document (details, horoscope, photos, Aadhaar, preferences…) reaches the
  /// user app in real time — no re-login, no stale one-shot cache.
  ///
  /// NOTE THE MISSING `.limit(1)` — removing it is a correctness fix, not an
  /// oversight (spec §4/§23).
  ///
  /// An account is supposed to own exactly one profile, and [createProfile]
  /// now enforces that. But a uid CAN come back to a collection that still
  /// holds an older document under it: the obvious way is deleting the account
  /// and signing in again before every delete has landed — Firebase reuses the
  /// uid whenever the auth record itself survived (`requires-recent-login`, a
  /// cancelled re-auth), so the new profile lands beside the old one.
  ///
  /// `limit(1)` on an UNORDERED query is then actively dangerous: Firestore is
  /// free to return either document, and what it actually returns is the first
  /// by document id — which has nothing to do with which profile is current.
  /// That is precisely the "I deleted my account, made a new profile, and the
  /// OLD one came back" report. Reading every match and taking the NEWEST by
  /// `createdAt` makes the answer deterministic and always the live profile.
  /// The query is still one equality filter on a single-field index, and an
  /// account has one or two documents, so this costs nothing.
  Stream<ProfileModel?> watchProfileByUserId(String userId) => _db
      .collection(AppConstants.profilesCollection)
      .where('userId', isEqualTo: userId)
      .snapshots()
      .map((s) => newestProfileOf(s.docs));

  /// The CURRENT profile among [docs]: the most recently created one.
  ///
  /// Ties (equal or missing `createdAt`) fall back to the most recently
  /// updated, then to the document id, so the choice is always stable rather
  /// than dependent on result ordering.
  static ProfileModel? newestProfileOf(
          List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      newestProfile(docs.map(ProfileModel.fromFirestore).toList());

  /// The selection rule itself, over already-parsed profiles — pure, so the
  /// "the newest profile always wins" contract is testable without Firestore.
  @visibleForTesting
  static ProfileModel? newestProfile(List<ProfileModel> profiles) {
    if (profiles.isEmpty) return null;
    if (profiles.length == 1) return profiles.first;
    final sorted = [...profiles]..sort((a, b) {
        final byCreated = b.createdAt.compareTo(a.createdAt);
        if (byCreated != 0) return byCreated;
        final byUpdated = b.updatedAt.compareTo(a.updatedAt);
        if (byUpdated != 0) return byUpdated;
        return b.id.compareTo(a.id);
      });
    debugPrint('[Firestore] ⚠ ${sorted.length} profiles found for '
        'userId=${sorted.first.userId} — serving the newest '
        '(${sorted.first.id}). The others are stale and should be removed.');
    return sorted.first;
  }

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

  /// LIVE [getApprovedProfileByUserId] — same rule-mirroring filters. Served
  /// from the local cache first, so re-opening a row is instant.
  Stream<ProfileModel?> watchApprovedProfileByUserId(String userId) => _db
      .collection(AppConstants.profilesCollection)
      .where('userId', isEqualTo: userId)
      .where('status', isEqualTo: 'approved')
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map((s) => newestProfileOf(s.docs));

  Stream<ProfileModel?> watchProfile(String profileId) =>
      _db.collection(AppConstants.profilesCollection).doc(profileId).snapshots().map(
            (doc) => doc.exists ? ProfileModel.fromFirestore(doc) : null,
          );

  // ── FULL profile reads (owner / admin / staff only) ─────────────────────────
  //
  // The member-readable document has every hidden field blanked. These reads
  // lay the private copy back over it. Only call them for a viewer the rules
  // let read `profile_private` — the owner, an admin, or staff. For anyone else
  // the private half is simply absent and the result equals the public read.

  ProfileModel _fullOf(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic>? privateData,
  ) =>
      ProfileModel.fromData(
          doc.id, mergePrivateProfileData(doc.data()!, privateData));

  /// LIVE full profile of [userId] — newest profile document under the uid,
  /// merged with the private copy.
  Stream<ProfileModel?> watchFullProfileByUserId(String userId) =>
      FirestoreSync.combineLatest2<QuerySnapshot<Map<String, dynamic>>,
          Map<String, dynamic>?, ProfileModel?>(
        _db
            .collection(AppConstants.profilesCollection)
            .where('userId', isEqualTo: userId)
            .snapshots(),
        FirestoreSync.optionalDocData(_privateProfileRef(userId),
            label: 'profile_private/$userId'),
        (snap, privateData) {
          if (snap.docs.isEmpty) return null;
          return newestProfile([
            for (final d in snap.docs) _fullOf(d, privateData),
          ]);
        },
      );

  Future<ProfileModel?> getFullProfileByUserId(String userId) async {
    final snap = await _db
        .collection(AppConstants.profilesCollection)
        .where('userId', isEqualTo: userId)
        .get();
    if (snap.docs.isEmpty) return null;
    final privateData = await _readPrivateProfile(userId);
    return newestProfile([for (final d in snap.docs) _fullOf(d, privateData)]);
  }

  /// LIVE full profile by document id.
  Stream<ProfileModel?> watchFullProfile(String profileId) async* {
    final ref = _db.collection(AppConstants.profilesCollection).doc(profileId);
    final first = await ref.get();
    final uid = '${first.data()?['userId'] ?? ''}'.trim();
    if (!first.exists || uid.isEmpty) {
      yield* watchProfile(profileId);
      return;
    }
    yield* FirestoreSync.combineLatest2<DocumentSnapshot<Map<String, dynamic>>,
        Map<String, dynamic>?, ProfileModel?>(
      ref.snapshots(),
      FirestoreSync.optionalDocData(_privateProfileRef(uid),
          label: 'profile_private/$uid'),
      (doc, privateData) => doc.exists ? _fullOf(doc, privateData) : null,
    );
  }

  Future<ProfileModel?> getFullProfile(String profileId) async {
    final doc = await _db
        .collection(AppConstants.profilesCollection)
        .doc(profileId)
        .get();
    if (!doc.exists) return null;
    final uid = '${doc.data()?['userId'] ?? ''}';
    return _fullOf(doc, await _readPrivateProfile(uid));
  }

  /// Every private profile copy, keyed by uid — admin only. Emits an empty map
  /// (never an error) when it cannot be read, so the admin lists still load.
  Stream<Map<String, Map<String, dynamic>>> _watchAllPrivateProfiles() => _db
      .collection(AppConstants.profilePrivateCollection)
      .snapshots()
      .map((s) => {for (final d in s.docs) d.id: d.data()})
      .transform(StreamTransformer<Map<String, Map<String, dynamic>>,
          Map<String, Map<String, dynamic>>>.fromHandlers(
        handleError: (e, st, sink) {
          debugPrint('[FirestoreService] profile_private list unavailable: $e');
          sink.add(const {});
        },
      ));

  /// [profiles] (a live admin query) with each member's private copy merged.
  Stream<List<ProfileModel>> _mergeAllPrivate(
    Query<Map<String, dynamic>> profiles, {
    required int Function(ProfileModel a, ProfileModel b) sort,
    required String label,
  }) =>
      FirestoreSync.combineLatest2<QuerySnapshot<Map<String, dynamic>>,
          Map<String, Map<String, dynamic>>, List<ProfileModel>>(
        profiles.snapshots(),
        _watchAllPrivateProfiles(),
        (snap, privates) {
          final out = <ProfileModel>[];
          for (final d in snap.docs) {
            try {
              final uid = '${d.data()['userId'] ?? ''}';
              out.add(_fullOf(d, privates[uid]));
            } catch (e) {
              debugPrint('[FirestoreSync] $label: skipped ${d.id}: $e');
            }
          }
          out.sort(sort);
          return out;
        },
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

  /// The deterministic `connections/{pair}` document id for two uids.
  static String connectionPairId(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  /// Removes an ACCEPTED interest and the contact-unlock connection it created.
  ///
  /// Both sides of the match are affected, which is the point: after this the
  /// pair is no longer connected, so the interest disappears from BOTH members'
  /// Accepted lists and neither can read the other's gated contact details any
  /// more. The rules already permit this — either party may delete the
  /// interest, and a participant may delete their own connection — so no rules
  /// change is required.
  ///
  /// The connection is deleted FIRST: if the interest went first, the
  /// connection would briefly reference a missing interest, and a failure
  /// between the two writes would leave contact details unlocked for a match
  /// that no longer exists. Losing the interest but keeping the connection is
  /// the more harmful ordering, so it is the one that cannot happen.
  Future<void> removeAcceptedInterest(InterestModel interest) async {
    final pair = connectionPairId(interest.senderId, interest.receiverId);
    await _deleteDocSafe(AppConstants.connectionsCollection, pair);
    await deleteInterest(interest.id);
    debugPrint('[FirestoreService] removed accepted interest ${interest.id} '
        'and connection $pair');
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

  /// FULL contact details — the gated record with the private phone numbers
  /// laid back over it. Owner and admin reads only.
  Future<ContactDetails?> getFullContact(String userId) async {
    final doc = await _db
        .collection(AppConstants.contactsCollection)
        .doc(userId)
        .get();
    final privateData = await _readPrivateContact(userId);
    if (!doc.exists && privateData == null) return null;
    return ContactDetails.fromMap(
        mergePrivateContactData(doc.data() ?? const {}, privateData));
  }

  /// LIVE [getFullContact].
  Stream<ContactDetails?> watchFullContact(String userId) =>
      FirestoreSync.combineLatest2<DocumentSnapshot<Map<String, dynamic>>,
          Map<String, dynamic>?, ContactDetails?>(
        _db.collection(AppConstants.contactsCollection).doc(userId).snapshots(),
        FirestoreSync.optionalDocData(_privateContactRef(userId),
            label: 'contact_private/$userId'),
        (doc, privateData) => (!doc.exists && privateData == null)
            ? null
            : ContactDetails.fromMap(
                mergePrivateContactData(doc.data() ?? const {}, privateData)),
      );

  /// Creates/updates a member's contact details.
  ///
  /// The phone numbers are always stored in `contact_private/{uid}`; the
  /// shareable `contacts/{uid}` record carries them only while "Hide Phone
  /// Number" is off. The record also carries [profileId] — the pointer the
  /// security rules follow to the member's Public/Private sharing choice.
  ///
  /// [profileId] / [hidePhone] are looked up from the member's profile when
  /// not supplied.
  Future<void> saveContact(
    String userId,
    ContactDetails contact, {
    String? profileId,
    bool? hidePhone,
  }) async {
    if (profileId == null || hidePhone == null) {
      final docs = await _profileDocsFor(userId);
      if (docs.isNotEmpty) {
        profileId ??= docs.first.id;
        hidePhone ??= ProfilePrivacy.isHidden(
            ProfilePrivacy.fromMap(docs.first.data()['privacySettings']),
            ProfilePrivacy.phone);
      }
    }
    final values = contact.hasAnyValue ? contact.toMap() : <String, dynamic>{};
    await _writeContact(userId,
        values: values,
        profileId: profileId,
        hidePhone: hidePhone ?? false);
  }

  Future<void> _writeContact(
    String userId, {
    required Map<String, dynamic> values,
    required String? profileId,
    required bool hidePhone,
  }) async {
    final meta = <String, dynamic>{
      'userId': userId,
      if ((profileId ?? '').isNotEmpty) 'profileId': profileId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final contactRef =
        _db.collection(AppConstants.contactsCollection).doc(userId);
    if (!await _useSplitWrites(userId, hidesSomething: hidePhone)) {
      await contactRef.set({...values, ...meta}, SetOptions(merge: true));
      return;
    }
    final split = splitContactWrite(values, hidePhone: hidePhone);
    final batch = _db.batch()
      ..set(contactRef, {...split.public, ...meta}, SetOptions(merge: true));
    if (split.private.isNotEmpty) {
      batch.set(
          _privateContactRef(userId),
          {
            ...split.private,
            'userId': userId,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }
    if (!await _commitPrivacyBatch(batch, uid: userId)) {
      await contactRef.set({...values, ...meta}, SetOptions(merge: true));
    }
  }

  /// Re-applies "Hide Phone Number" to the stored contact record after the
  /// switch changed. Best-effort: the profile save that triggered it already
  /// succeeded.
  Future<void> _reprojectContact(
    String userId, {
    required String profileId,
    required bool hidePhone,
  }) async {
    try {
      final full = await getFullContact(userId);
      await _writeContact(userId,
          values: full?.toMap() ?? const {},
          profileId: profileId,
          hidePhone: hidePhone);
    } catch (e) {
      debugPrint('[FirestoreService] contact re-projection for $userId '
          'skipped: $e');
    }
  }

  /// Makes sure `contacts/{uid}` points at [profileId], so the rules can find
  /// the member's contact-sharing choice. Best-effort.
  Future<void> _ensureContactPointerFor(String profileId) async {
    try {
      final doc = await _db
          .collection(AppConstants.profilesCollection)
          .doc(profileId)
          .get();
      final uid = '${doc.data()?['userId'] ?? ''}'.trim();
      if (uid.isEmpty) return;
      await commitWrite(_db
          .collection(AppConstants.contactsCollection)
          .doc(uid)
          .set({'userId': uid, 'profileId': profileId},
              SetOptions(merge: true)));
    } catch (e) {
      debugPrint('[FirestoreService] contact pointer for $profileId '
          'skipped: $e');
    }
  }

  /// Brings ONE member's stored documents in line with their privacy switches
  /// and repairs the photo mapping — idempotent, and a no-op when everything
  /// is already right.
  ///
  /// Runs for the member themself once per session, and for every member from
  /// the admin "Repair privacy & photos" action. In order, and never
  /// destructively:
  ///
  ///  1. **Photo mapping.** A profile with no `profilePhotoUrl` whose image is
  ///     still referenced from a legacy `photos` / `additionalPhotos` array gets
  ///     it back. [adminRepair] also accepts the member's `users/{uid}.photoUrl`
  ///     mirror — but only for an upload inside that member's OWN Cloudinary
  ///     folder, so nobody can be given someone else's picture.
  ///  2. **Contact record.** Contact details embedded in the public profile by
  ///     an old build are moved into the gated record (if it is empty), phone
  ///     numbers are split per "Hide Phone Number", and the `profileId` pointer
  ///     the rules need is written.
  ///  3. **Private copy + projection.** The full photo / salary / horoscope go
  ///     to `profile_private/{uid}` and the public document is blanked for
  ///     every switch that is on, restored for every switch that is off. One
  ///     batch, so a blank never lands without its private copy.
  ///
  /// Returns what changed, for the admin summary.
  Future<MemberPrivacyRepair> reconcileMemberPrivacy(
    String profileId, {
    bool adminRepair = false,
  }) async {
    final ref = _db.collection(AppConstants.profilesCollection).doc(profileId);
    final snap = await ref.get();
    final publicData = snap.data();
    final uid = '${publicData?['userId'] ?? ''}'.trim();
    if (publicData == null || uid.isEmpty) {
      return const MemberPrivacyRepair.skipped();
    }
    final privateData = await _readPrivateProfile(uid);
    final storageReady = await _privateStorageAvailable(uid) == true;

    // 1) photo mapping — a photo that exists but that `profilePhotoUrl` lost.
    //    First the legacy arrays on the profile itself, then the
    //    `users/{uid}.photoUrl` mirror that every photo save also writes. The
    //    mirror lives on the member's OWN account document (only they and an
    //    admin can write it), and must be an image uploaded through this app's
    //    Cloudinary account — never an identity-provider avatar.
    final hasPhoto = hasStoredValue(publicData['profilePhotoUrl']) ||
        hasStoredValue(privateData?['profilePhotoUrl']);
    var recovered = hasPhoto ? '' : legacyProfilePhoto(publicData);
    if (!hasPhoto && recovered.isEmpty) {
      try {
        final user = await _db
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .get();
        final mirror = '${user.data()?['photoUrl'] ?? ''}'.trim();
        if (mirror.isNotEmpty &&
            !isAuthProviderPhoto(mirror) &&
            isAppCloudinaryImage(mirror)) {
          recovered = mirror;
        }
      } catch (e) {
        debugPrint('[Reconcile] users/$uid mirror unreadable: $e');
      }
    }

    if (!storageReady) {
      // The private collections are not usable (rules not deployed): nothing
      // may be blanked. A lost photo reference is still restored — with a
      // plain update of the one field, which the existing rules allow.
      if (recovered.isEmpty) return const MemberPrivacyRepair.skipped();
      try {
        await commitWrite(ref.update({'profilePhotoUrl': recovered}),
            timeout: const Duration(seconds: 20));
        debugPrint('[Reconcile] $uid: profilePhotoUrl restored on '
            'profiles/$profileId from an existing reference.');
        return const MemberPrivacyRepair(changed: true, recoveredPhoto: true);
      } catch (e) {
        debugPrint('[Reconcile] $uid: photo restore failed: $e');
        return const MemberPrivacyRepair.skipped();
      }
    }

    // 2) contact record
    var contactChanged = false;
    var contactSafe = false;
    try {
      final contactDoc = await _db
          .collection(AppConstants.contactsCollection)
          .doc(uid)
          .get();
      final contactPrivate = await _readPrivateContact(uid);
      final stored = mergePrivateContactData(
          contactDoc.data() ?? const {}, contactPrivate);
      var truthContact = ContactDetails.fromMap(stored);
      final embedded = publicData['contact'];
      if (!truthContact.hasAnyValue && embedded is Map) {
        truthContact =
            ContactDetails.fromMap(Map<String, dynamic>.from(embedded));
      }
      final hidePhone = ProfilePrivacy.isHidden(
          ProfilePrivacy.fromMap(publicData['privacySettings']),
          ProfilePrivacy.phone);
      final wantPublic = splitContactWrite(
              truthContact.hasAnyValue ? truthContact.toMap() : {},
              hidePhone: hidePhone)
          .public;
      final current = contactDoc.data() ?? const <String, dynamic>{};
      final needsWrite = current['profileId'] != profileId ||
          wantPublic.entries.any((e) => '${current[e.key] ?? ''}' !=
              '${e.value ?? ''}') ||
          (hidePhone &&
              truthContact.hasAnyValue &&
              contactPrivate == null &&
              (truthContact.mobileNumber.isNotEmpty ||
                  (truthContact.whatsappNumber ?? '').isNotEmpty));
      if (needsWrite) {
        await _writeContact(uid,
            values: truthContact.hasAnyValue ? truthContact.toMap() : {},
            profileId: profileId,
            hidePhone: hidePhone);
        contactChanged = true;
      }
      contactSafe = true;
    } catch (e) {
      debugPrint('[Reconcile] contact record for $uid skipped: $e');
    }

    // 3) private copy + projection. The embedded contact copy is removed from
    //    the public profile only once the gated record is known to be safe.
    final plan = planPrivacyReconcile(
      publicData: contactSafe
          ? publicData
          : (Map<String, dynamic>.of(publicData)..remove('contact')),
      privateData: privateData,
      recoveredPhoto: recovered,
    );
    if (plan.isNoop) {
      return MemberPrivacyRepair(
          changed: contactChanged, recoveredPhoto: false);
    }
    final batch = _db.batch();
    if (plan.privateWrite != null) {
      batch.set(_privateProfileRef(uid), {
        ...plan.privateWrite!,
        'userId': uid,
        'profileId': profileId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (plan.publicUpdate.isNotEmpty) batch.update(ref, plan.publicUpdate);
    if (!await _commitPrivacyBatch(batch, uid: uid)) {
      return const MemberPrivacyRepair.skipped();
    }
    if (plan.recoveredPhoto.isNotEmpty) {
      debugPrint('[Reconcile] $uid: photo mapping restored from an existing '
          'reference.');
    }
    return MemberPrivacyRepair(
        changed: true, recoveredPhoto: plan.recoveredPhoto.isNotEmpty);
  }

  /// ADMIN: runs [reconcileMemberPrivacy] for every profile. Sequential and
  /// best-effort per member — one failure never stops the rest.
  Future<PrivacyRepairSummary> repairAllMemberPrivacy() async {
    final snap =
        await _db.collection(AppConstants.profilesCollection).limit(5000).get();
    var changed = 0, photos = 0, skipped = 0, failed = 0;
    for (final d in snap.docs) {
      try {
        final r = await reconcileMemberPrivacy(d.id, adminRepair: true);
        if (r.skipped) {
          skipped++;
        } else if (r.changed) {
          changed++;
        }
        if (r.recoveredPhoto) photos++;
      } catch (e) {
        failed++;
        debugPrint('[Reconcile] ${d.id} failed: $e');
      }
    }
    return PrivacyRepairSummary(
      total: snap.docs.length,
      changed: changed,
      recoveredPhotos: photos,
      skipped: skipped,
      failed: failed,
    );
  }

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

  /// Admin **profile verification** — the green tick beside a member's name
  /// (spec §13/§14).
  ///
  /// Deliberately separate from the approval [status] and from the Aadhaar
  /// check, because it must be REVERSIBLE: revoking writes `profileVerified:
  /// false` rather than deleting the field or demoting the profile, so the
  /// account, its data and its visibility are all untouched — only the badge
  /// changes. Verify → revoke → verify again is a normal cycle, not an
  /// exceptional one.
  Future<void> setProfileVerified({
    required String profileId,
    required bool verified,
    String adminUid = '',
  }) =>
      _db.collection(AppConstants.profilesCollection).doc(profileId).update({
        'profileVerified': verified,
        'profileVerifiedAt': FieldValue.serverTimestamp(),
        if (adminUid.isNotEmpty) 'profileVerifiedBy': adminUid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
        // Banners are image-only. Documents without artwork (legacy
        // text/template banners) are skipped so nothing fake can reach Home.
        final list = s.docs
            .map(HomeBannerModel.fromFirestore)
            .where((b) => b.hasImage)
            .toList();
        list.sort((a, b) => a.order.compareTo(b.order));
        return list;
      });

  /// ALL banners (any status) for the admin management screen, by order.
  Stream<List<HomeBannerModel>> watchAllBanners() => _db
      .collection(AppConstants.bannersCollection)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map(HomeBannerModel.fromFirestore)
            .where((b) => b.hasImage)
            .toList();
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

  /// Records the version code this member is actually running.
  ///
  /// Without it the update push would have to go to everyone, including people
  /// already on the newest build (spec §7). Merged onto the user document and
  /// completely best-effort — a failure here must never affect startup.
  Future<void> recordAppVersion(String uid, int versionCode) async {
    if (uid.trim().isEmpty || versionCode <= 0) return;
    try {
      await _db.collection(AppConstants.usersCollection).doc(uid).set(
        {'appVersionCode': versionCode},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[Firestore] recordAppVersion skipped: $e');
    }
  }

  // ── App rating (spec §29–§32) ─────────────────────────────────────────────

  /// True once this ACCOUNT has completed the rating flow.
  ///
  /// Stored on the user document rather than only on the device so the promise
  /// in spec §31 actually holds: a member who has rated is never asked again,
  /// including after a reinstall or on a second phone. A read failure returns
  /// false — the worst case is one extra ask, which the device-level cooldown
  /// still throttles.
  Future<bool> hasRatedApp(String uid) async {
    if (uid.trim().isEmpty) return false;
    try {
      final doc =
          await _db.collection(AppConstants.usersCollection).doc(uid).get();
      return (doc.data() ?? const {})['appRated'] == true;
    } catch (e) {
      debugPrint('[Firestore] hasRatedApp skipped: $e');
      return false;
    }
  }

  /// Records the account's rating state.
  ///
  /// [rated] true is TERMINAL — nothing ever sets it back to false, because
  /// "already rated" cannot become untrue. A false call only stamps WHEN the
  /// member was last asked, which is what the cooldown reads.
  Future<void> setRatingStatus({
    required String uid,
    required bool rated,
  }) async {
    if (uid.trim().isEmpty) return;
    try {
      await _db.collection(AppConstants.usersCollection).doc(uid).set({
        if (rated) 'appRated': true,
        if (rated) 'appRatedAt': FieldValue.serverTimestamp(),
        'appRatingAskedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Firestore] setRatingStatus skipped: $e');
    }
  }

  // ── App version / release gate (spec §23–§28) ─────────────────────────────
  //
  // The app is updated through Google Play, never pushed from here — what
  // this config carries is only WHEN the app should insist on it.

  DocumentReference<Map<String, dynamic>> get _updateConfigRef => _db
      .collection(AppConstants.appConfigCollection)
      .doc(AppConstants.appUpdateConfigDoc);

  /// Live release config. A missing document yields the DEFAULT config, whose
  /// latestVersionCode is 0 — i.e. "nothing configured, prompt nobody" — so a
  /// project that has never set this up behaves exactly as before.
  Stream<AppUpdateConfig> watchAppUpdateConfig() => _updateConfigRef
      .snapshots()
      .map((d) => d.exists
          ? AppUpdateConfig.fromFirestore(d)
          : const AppUpdateConfig())
      // A rules denial or offline read must not surface as an error that
      // blocks the app; fall back to "nothing to do".
      .handleError((Object e) {
        debugPrint('[Firestore] update config unavailable: $e');
      });

  Future<AppUpdateConfig> getAppUpdateConfig() async {
    try {
      final d = await _updateConfigRef.get();
      return d.exists ? AppUpdateConfig.fromFirestore(d) : const AppUpdateConfig();
    } catch (e) {
      debugPrint('[Firestore] update config read failed: $e');
      return const AppUpdateConfig();
    }
  }

  Future<void> saveAppUpdateConfig(Map<String, dynamic> fields) =>
      _updateConfigRef.set(
        {...fields, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

  // ── App-opening popups (admin-managed, spec §13/§14) ──────────────────────

  /// ACTIVE popups in display order — the rotation the user sees.
  Stream<List<AppPopupModel>> watchActivePopups() => _db
      .collection(AppConstants.appPopupsCollection)
      .where('enabled', isEqualTo: true)
      .snapshots()
      .map((s) {
        // An empty popup (no title AND no body) is never shown, so a
        // half-created document cannot reach users.
        final list = s.docs
            .map(AppPopupModel.fromFirestore)
            .where((p) => p.hasContent)
            .toList();
        list.sort((a, b) => a.order.compareTo(b.order));
        return list;
      });

  /// ALL popups (any status) for the admin management screen.
  Stream<List<AppPopupModel>> watchAllPopups() => _db
      .collection(AppConstants.appPopupsCollection)
      .snapshots()
      .map((s) {
        final list = s.docs.map(AppPopupModel.fromFirestore).toList();
        list.sort((a, b) => a.order.compareTo(b.order));
        return list;
      });

  Future<void> createPopup(AppPopupModel popup) => _db
      .collection(AppConstants.appPopupsCollection)
      .add(popup.toFirestore()..['createdAt'] = FieldValue.serverTimestamp());

  Future<void> updatePopup(String id, Map<String, dynamic> fields) => _db
      .collection(AppConstants.appPopupsCollection)
      .doc(id)
      .update({...fields, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> deletePopup(String id) =>
      _db.collection(AppConstants.appPopupsCollection).doc(id).delete();

  /// Swaps the display order of two popups atomically (Move Up / Move Down).
  Future<void> swapPopupOrder(
      String idA, int orderA, String idB, int orderB) async {
    final batch = _db.batch();
    final col = _db.collection(AppConstants.appPopupsCollection);
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

  /// Realtime [getAllUsers] — matrimony members, newest-first.
  ///
  /// A member is any account that is not staff, a dedicated admin or a
  /// wedding-workspace family login. `super_admin` is kept: that account is a
  /// matrimony member with an admin shortcut, and dropping it hid a real
  /// profile from the admin panel.
  Stream<List<UserModel>> watchAllUsers({int limit = 300}) =>
      FirestoreSync.collectionStream<UserModel>(
        _db.collection(AppConstants.usersCollection).limit(limit),
        fromDoc: UserModel.fromFirestore,
        where: (u) => !const {'admin', 'astrologer', 'family'}.contains(u.role),
        sort: (a, b) => b.createdAt.compareTo(a.createdAt),
        label: 'allUsers',
      );

  /// Realtime [getAllProfiles] — every profile, newest-first. The limit
  /// bounds runaway reads while keeping the admin dashboard's profile stats
  /// accurate far beyond the visible list size.
  ///
  /// ADMIN view: each profile carries its private copy (hidden photo, salary,
  /// horoscope), because member privacy settings never apply to an admin.
  Stream<List<ProfileModel>> watchAllProfiles({int limit = 5000}) =>
      _mergeAllPrivate(
        _db.collection(AppConstants.profilesCollection).limit(limit),
        sort: (a, b) => b.createdAt.compareTo(a.createdAt),
        label: 'allProfiles',
      );

  /// Realtime [getPendingProfiles] — oldest-first (FIFO moderation). Sorted
  /// client-side to avoid the where + orderBy composite index. Admin view, so
  /// hidden fields are merged back in like [watchAllProfiles].
  Stream<List<ProfileModel>> watchPendingProfiles() => _mergeAllPrivate(
        _db
            .collection(AppConstants.profilesCollection)
            .where('status', isEqualTo: 'pending'),
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
  /// Permanently removes every Firestore record belonging to [uid].
  ///
  /// Returns the names of the steps that did NOT complete — empty means the
  /// account's data is genuinely gone. That return value is the point of this
  /// method's shape (spec §3/§4/§26).
  ///
  /// Each step used to swallow its own failure and carry on, which made a
  /// PARTIAL deletion indistinguishable from a complete one. That is how the
  /// worst bug in this area happened: the profile delete quietly failed, the
  /// Firebase Auth record also survived (`requires-recent-login`), the same uid
  /// signed in again — and the "deleted" profile was still there waiting. The
  /// caller now knows what survived and can say so instead of reporting
  /// success.
  ///
  /// ORDER MATTERS. `users/{uid}` is deleted LAST: the security rules resolve
  /// `isAdmin()` and several ownership checks by reading that very document, so
  /// removing it first would revoke the caller's own access half way through
  /// and deny everything after it.
  Future<List<String>> deleteUserAccountData(String uid) async {
    debugPrint('[Firestore] 🗑 deleteUserAccountData($uid)');
    final failed = <String>[];
    Future<void> step(String label, Future<bool> Function() run) async {
      if (!await run()) failed.add(label);
    }

    // The profile FIRST and verified: it is the document that makes a deleted
    // member still look like a member.
    await step('profiles',
        () => _deleteWhere(AppConstants.profilesCollection, 'userId', uid));
    await step('interests(sent)',
        () => _deleteWhere(AppConstants.interestsCollection, 'senderId', uid));
    await step(
        'interests(received)',
        () =>
            _deleteWhere(AppConstants.interestsCollection, 'receiverId', uid));
    await step(
        'notifications',
        () =>
            _deleteWhere(AppConstants.notificationsCollection, 'userId', uid));
    await step(
        'account_deletion_requests',
        () => _deleteWhere(
            AppConstants.accountDeletionRequestsCollection, 'userId', uid));
    // Horoscope-report / appointment bookings this member created. Owned by
    // them per the rules, so the delete is permitted.
    await step(
        'astrologer_requests',
        () => _deleteWhere(
            AppConstants.astrologerRequestsCollection, 'userId', uid));
    await step(
        'consultations',
        () =>
            _deleteWhere(AppConstants.consultationsCollection, 'userId', uid));
    // Moderation records this member created. The ones filed AGAINST them are
    // deliberately left for admins — a deleted account must not erase the
    // reports about it.
    await step('blocks',
        () => _deleteWhere(AppConstants.blocksCollection, 'blockerUid', uid));
    await step(
        'connections',
        () => _deleteArrayContains(
            AppConstants.connectionsCollection, 'uids', uid));
    await step('contacts',
        () => _deleteDocSafe(AppConstants.contactsCollection, uid));
    // The private halves of the profile and contact record (hidden photo,
    // salary, horoscope, phone numbers) must not outlive the account either.
    await step('contact_private',
        () => _deleteDocSafe(AppConstants.contactPrivateCollection, uid));
    await step('profile_private',
        () => _deleteDocSafe(AppConstants.profilePrivateCollection, uid));
    // Sensitive KYC record — must not outlive the account.
    await step('aadhaar',
        () => _deleteDocSafe(AppConstants.aadhaarCollection, uid));
    // The mobile → sign-in-address index. Leaving it behind is what makes a
    // deleted member's phone number look "already registered" forever, and
    // points it at an auth address that no longer exists (spec §4/§21).
    await step('login_index', () => _deleteLoginIndexFor(uid));
    // LAST — see the ordering note above.
    await step('users',
        () => _deleteDocSafe(AppConstants.usersCollection, uid));

    if (failed.isEmpty) {
      debugPrint('[Firestore] ✅ deleteUserAccountData($uid): all data removed.');
    } else {
      debugPrint('[Firestore] ⚠ deleteUserAccountData($uid): these did NOT '
          'complete → ${failed.join(', ')}');
    }
    return failed;
  }

  /// Removes the `login_index` entry (or entries) pointing at [uid].
  ///
  /// Keyed by mobile number rather than uid, so it has to be looked up by its
  /// `uid` field. The index is publicly readable by design (a phone login has
  /// to resolve an address BEFORE anyone is authenticated), so this query is
  /// always permitted.
  Future<bool> _deleteLoginIndexFor(String uid) async {
    try {
      final snap = await _db
          .collection(LoginDirectoryService.collection)
          .where('uid', isEqualTo: uid)
          .get();
      if (snap.docs.isEmpty) return true;
      await _deleteDocs(snap.docs);
      return true;
    } catch (e) {
      debugPrint('[Firestore] login_index cleanup for $uid failed: $e');
      return false;
    }
  }

  /// Whether any Firestore data is still stored for [uid].
  ///
  /// Used to VERIFY a deletion rather than assume it (spec §4). Only the
  /// documents that would resurrect the account are checked — the profile and
  /// the account document — because those are what a later sign-in reads.
  Future<bool> hasResidualAccountData(String uid) async {
    try {
      final profiles = await _profileDocsFor(uid);
      if (profiles.isNotEmpty) {
        debugPrint('[Firestore] residual check: ${profiles.length} profile(s) '
            'still stored for $uid.');
        return true;
      }
      final user =
          await _db.collection(AppConstants.usersCollection).doc(uid).get();
      if (user.exists) {
        debugPrint('[Firestore] residual check: users/$uid still exists.');
        return true;
      }
      return false;
    } catch (e) {
      // A denied/failed check is not evidence of residue — say "clean" rather
      // than alarm the member, and let the per-step failures above speak.
      debugPrint('[Firestore] residual check for $uid skipped: $e');
      return false;
    }
  }

  /// Permanently deletes ALL Firestore data owned by an astrologer: their
  /// `astrologers/{uid}` account (services / certificates are embedded in that
  /// document), the `astrologers/{uid}/reviews` subcollection (Firestore does
  /// NOT cascade-delete subcollections, so it must be cleared explicitly), every
  /// `astrologer_requests` addressed to them, any stale deletion request, and
  /// the `users/{uid}` role document.
  /// Returns the steps that did not complete — see [deleteUserAccountData] for
  /// why the result is reported rather than swallowed.
  Future<List<String>> deleteAstrologerAccountData(String uid) async {
    debugPrint('[Firestore] 🗑 deleteAstrologerAccountData($uid)');
    final failed = <String>[];
    Future<void> step(String label, Future<bool> Function() run) async {
      if (!await run()) failed.add(label);
    }

    // NOT deleted: `astrologer_requests` assigned to this employee. Those are
    // MEMBERS' records — their paid horoscope-report requests and the reports
    // written for them — so deleting the employee's account must not destroy
    // them. They stay for an admin to reassign.
    // Reviews about this astrologer live in astrologers/{uid}/reviews.
    await step(
        'astrologer_reviews',
        () => _deleteSubcollection(AppConstants.astrologersCollection, uid,
            AppConstants.astrologerReviewsSubcollection));
    await step(
        'account_deletion_requests',
        () => _deleteWhere(
            AppConstants.accountDeletionRequestsCollection, 'userId', uid));
    await step('astrologers',
        () => _deleteDocSafe(AppConstants.astrologersCollection, uid));
    // LAST: the rules read users/{uid} to authorise the steps above.
    await step('users',
        () => _deleteDocSafe(AppConstants.usersCollection, uid));
    if (failed.isNotEmpty) {
      debugPrint('[Firestore] ⚠ deleteAstrologerAccountData($uid): these did '
          'NOT complete → ${failed.join(', ')}');
    }
    return failed;
  }

  /// Deletes every document in the `{parentCollection}/{parentId}/{sub}`
  /// subcollection. Guarded so a failure (e.g. rules) can't abort the wider
  /// account-deletion sequence.
  Future<bool> _deleteSubcollection(
      String parentCollection, String parentId, String sub) async {
    try {
      final snap = await _db
          .collection(parentCollection)
          .doc(parentId)
          .collection(sub)
          .get();
      await _deleteDocs(snap.docs);
      return true;
    } catch (e) {
      debugPrint('[Firestore] deleteSubcollection('
          '$parentCollection/$parentId/$sub) FAILED: $e');
      return false;
    }
  }

  /// Deletes every document in [collection] where [field] == [value].
  ///
  /// Returns whether it completed. The boolean is what lets
  /// [deleteUserAccountData] tell a partial deletion from a whole one instead
  /// of logging a failure and moving on as if nothing happened.
  Future<bool> _deleteWhere(
      String collection, String field, String value) async {
    try {
      final snap =
          await _db.collection(collection).where(field, isEqualTo: value).get();
      await _deleteDocs(snap.docs);
      return true;
    } catch (e) {
      debugPrint('[Firestore] deleteWhere($collection.$field==$value) FAILED: $e');
      return false;
    }
  }

  /// Deletes every document in [collection] whose [arrayField] contains
  /// [value]. Returns whether it completed.
  Future<bool> _deleteArrayContains(
      String collection, String arrayField, String value) async {
    try {
      final snap = await _db
          .collection(collection)
          .where(arrayField, arrayContains: value)
          .get();
      await _deleteDocs(snap.docs);
      return true;
    } catch (e) {
      debugPrint('[Firestore] deleteArrayContains($collection.$arrayField) FAILED: $e');
      return false;
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

  /// Deletes a single document. Returns whether it completed — a missing
  /// document counts as success (there is nothing left to remove), a denied or
  /// failed delete does not.
  Future<bool> _deleteDocSafe(String collection, String id) async {
    try {
      await _db.collection(collection).doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('[Firestore] delete $collection/$id FAILED: $e');
      return false;
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
