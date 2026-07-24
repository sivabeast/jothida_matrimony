import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/admin_config.dart';

class UserModel {
  final String uid;
  final String? email;
  final String? phone;
  final String? displayName;
  final String? photoUrl;
  // 'google.com' | 'password' | 'phone' — how the user authenticated.
  final String? loginProvider;
  final String? gender; // 'Male' | 'Female' — collected at signup
  final String role; // user, admin, astrologer
  final bool isProfileComplete;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final bool isBlocked;
  final String? profileId; // Link to profile document
  final int freePortuthamsUsed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;
  final Map<String, bool> privacySettings;
  final String? fcmToken;
  // Preferred app/report language: 'ta' (Tamil) | 'en' (English). Drives the
  // localisation of the whole app and the language the astrologer writes the
  // report in. Null until the user has chosen.
  final String? preferredLanguage;

  const UserModel({
    required this.uid,
    this.email,
    this.phone,
    this.displayName,
    this.photoUrl,
    this.loginProvider,
    this.gender,
    this.role = 'user',
    this.isProfileComplete = false,
    this.isEmailVerified = false,
    this.isPhoneVerified = false,
    this.isBlocked = false,
    this.profileId,
    this.freePortuthamsUsed = 0,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
    this.privacySettings = const {
      'hidePhone': false,
      'hideAddress': false,
      'hideFamilyDetails': false,
      'hideSalary': false,
      'hideHoroscope': false,
      'hideAdditionalPhotos': false,
    },
    this.fcmToken,
    this.preferredLanguage,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'],
      phone: data['phone'],
      displayName: data['displayName'],
      photoUrl: data['photoUrl'],
      loginProvider: data['loginProvider'],
      gender: data['gender'],
      role: data['role'] ?? 'user',
      isProfileComplete: _boolOf(data['isProfileComplete']),
      isEmailVerified: _boolOf(data['isEmailVerified']),
      isPhoneVerified: _boolOf(data['isPhoneVerified']),
      isBlocked: _boolOf(data['isBlocked']),
      profileId: data['profileId'],
      freePortuthamsUsed: _intOf(data['freePortuthamsUsed']),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
      lastLoginAt: data['lastLoginAt'] is Timestamp
          ? (data['lastLoginAt'] as Timestamp).toDate()
          : null,
      privacySettings: _privacyOf(data['privacySettings']),
      fcmToken: data['fcmToken'],
      preferredLanguage: data['preferred_language'],
    );
  }

  /// Default privacy flags — used when a document has none, and to backfill any
  /// key an older document is missing.
  static const Map<String, bool> _defaultPrivacy = {
    'hidePhone': false,
    'hideAddress': false,
    'hideFamilyDetails': false,
    'hideSalary': false,
    'hideHoroscope': false,
    'hideAdditionalPhotos': false,
  };

  /// Coerces a Firestore value into a `bool` instead of blindly casting it.
  ///
  /// Some historic documents (and a few admin/registration writes) stored these
  /// flags as the STRINGS `"true"`/`"false"` or as `0`/`1`. A direct assignment
  /// then threw `type 'String' is not a subtype of type 'bool' in type cast`
  /// during `fromFirestore`, which surfaced as "Signed in, but something went
  /// wrong while setting up your account" and blocked the user right AFTER a
  /// successful Google sign-in. Coercing here makes login resilient to that.
  static bool _boolOf(dynamic v, {bool fallback = false}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no' || s.isEmpty) return false;
    }
    return fallback;
  }

  /// Same defensive idea for the one integer field, so a stringified count
  /// ("2") can't crash the parse either.
  static int _intOf(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  /// Builds the privacy map without a blanket `Map<String, bool>.from`, which
  /// throws the moment ANY stored value is a string. Each value is coerced and
  /// the defaults backfill any missing key.
  static Map<String, bool> _privacyOf(dynamic raw) {
    final out = Map<String, bool>.from(_defaultPrivacy);
    if (raw is Map) {
      raw.forEach((k, v) => out[k.toString()] = _boolOf(v));
    }
    return out;
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'phone': phone,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'loginProvider': loginProvider,
        'gender': gender,
        'role': role,
        'isProfileComplete': isProfileComplete,
        'isEmailVerified': isEmailVerified,
        'isPhoneVerified': isPhoneVerified,
        'isBlocked': isBlocked,
        'profileId': profileId,
        'freePortuthamsUsed': freePortuthamsUsed,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'lastLoginAt':
            lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
        'privacySettings': privacySettings,
        'fcmToken': fcmToken,
        'preferred_language': preferredLanguage,
      };

  UserModel copyWith({
    String? uid,
    String? email,
    String? phone,
    String? displayName,
    String? photoUrl,
    String? loginProvider,
    String? gender,
    String? role,
    bool? isProfileComplete,
    bool? isEmailVerified,
    bool? isPhoneVerified,
    bool? isBlocked,
    String? profileId,
    int? freePortuthamsUsed,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
    Map<String, bool>? privacySettings,
    String? fcmToken,
    String? preferredLanguage,
  }) =>
      UserModel(
        uid: uid ?? this.uid,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        loginProvider: loginProvider ?? this.loginProvider,
        gender: gender ?? this.gender,
        role: role ?? this.role,
        isProfileComplete: isProfileComplete ?? this.isProfileComplete,
        isEmailVerified: isEmailVerified ?? this.isEmailVerified,
        isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
        isBlocked: isBlocked ?? this.isBlocked,
        profileId: profileId ?? this.profileId,
        freePortuthamsUsed: freePortuthamsUsed ?? this.freePortuthamsUsed,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
        privacySettings: privacySettings ?? this.privacySettings,
        fcmToken: fcmToken ?? this.fcmToken,
        preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      );

  /// `super_admin` accounts also have full admin privileges (route protection
  /// and Admin Dashboard access). Only the email(s) in
  /// `AdminConfig.superAdminEmails` receive this role, assigned automatically
  /// on login.
  ///
  /// The whitelist is checked as a FALLBACK on top of the stored role. The role
  /// is written by `createOrUpdateUserOnLogin`, and that write can legitimately
  /// not be in effect yet — the document was just created, the promotion write
  /// was blocked, or this copy of the model predates it. Deriving admin status
  /// from the (immutable, authenticated) email as well is why the Admin button
  /// can no longer silently disappear for the whitelisted account.
  ///
  /// This is a UI/UX affordance only: Firestore still enforces admin writes
  /// server-side via the `role` field in firestore.rules, so a stale local
  /// value grants no extra data access.
  bool get isAdmin =>
      role == 'admin' || role == 'super_admin' || _isWhitelistedSuperAdmin;

  /// Employee (horoscope-analysis staff). The internal role value keeps the
  /// legacy name 'astrologer' for data compatibility.
  bool get isAstrologer => role == 'astrologer';
  bool get isSuperAdmin => role == 'super_admin' || _isWhitelistedSuperAdmin;

  bool get _isWhitelistedSuperAdmin => AdminConfig.isSuperAdminEmail(email);

  /// FAMILY user — invited (by gmail) into a couple's Wedding Workspace.
  /// Family users have NO matrimony profile and are locked to the workspace;
  /// they can never browse matches, send interests or chat.
  bool get isFamily => role == 'family';
}
