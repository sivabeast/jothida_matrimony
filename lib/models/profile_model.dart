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
  final String? religionId;
  final String? caste;
  final String? casteId;
  final String? subCaste;
  final String? subCasteId;
  final String education;
  final String occupation;
  final String annualIncome;
  final String country;
  final String state;
  final String stateId;
  final String district;
  final String districtId;
  final String city;
  final String cityId;
  final double? latitude;
  final double? longitude;
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
  final bool isMarried; // true once the user marks themselves as married

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
    this.religionId,
    this.caste,
    this.casteId,
    this.subCaste,
    this.subCasteId,
    required this.education,
    required this.occupation,
    required this.annualIncome,
    required this.country,
    required this.state,
    this.stateId = '',
    this.district = '',
    this.districtId = '',
    required this.city,
    this.cityId = '',
    this.latitude,
    this.longitude,
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
    this.isMarried = false,
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
      religionId: d['religionId'],
      caste: d['caste'],
      casteId: d['casteId'],
      subCaste: d['subCaste'],
      subCasteId: d['subCasteId'],
      education: d['education'] ?? '',
      occupation: d['occupation'] ?? '',
      annualIncome: d['annualIncome'] ?? '',
      country: d['country'] ?? 'India',
      state: d['state'] ?? d['stateName'] ?? '',
      stateId: d['stateId'] ?? '',
      district: d['district'] ?? d['districtName'] ?? '',
      districtId: d['districtId'] ?? '',
      city: d['city'] ?? d['cityName'] ?? '',
      cityId: d['cityId'] ?? '',
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
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
      isMarried: d['isMarried'] ?? false,
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
        'religionId': religionId,
        'caste': caste,
        'casteId': casteId,
        'subCaste': subCaste,
        'subCasteId': subCasteId,
        'education': education,
        'occupation': occupation,
        'annualIncome': annualIncome,
        'country': country,
        // Both human-readable names and stable master-data ids are persisted.
        'state': state,
        'stateId': stateId,
        'stateName': state,
        'district': district,
        'districtId': districtId,
        'districtName': district,
        'city': city,
        'cityId': cityId,
        'cityName': city,
        'latitude': latitude,
        'longitude': longitude,
        'motherTongue': motherTongue,
        'aboutMe': aboutMe,
        'profilePhotoUrl': profilePhotoUrl,
        'additionalPhotos': additionalPhotos,
        'horoscope': horoscope.toMap(),
        'family': family.toMap(),
        'partnerPreferences': partnerPreferences.toMap(),
        // Contact details are intentionally NOT written into the public profile
        // document — they are stored in the access-gated `contacts/{userId}`
        // collection and unlock only after a mutually-accepted interest.
        // (See FirestoreService.createProfile / saveContact.)
        'status': status,
        'isVerified': isVerified,
        'reportCount': reportCount,
        'viewCount': viewCount,
        'interestCount': interestCount,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'isFeatured': isFeatured,
        'isActive': isActive,
        'isMarried': isMarried,
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
      religionId: d['religionId'],
      caste: d['caste'],
      casteId: d['casteId'],
      subCaste: d['subCaste'],
      subCasteId: d['subCasteId'],
      education: d['education'] ?? '',
      occupation: d['occupation'] ?? '',
      annualIncome: d['annualIncome'] ?? '',
      country: d['country'] ?? 'India',
      state: d['state'] ?? d['stateName'] ?? '',
      stateId: d['stateId'] ?? '',
      district: d['district'] ?? d['districtName'] ?? '',
      districtId: d['districtId'] ?? '',
      city: d['city'] ?? d['cityName'] ?? '',
      cityId: d['cityId'] ?? '',
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
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
    String? gender,
    DateTime? dateOfBirth,
    int? age,
    String? height,
    String? weight,
    String? maritalStatus,
    String? religion,
    String? religionId,
    String? caste,
    String? casteId,
    String? subCaste,
    String? subCasteId,
    String? education,
    String? occupation,
    String? annualIncome,
    String? country,
    String? state,
    String? stateId,
    String? district,
    String? districtId,
    String? city,
    String? cityId,
    double? latitude,
    double? longitude,
    String? motherTongue,
    String? aboutMe,
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
    bool? isMarried,
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
        gender: gender ?? this.gender,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        age: age ?? this.age,
        height: height ?? this.height,
        weight: weight ?? this.weight,
        maritalStatus: maritalStatus ?? this.maritalStatus,
        religion: religion ?? this.religion,
        religionId: religionId ?? this.religionId,
        caste: caste ?? this.caste,
        casteId: casteId ?? this.casteId,
        subCaste: subCaste ?? this.subCaste,
        subCasteId: subCasteId ?? this.subCasteId,
        education: education ?? this.education,
        occupation: occupation ?? this.occupation,
        annualIncome: annualIncome ?? this.annualIncome,
        country: country ?? this.country,
        state: state ?? this.state,
        stateId: stateId ?? this.stateId,
        district: district ?? this.district,
        districtId: districtId ?? this.districtId,
        city: city ?? this.city,
        cityId: cityId ?? this.cityId,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        motherTongue: motherTongue ?? this.motherTongue,
        aboutMe: aboutMe ?? this.aboutMe,
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
        isMarried: isMarried ?? this.isMarried,
      );

  /// Returns a copy with the primary profile photo set to [url] (or cleared
  /// when null). [copyWith] can't clear a non-null field via `?? this.x`, so
  /// this is the dedicated path for setting/removing the photo.
  ProfileModel withProfilePhoto(String? url) => ProfileModel(
        id: id,
        userId: userId,
        profileCreatedBy: profileCreatedBy,
        profileCreatedFor: profileCreatedFor,
        fullName: fullName,
        gender: gender,
        dateOfBirth: dateOfBirth,
        age: age,
        height: height,
        weight: weight,
        maritalStatus: maritalStatus,
        religion: religion,
        religionId: religionId,
        caste: caste,
        casteId: casteId,
        subCaste: subCaste,
        subCasteId: subCasteId,
        education: education,
        occupation: occupation,
        annualIncome: annualIncome,
        country: country,
        state: state,
        district: district,
        city: city,
        latitude: latitude,
        longitude: longitude,
        motherTongue: motherTongue,
        aboutMe: aboutMe,
        profilePhotoUrl: url,
        additionalPhotos: additionalPhotos,
        horoscope: horoscope,
        family: family,
        partnerPreferences: partnerPreferences,
        contact: contact,
        status: status,
        isVerified: isVerified,
        reportCount: reportCount,
        viewCount: viewCount,
        interestCount: interestCount,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        isFeatured: isFeatured,
        isActive: isActive,
        isMarried: isMarried,
      );
}

