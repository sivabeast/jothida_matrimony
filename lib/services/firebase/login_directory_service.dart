import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
  Future<bool> isPhoneRegistered(String mobile) async {
    final key = LoginIdentifier.phoneKey(mobile);
    if (key.isEmpty) return false;
    final snap = await _doc(key).get().timeout(const Duration(seconds: 10));
    return snap.exists && (snap.data()?['authEmail'] ?? '').toString().isNotEmpty;
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
