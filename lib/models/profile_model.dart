import 'package:cloud_firestore/cloud_firestore.dart';

/// Safely coerce a dynamic value into a List<String>.
///
/// Tolerates a single String (e.g. a dropdown value like "Any" or "B.E"),
/// a real List, or null — preventing the
/// "type 'String' is not a subtype of type 'Iterable<dynamic>'" crash when a
/// scalar is stored where a list is expected.
List<String> toStringList(dynamic value) {
  if (value == null) return const [];
  if (value is List) return value.map((e) => e.toString()).toList();
  if (value is String) {
    return (value.isEmpty || value == 'Any') ? const [] : [value];
  }
  return const [];
}

class ProfileModel {
  final String id;
  final String userId;

  // Who Created
  final String profileCreatedBy;
  final String profileCreatedFor;

  // Personal Details
  final String fullName;
  final String gender;
  final DateTime dateOfBirth;
  final int age;
  final String height;
  final String weight;
  final String maritalStatus;
  final String religion;
  final String? caste;
  final String? subCaste;
  final String education;
  final String occupation;
  final String annualIncome;
  final String country;
  final String state;
  final String city;
  final String motherTongue;
  final String? aboutMe;

  // Photos
  final String? profilePhotoUrl;
  final List<String> additionalPhotos;

  // Horoscope
  final HoroscopeDetails horoscope;

  // Family
  final FamilyDetails family;

  // Partner Preferences
  final PartnerPreferences partnerPreferences;

  // Contact
  final ContactDetails contact;

  // Status
  final String status; // pending, approved, rejected, blocked
  final bool isVerified;
  final int reportCount;
  final int viewCount;
  final int interestCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFeatured;
  final bool isActive;

  const ProfileModel({
    required this.id,
    required this.userId,
    required this.profileCreatedBy,
    required this.profileCreatedFor,
    required this.fullName,
    required this.gender,
    required this.dateOfBirth,
    required this.age,
    required this.height,
    required this.weight,
    required this.maritalStatus,
    required this.religion,
    this.caste,
    this.subCaste,
    required this.education,
    required this.occupation,
    required this.annualIncome,
    required this.country,
    required this.state,
    required this.city,
    required this.motherTongue,
    this.aboutMe,
    this.profilePhotoUrl,
    this.additionalPhotos = const [],
    required this.horoscope,
    required this.family,
    required this.partnerPreferences,
    required this.contact,
    this.status = 'pending',
    this.isVerified = false,
    this.reportCount = 0,
    this.viewCount = 0,
    this.interestCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isFeatured = false,
    this.isActive = true,
  });