class HoroscopeDetails {
  final String rasi;
  final String nakshatra;
  final String lagnam;
  final String dosham;
  final String dasaBalance;
  final String yogam;
  final String karanam;
  final String moonSign;
  final String sunSign;
  final String birthTime;
  final String birthPlace;
  // 'city' when birthPlace is a master-data city, 'custom' when the user typed
  // a place via the "Others" option.
  final String birthPlaceType;
  // Geocoded birth coordinates used by the Vedic calculation engine. 0/0 means
  // "not yet calculated".
  final double latitude;
  final double longitude;
  // True once Rasi/Nakshatra/Lagnam have been generated by the Vedic engine
  // from the birth details.
  final bool horoscopeGenerated;
  // The engine-calculated values, always preserved even when the user manually
  // overrides. The effective values live in [rasi]/[nakshatra]/[lagnam].
  final String generatedRasi;
  final String generatedNakshatra;
  final String generatedLagnam;
  // When true the user has manually chosen Rasi/Nakshatra/Lagnam, which then
  // replace the generated values as the effective ones.
  final bool overrideEnabled;
  final bool isAutoGenerated;
  final bool isUserEdited;
  final bool isAstrologerVerified;
  final String? horoscopePdfUrl;
  final List<String> horoscopeImages;

  const HoroscopeDetails({
    required this.rasi,
    required this.nakshatra,
    required this.lagnam,
    this.dosham = '',
    required this.dasaBalance,
    required this.yogam,
    required this.karanam,
    required this.moonSign,
    required this.sunSign,
    required this.birthTime,
    required this.birthPlace,
    this.birthPlaceType = 'city',
    this.latitude = 0,
    this.longitude = 0,
    this.horoscopeGenerated = false,
    this.generatedRasi = '',
    this.generatedNakshatra = '',
    this.generatedLagnam = '',
    this.overrideEnabled = false,
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
        dosham: map['dosham'] ?? '',
        dasaBalance: map['dasaBalance'] ?? '',
        yogam: map['yogam'] ?? '',
        karanam: map['karanam'] ?? '',
        moonSign: map['moonSign'] ?? '',
        sunSign: map['sunSign'] ?? '',
        birthTime: map['birthTime'] ?? '',
        birthPlace: map['birthPlace'] ?? '',
        birthPlaceType: map['birthPlaceType'] ?? 'city',
        latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
        horoscopeGenerated: map['horoscopeGenerated'] ?? false,
        generatedRasi: map['generatedRasi'] ?? '',
        generatedNakshatra: map['generatedNakshatra'] ?? '',
        generatedLagnam: map['generatedLagnam'] ?? '',
        overrideEnabled: map['overrideEnabled'] ?? false,
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
        'dosham': dosham,
        'dasaBalance': dasaBalance,
        'yogam': yogam,
        'karanam': karanam,
        'moonSign': moonSign,
        'sunSign': sunSign,
        'birthTime': birthTime,
        'birthPlace': birthPlace,
        'birthPlaceType': birthPlaceType,
        'latitude': latitude,
        'longitude': longitude,
        'horoscopeGenerated': horoscopeGenerated,
        'generatedRasi': generatedRasi,
        'generatedNakshatra': generatedNakshatra,
        'generatedLagnam': generatedLagnam,
        'overrideEnabled': overrideEnabled,
        'isAutoGenerated': isAutoGenerated,
        'isUserEdited': isUserEdited,
        'isAstrologerVerified': isAstrologerVerified,
        'horoscopePdfUrl': horoscopePdfUrl,
        'horoscopeImages': horoscopeImages,
      };

  HoroscopeDetails copyWith({
    String? rasi,
    String? nakshatra,
    String? lagnam,
    String? dosham,
    String? dasaBalance,
    String? yogam,
    String? karanam,
    String? moonSign,
    String? sunSign,
    String? birthTime,
    String? birthPlace,
    String? birthPlaceType,
    double? latitude,
    double? longitude,
    bool? horoscopeGenerated,
    String? generatedRasi,
    String? generatedNakshatra,
    String? generatedLagnam,
    bool? overrideEnabled,
    bool? isUserEdited,
  }) =>
      HoroscopeDetails(
        rasi: rasi ?? this.rasi,
        nakshatra: nakshatra ?? this.nakshatra,
        lagnam: lagnam ?? this.lagnam,
        dosham: dosham ?? this.dosham,
        dasaBalance: dasaBalance ?? this.dasaBalance,
        yogam: yogam ?? this.yogam,
        karanam: karanam ?? this.karanam,
        moonSign: moonSign ?? this.moonSign,
        sunSign: sunSign ?? this.sunSign,
        birthTime: birthTime ?? this.birthTime,
        birthPlace: birthPlace ?? this.birthPlace,
        birthPlaceType: birthPlaceType ?? this.birthPlaceType,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        horoscopeGenerated: horoscopeGenerated ?? this.horoscopeGenerated,
        generatedRasi: generatedRasi ?? this.generatedRasi,
        generatedNakshatra: generatedNakshatra ?? this.generatedNakshatra,
        generatedLagnam: generatedLagnam ?? this.generatedLagnam,
        overrideEnabled: overrideEnabled ?? this.overrideEnabled,
        isAutoGenerated: isAutoGenerated,
        isUserEdited: isUserEdited ?? this.isUserEdited,
        isAstrologerVerified: isAstrologerVerified,
        horoscopePdfUrl: horoscopePdfUrl,
        horoscopeImages: horoscopeImages,
      );

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
  final String? religionId;
  final String? caste;
  final String? casteId;
  final String? city;
  final String? rasi;
  final String? nakshatra;
  // Extended preference fields (Partner Preferences screen).
  final String maritalStatus; // 'Any' or a specific status
  final String? state;
  final String? country;
  final String motherTongue; // language preference; 'Any' or a language
  final bool horoscopeMatchRequired;

  const PartnerPreferences({
    this.minAge = 18,
    this.maxAge = 40,
    this.minHeight = "5'0\"",
    this.maxHeight = "5'10\"",
    this.education = const [],
    this.occupation = const [],
    this.income = 'Any',
    this.religion = 'Any',
    this.religionId,
    this.caste,
    this.casteId,
    this.city,
    this.rasi,
    this.nakshatra,
    this.maritalStatus = 'Any',
    this.state,
    this.country,
    this.motherTongue = 'Any',
    this.horoscopeMatchRequired = true,
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
        religionId: map['religionId'],
        caste: map['caste'],
        casteId: map['casteId'],
        city: map['city'],
        rasi: map['rasi'],
        nakshatra: map['nakshatra'],
        maritalStatus: map['maritalStatus'] ?? 'Any',
        state: map['state'],
        country: map['country'],
        motherTongue: map['motherTongue'] ?? 'Any',
        horoscopeMatchRequired: map['horoscopeMatchRequired'] ?? true,
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
        'religionId': religionId,
        'caste': caste,
        'casteId': casteId,
        'city': city,
        'rasi': rasi,
        'nakshatra': nakshatra,
        'maritalStatus': maritalStatus,
        'state': state,
        'country': country,
        'motherTongue': motherTongue,
        'horoscopeMatchRequired': horoscopeMatchRequired,
      };

  PartnerPreferences copyWith({
    int? minAge,
    int? maxAge,
    String? minHeight,
    String? maxHeight,
    List<String>? education,
    List<String>? occupation,
    String? income,
    String? religion,
    String? religionId,
    String? caste,
    String? casteId,
    String? city,
    String? rasi,
    String? nakshatra,
    String? maritalStatus,
    String? state,
    String? country,
    String? motherTongue,
    bool? horoscopeMatchRequired,
  }) =>
      PartnerPreferences(
        minAge: minAge ?? this.minAge,
        maxAge: maxAge ?? this.maxAge,
        minHeight: minHeight ?? this.minHeight,
        maxHeight: maxHeight ?? this.maxHeight,
        education: education ?? this.education,
        occupation: occupation ?? this.occupation,
        income: income ?? this.income,
        religion: religion ?? this.religion,
        religionId: religionId ?? this.religionId,
        caste: caste ?? this.caste,
        casteId: casteId ?? this.casteId,
        city: city ?? this.city,
        rasi: rasi ?? this.rasi,
        nakshatra: nakshatra ?? this.nakshatra,
        maritalStatus: maritalStatus ?? this.maritalStatus,
        state: state ?? this.state,
        country: country ?? this.country,
        motherTongue: motherTongue ?? this.motherTongue,
        horoscopeMatchRequired:
            horoscopeMatchRequired ?? this.horoscopeMatchRequired,
      );
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
