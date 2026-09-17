import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/account_identity.dart';
import '../../core/utils/login_identifier.dart';

/// The mobile-number → sign-in-address index (`login_index/{10-digit-mobile}`).
///
/// WHY IT EXISTS: Firebase Authentication verifies a password against an
/// *e-mail* credential only. A member who registered with a real e-mail but
/// then logs in with their **mobile number** cannot be resolved by Firebase, and
/// the `users` collection is (correctly) not readable before sign-in. This tiny
/// index is the standard Firebase pattern for that lookup.
///
/// It is deliberately minimal — one field, `authEmail`, plus the owning `uid`
/// so the security rules can stop anyone from re-pointing someone else's
/// number. It duplicates nothing: `users/{uid}` remains the single source of
/// truth for the account itself.
///
/// Phone-only accounts (no real e-mail) resolve WITHOUT this index via
/// [LoginIdentifier.phoneAuthEmail], so a lookup failure is never fatal.
class LoginDirectoryService {
  final FirebaseFirestore _db;

  LoginDirectoryService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  static const String collection = 'login_index';

  DocumentReference<Map<String, dynamic>> _doc(String mobile) =>
      _db.collection(collection).doc(LoginIdentifier.phoneKey(mobile));

  /// The Firebase Auth address registered for [mobile], or `null` when the
  /// number is unknown (or the lookup could not complete). Bounded and
  /// non-throwing: the caller falls back to the synthesized phone address.
  Future<String?> authEmailForPhone(String mobile) async {
    final key = LoginIdentifier.phoneKey(mobile);
    if (key.isEmpty) return null;
    try {
      final snap = await _doc(key).get().timeout(const Duration(seconds: 10));
      final email = (snap.data()?['authEmail'] ?? '').toString().trim();
      debugPrint('[LoginDirectory] $key → '
          '${email.isEmpty ? 'not registered' : 'resolved'}');
      return email.isEmpty ? null : email;
    } catch (e) {
      debugPrint('[LoginDirectory] lookup for $key failed (non-fatal): $e');
      return null;
    }
  }

  /// Whether a mobile number already has a login account. Used by the admin
  /// "Login Credentials" step to refuse duplicates BEFORE creating anything.
  Future<bool> isPhoneRegistered(String mobile) async =>
      (await lookup(mobile)) != null;

  /// The registry entry for [mobile], or null when the number is free.
  ///
  /// STRICT — unlike [authEmailForPhone] a failed read throws: every caller is
  /// a duplicate guard, and "could not check" must never be read as "free".
  Future<LoginIndexEntry?> lookup(String mobile) async {
    final key = LoginIdentifier.localMobile(mobile);
    if (key == null) return null;
    final snap = await _doc(key)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    return _entryOf(key, snap.data());
  }

  static LoginIndexEntry? _entryOf(String mobile, Map<String, dynamic>? data) {
    final authEmail = '${data?['authEmail'] ?? ''}'.trim();
    if (data == null || authEmail.isEmpty) return null;
    return LoginIndexEntry(
        mobile: mobile, uid: '${data['uid'] ?? ''}'.trim(), authEmail: authEmail);
  }

  /// Claims [mobile] for [uid] ATOMICALLY and returns the entry that holds the
  /// number afterwards.
  ///
  /// When another uid already holds it, nothing is written and that entry is
  /// returned — the caller decides (registration rolls its new login back,
  /// the admin is shown the existing account). This is what closes the race
  /// in which two registrations for the same number both passed a pre-check.
  Future<LoginIndexEntry> claim({
    required String mobile,
    required String authEmail,
    required String uid,
  }) async {
    final key = LoginIdentifier.localMobile(mobile);
    if (key == null) {
      throw ArgumentError.value(mobile, 'mobile', 'Not a 10-digit mobile');
    }
    final ref = _doc(key);
    final email = authEmail.trim().toLowerCase();
    return _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final existing = _entryOf(key, snap.data());
      if (existing != null && existing.uid.isNotEmpty && existing.uid != uid) {
        debugPrint('[LoginDirectory] $key is already held by ${existing.uid}.');
        return existing;
      }
      txn.set(ref, {
        'authEmail': email,
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return LoginIndexEntry(mobile: key, uid: uid, authEmail: email);
    }).timeout(const Duration(seconds: 20));
  }

  /// ADMIN: gives [mobile] back to [uid] (restoring a disabled login). The
  /// rules accept this only from an admin, and only while the number is free.
  Future<void> assign({
    required String mobile,
    required String authEmail,
    required String uid,
  }) async {
    final key = LoginIdentifier.localMobile(mobile);
    if (key == null) return;
    await _doc(key).set({
      'authEmail': authEmail.trim().toLowerCase(),
      'uid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ADMIN: frees [mobile] (a confirmed stale entry, or a login being removed).
  Future<void> release(String mobile) async {
    final key = LoginIdentifier.localMobile(mobile);
    if (key == null) return;
    await _doc(key).delete();
    debugPrint('[LoginDirectory] released $key');
  }

  /// ADMIN: every entry that points at [uid] (normally zero or one).
  Future<List<LoginIndexEntry>> entriesForUid(String uid) async {
    if (uid.trim().isEmpty) return const [];
    final snap =
        await _db.collection(collection).where('uid', isEqualTo: uid).get();
    return [
      for (final d in snap.docs) ?_entryOf(d.id, d.data()),
    ];
  }

  /// ADMIN (Account Health): the whole registry.
  Future<List<LoginIndexEntry>> allEntries() async {
    final snap = await _db.collection(collection).get();
    return [
      for (final d in snap.docs)
        LoginIndexEntry(
          mobile: d.id,
          uid: '${d.data()['uid'] ?? ''}'.trim(),
          authEmail: '${d.data()['authEmail'] ?? ''}'.trim(),
        ),
    ];
  }

  /// Registers (or refreshes) the mapping for a just-created account.
  ///
  /// [uid] must be the owner's uid — the security rules only accept a write
  /// whose `uid` equals the caller, which is what prevents anyone from
  /// hijacking another member's number.
  Future<void> register({
    required String mobile,
    required String authEmail,
    required String uid,
  }) async {
    final key = LoginIdentifier.phoneKey(mobile);
    if (key.isEmpty || authEmail.trim().isEmpty) return;
    await _doc(key).set({
      'authEmail': authEmail.trim().toLowerCase(),
      'uid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('[LoginDirectory] registered $key → $authEmail');
  }

  /// Best-effort variant used on paths where a failed index write must never
  /// break the surrounding flow (the account itself is already created).
  Future<void> registerQuietly({
    required String mobile,
    required String authEmail,
    required String uid,
  }) async {
    try {
      await register(mobile: mobile, authEmail: authEmail, uid: uid)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[LoginDirectory] register skipped (non-fatal): $e');
    }
  }
}
