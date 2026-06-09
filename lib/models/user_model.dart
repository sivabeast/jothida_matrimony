import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String? email;
  final String? phone;
  final String? displayName;
  final String? photoUrl;
  final String role; // user, admin, astrologer
  final bool isProfileComplete;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final bool isBlocked;
  final String? profileId; // Link to profile document
  final String? subscriptionPlan;
  final DateTime? subscriptionExpiry;
  final int freePortuthamsUsed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, bool> privacySettings;
  final String? fcmToken;

  const UserModel({
    required this.uid,
    this.email,
    this.phone,
    this.displayName,
    this.photoUrl,
    this.role = 'user',
    this.isProfileComplete = false,
    this.isEmailVerified = false,
    this.isPhoneVerified = false,
    this.isBlocked = false,
    this.profileId,
    this.subscriptionPlan,
    this.subscriptionExpiry,
    this.freePortuthamsUsed = 0,
    required this.createdAt,
    required this.updatedAt,
    this.privacySettings = const {
      'hidePhone': false,
      'hideAddress': false,
      'hideFamilyDetails': false,
      'hideSalary': false,
      'hideHoroscope': false,
      'hideAdditionalPhotos': false,
    },
    this.fcmToken,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'],
      phone: data['phone'],
      displayName: data['displayName'],
      photoUrl: data['photoUrl'],
      role: data['role'] ?? 'user',
      isProfileComplete: data['isProfileComplete'] ?? false,
      isEmailVerified: data['isEmailVerified'] ?? false,
      isPhoneVerified: data['isPhoneVerified'] ?? false,
      isBlocked: data['isBlocked'] ?? false,
      profileId: data['profileId'],
      subscriptionPlan: data['subscriptionPlan'],
      subscriptionExpiry: data['subscriptionExpiry'] != null
          ? (data['subscriptionExpiry'] as Timestamp).toDate()
          : null,
      freePortuthamsUsed: data['freePortuthamsUsed'] ?? 0,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
      privacySettings: Map<String, bool>.from(data['privacySettings'] ?? {
        'hidePhone': false,
        'hideAddress': false,
        'hideFamilyDetails': false,
        'hideSalary': false,
        'hideHoroscope': false,
        'hideAdditionalPhotos': false,
      }),
      fcmToken: data['fcmToken'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'phone': phone,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'role': role,
        'isProfileComplete': isProfileComplete,
        'isEmailVerified': isEmailVerified,
        'isPhoneVerified': isPhoneVerified,
        'isBlocked': isBlocked,
        'profileId': profileId,
        'subscriptionPlan': subscriptionPlan,
        'subscriptionExpiry': subscriptionExpiry != null
            ? Timestamp.fromDate(subscriptionExpiry!)
            : null,
        'freePortuthamsUsed': freePortuthamsUsed,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'privacySettings': privacySettings,
        'fcmToken': fcmToken,
      };

  UserModel copyWith({
    String? uid,
    String? email,
    String? phone,
    String? displayName,
    String? photoUrl,
    String? role,
    bool? isProfileComplete,
    bool? isEmailVerified,
    bool? isPhoneVerified,
    bool? isBlocked,
    String? profileId,
    String? subscriptionPlan,
    DateTime? subscriptionExpiry,
    int? freePortuthamsUsed,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, bool>? privacySettings,
    String? fcmToken,
  }) =>
      UserModel(
        uid: uid ?? this.uid,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        role: role ?? this.role,
        isProfileComplete: isProfileComplete ?? this.isProfileComplete,
        isEmailVerified: isEmailVerified ?? this.isEmailVerified,
        isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
        isBlocked: isBlocked ?? this.isBlocked,
        profileId: profileId ?? this.profileId,
        subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
        subscriptionExpiry: subscriptionExpiry ?? this.subscriptionExpiry,
        freePortuthamsUsed: freePortuthamsUsed ?? this.freePortuthamsUsed,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        privacySettings: privacySettings ?? this.privacySettings,
        fcmToken: fcmToken ?? this.fcmToken,
      );

  bool get hasActiveSubscription {
    if (subscriptionPlan == null) return false;
    if (subscriptionExpiry == null) return false;
    return subscriptionExpiry!.isAfter(DateTime.now());
  }

  bool get isAdmin => role == 'admin';
  bool get isAstrologer => role == 'astrologer';
}