  factory ProfileModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProfileModel(
      id: doc.id,
      userId: d['userId'] ?? '',
      profileCreatedBy: d['profileCreatedBy'] ?? 'Myself',
      profileCreatedFor: d['profileCreatedFor'] ?? 'Myself',
      fullName: d['fullName'] ?? '',
      gender: d['gender'] ?? '',
      dateOfBirth: d['dateOfBirth'] != null
          ? (d['dateOfBirth'] as Timestamp).toDate()
          : DateTime.now(),
      age: d['age'] ?? 0,
      height: d['height'] ?? '',
      weight: d['weight'] ?? '',
      maritalStatus: d['maritalStatus'] ?? '',
      religion: d['religion'] ?? '',
      caste: d['caste'],
      subCaste: d['subCaste'],
      education: d['education'] ?? '',
      occupation: d['occupation'] ?? '',
      annualIncome: d['annualIncome'] ?? '',
      country: d['country'] ?? 'India',
      state: d['state'] ?? '',
      city: d['city'] ?? '',
      motherTongue: d['motherTongue'] ?? 'Tamil',
      aboutMe: d['aboutMe'],
      profilePhotoUrl: d['profilePhotoUrl'],
      additionalPhotos: List<String>.from(d['additionalPhotos'] ?? []),
      horoscope: HoroscopeDetails.fromMap(d['horoscope'] ?? {}),
      family: FamilyDetails.fromMap(d['family'] ?? {}),
      partnerPreferences: PartnerPreferences.fromMap(d['partnerPreferences'] ?? {}),
      contact: ContactDetails.fromMap(d['contact'] ?? {}),
      status: d['status'] ?? 'pending',
      isVerified: d['isVerified'] ?? false,
      reportCount: d['reportCount'] ?? 0,
      viewCount: d['viewCount'] ?? 0,
      interestCount: d['interestCount'] ?? 0,
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: d['updatedAt'] != null
          ? (d['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
      isFeatured: d['isFeatured'] ?? false,
      isActive: d['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'profileCreatedBy': profileCreatedBy,
        'profileCreatedFor': profileCreatedFor,
        'fullName': fullName,
        'gender': gender,
        'dateOfBirth': Timestamp.fromDate(dateOfBirth),
        'age': age,
        'height': height,
        'weight': weight,
        'maritalStatus': maritalStatus,
        'religion': religion,
        'caste': caste,
        'subCaste': subCaste,
        'education': education,
        'occupation': occupation,
        'annualIncome': annualIncome,
        'country': country,
        'state': state,
        'city': city,
        'motherTongue': motherTongue,
        'aboutMe': aboutMe,
        'profilePhotoUrl': profilePhotoUrl,
        'additionalPhotos': additionalPhotos,
        'horoscope': horoscope.toMap(),
        'family': family.toMap(),
        'partnerPreferences': partnerPreferences.toMap(),
        'contact': contact.toMap(),
        'status': status,
        'isVerified': isVerified,
        'reportCount': reportCount,
        'viewCount': viewCount,
        'interestCount': interestCount,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'isFeatured': isFeatured,
        'isActive': isActive,
      };

  // ── Convenience getters used by UI ────────────────────────────────────
  String get name => fullName;
  String get about => aboutMe ?? '';
  List<String> get photos {
    final list = <String>[];
    if (profilePhotoUrl != null) list.add(profilePhotoUrl!);
    list.addAll(additionalPhotos);
    return list;
  }
  HoroscopeDetails get horoscopeDetails => horoscope;

  // ── fromMap factory for profile creation flow ─────────────────────────
  factory ProfileModel.fromMap(Map<String, dynamic> d) {
    final horoMap = d['horoscopeDetails'] as Map<String, dynamic>? ?? {};
    final famMap = d['familyDetails'] as Map<String, dynamic>? ?? {};
    final prefMap = d['partnerPreferences'] as Map<String, dynamic>? ?? {};
    final contactMap = d['contactDetails'] as Map<String, dynamic>? ?? {};
    final photos = toStringList(d['photos']);
    return ProfileModel(
      id: d['id'] ?? '',
      userId: d['userId'] ?? '',
      profileCreatedBy: d['profileFor'] ?? 'Myself',
      profileCreatedFor: d['profileFor'] ?? 'Myself',
      fullName: d['name'] ?? '',
      gender: d['gender'] ?? '',
      dateOfBirth: d['dateOfBirth'] != null
          ? DateTime.tryParse(d['dateOfBirth']) ?? DateTime(1990)
          : DateTime(1990),
      age: d['age'] ?? 0,
      height: d['height'] ?? '',
      weight: d['weight'] ?? '',
      maritalStatus: d['maritalStatus'] ?? '',
      religion: d['religion'] ?? '',
      caste: d['caste'],
      subCaste: d['subCaste'],
      education: d['education'] ?? '',
      occupation: d['occupation'] ?? '',
      annualIncome: d['annualIncome'] ?? '',
      country: d['country'] ?? 'India',
      state: d['state'] ?? '',
      city: d['city'] ?? '',
      motherTongue: d['motherTongue'] ?? 'Tamil',
      aboutMe: d['about'],
      profilePhotoUrl: photos.isNotEmpty ? photos.first : null,
      additionalPhotos: photos.length > 1 ? photos.sublist(1) : [],
      horoscope: HoroscopeDetails.fromMap(horoMap),
      family: FamilyDetails.fromMap(famMap),
      partnerPreferences: PartnerPreferences.fromMap(prefMap),
      contact: ContactDetails.fromMap(contactMap),
      status: d['status'] ?? 'pending',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  ProfileModel copyWith({
    String? fullName,
    String? profilePhotoUrl,
    List<String>? additionalPhotos,
    HoroscopeDetails? horoscope,
    FamilyDetails? family,
    PartnerPreferences? partnerPreferences,
    ContactDetails? contact,
    String? status,
    bool? isVerified,
    bool? isFeatured,
    bool? isActive,
    int? reportCount,
    int? viewCount,
    int? interestCount,
    DateTime? updatedAt,
  }) =>
      ProfileModel(
        id: id,
        userId: userId,
        profileCreatedBy: profileCreatedBy,
        profileCreatedFor: profileCreatedFor,
        fullName: fullName ?? this.fullName,
        gender: gender,
        dateOfBirth: dateOfBirth,
        age: age,
        height: height,
        weight: weight,
        maritalStatus: maritalStatus,
        religion: religion,
        caste: caste,
        subCaste: subCaste,
        education: education,
        occupation: occupation,
        annualIncome: annualIncome,
        country: country,
        state: state,
        city: city,
        motherTongue: motherTongue,
        aboutMe: aboutMe,
        profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
        additionalPhotos: additionalPhotos ?? this.additionalPhotos,
        horoscope: horoscope ?? this.horoscope,
        family: family ?? this.family,
        partnerPreferences: partnerPreferences ?? this.partnerPreferences,
        contact: contact ?? this.contact,
        status: status ?? this.status,
        isVerified: isVerified ?? this.isVerified,
        reportCount: reportCount ?? this.reportCount,
        viewCount: viewCount ?? this.viewCount,
        interestCount: interestCount ?? this.interestCount,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isFeatured: isFeatured ?? this.isFeatured,
        isActive: isActive ?? this.isActive,
      );
}

class HoroscopeDetails {
  final String rasi;
  final String nakshatra;
  final String lagnam;
  final String dasaBalance;
  final String yogam;
  final String karanam;
  final String moonSign;
  final String sunSign;
  final String birthTime;
  final String birthPlace;
  final bool isAutoGenerated;
  final bool isUserEdited;
  final bool isAstrologerVerified;
  final String? horoscopePdfUrl;
  final List<String> horoscopeImages;

  const HoroscopeDetails({
    required this.rasi,
    required this.nakshatra,
    required this.lagnam,
    required this.dasaBalance,
    required this.yogam,
    required this.karanam,
    required this.moonSign,
    required this.sunSign,
    required this.birthTime,
    required this.birthPlace,
    this.isAutoGenerated = true,
    this.isUserEdited = false,
    this.isAstrologerVerified = false,
    this.horoscopePdfUrl,
    this.horoscopeImages = const [],
  });

  factory HoroscopeDetails.fromMap(Map<String, dynamic> map) => HoroscopeDetails(
        rasi: map['rasi'] ?? '',
        nakshatra: map['nakshatra'] ?? '',
        lagnam: map['lagnam'] ?? '',
        dasaBalance: map['dasaBalance'] ?? '',
        yogam: map['yogam'] ?? '',
        karanam: map['karanam'] ?? '',
        moonSign: map['moonSign'] ?? '',
        sunSign: map['sunSign'] ?? '',
        birthTime: map['birthTime'] ?? '',
        birthPlace: map['birthPlace'] ?? '',
        isAutoGenerated: map['isAutoGenerated'] ?? true,
        isUserEdited: map['isUserEdited'] ?? false,
        isAstrologerVerified: map['isAstrologerVerified'] ?? false,
        horoscopePdfUrl: map['horoscopePdfUrl'],
        horoscopeImages: toStringList(map['horoscopeImages']),
      );

  Map<String, dynamic> toMap() => {
        'rasi': rasi,
        'nakshatra': nakshatra,
        'lagnam': lagnam,
        'dasaBalance': dasaBalance,
        'yogam': yogam,
        'karanam': karanam,
        'moonSign': moonSign,
        'sunSign': sunSign,
        'birthTime': birthTime,
        'birthPlace': birthPlace,
        'isAutoGenerated': isAutoGenerated,
        'isUserEdited': isUserEdited,
        'isAstrologerVerified': isAstrologerVerified,
        'horoscopePdfUrl': horoscopePdfUrl,
        'horoscopeImages': horoscopeImages,
      };

  String get badgeText {
    if (isAstrologerVerified) return 'Astrologer Verified';
    if (isUserEdited) return 'User Edited';
    return 'Auto Generated';
  }
}

class FamilyDetails {
  final String fatherName;
  final String fatherOccupation;
  final String motherName;
  final String motherOccupation;
  final int brothersCount;
  final int sistersCount;
  final String familyType;
  final String familyStatus;

  const FamilyDetails({
    required this.fatherName,
    required this.fatherOccupation,
    required this.motherName,
    required this.motherOccupation,
    required this.brothersCount,
    required this.sistersCount,
    required this.familyType,
    required this.familyStatus,
  });

  factory FamilyDetails.fromMap(Map<String, dynamic> map) => FamilyDetails(
        fatherName: map['fatherName'] ?? '',
        fatherOccupation: map['fatherOccupation'] ?? '',
        motherName: map['motherName'] ?? '',
        motherOccupation: map['motherOccupation'] ?? '',
        brothersCount: map['brothersCount'] ?? 0,
        sistersCount: map['sistersCount'] ?? 0,
        familyType: map['familyType'] ?? '',
        familyStatus: map['familyStatus'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'fatherName': fatherName,
        'fatherOccupation': fatherOccupation,
        'motherName': motherName,
        'motherOccupation': motherOccupation,
        'brothersCount': brothersCount,
        'sistersCount': sistersCount,
        'familyType': familyType,
        'familyStatus': familyStatus,
      };
}

class PartnerPreferences {
  final int minAge;
  final int maxAge;
  final String minHeight;
  final String maxHeight;
  final List<String> education;
  final List<String> occupation;
  final String income;
  final String religion;
  final String? caste;
  final String? city;
  final String? rasi;
  final String? nakshatra;

  const PartnerPreferences({
    this.minAge = 18,
    this.maxAge = 40,
    this.minHeight = "5'0\"",
    this.maxHeight = "5'10\"",
    this.education = const [],
    this.occupation = const [],
    this.income = 'Any',
    this.religion = 'Any',
    this.caste,
    this.city,
    this.rasi,
    this.nakshatra,
  });

  factory PartnerPreferences.fromMap(Map<String, dynamic> map) => PartnerPreferences(
        minAge: map['minAge'] ?? 18,
        maxAge: map['maxAge'] ?? 40,
        minHeight: map['minHeight'] ?? "5'0\"",
        maxHeight: map['maxHeight'] ?? "5'10\"",
        education: toStringList(map['education']),
        occupation: toStringList(map['occupation']),
        income: map['income'] ?? 'Any',
        religion: map['religion'] ?? 'Any',
        caste: map['caste'],
        city: map['city'],
        rasi: map['rasi'],
        nakshatra: map['nakshatra'],
      );

  Map<String, dynamic> toMap() => {
        'minAge': minAge,
        'maxAge': maxAge,
        'minHeight': minHeight,
        'maxHeight': maxHeight,
        'education': education,
        'occupation': occupation,
        'income': income,
        'religion': religion,
        'caste': caste,
        'city': city,
        'rasi': rasi,
        'nakshatra': nakshatra,
      };
}

class ContactDetails {
  final String contactPersonName;
  final String relationship;
  final String mobileNumber;
  final String? whatsappNumber;

  const ContactDetails({
    required this.contactPersonName,
    required this.relationship,
    required this.mobileNumber,
    this.whatsappNumber,
  });

  factory ContactDetails.fromMap(Map<String, dynamic> map) => ContactDetails(
        contactPersonName: map['contactPersonName'] ?? '',
        relationship: map['relationship'] ?? '',
        mobileNumber: map['mobileNumber'] ?? '',
        whatsappNumber: map['whatsappNumber'],
      );

  Map<String, dynamic> toMap() => {
        'contactPersonName': contactPersonName,
        'relationship': relationship,
        'mobileNumber': mobileNumber,
        'whatsappNumber': whatsappNumber,
      };
}
