import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/data/education_catalog.dart';
import '../core/data/occupation_catalog.dart';

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

/// The ONLY four privacy switches the app offers (§12), and the rule that
/// every one of them defaults to **OFF**.
///
/// Nothing is hidden until the member explicitly turns a switch on: a brand-new
/// profile is fully visible, and a legacy document missing these keys is read as
/// "nothing hidden" rather than silently hiding data the member never asked to
/// hide. (This reverses the earlier default-hidden behaviour, which switched
/// every option on for everybody.)
///
/// The retired switches (`hideAddress`, `hideFamilyDetails`,
/// `hideAdditionalPhotos`) are deliberately absent: the app never collects an
/// address, family details are not hideable, and additional photos no longer
/// exist. Legacy values for those keys are dropped on read.
class ProfilePrivacy {
  ProfilePrivacy._();

  static const String phone = 'hidePhone';
  static const String salary = 'hideSalary';
  static const String horoscope = 'hideHoroscope';
  static const String photo = 'hidePhoto';

  /// The four keys, in the order the Privacy Settings screen lists them.
  static const List<String> keys = [phone, salary, horoscope, photo];

  /// Default state: every switch OFF (§12). Applied to brand-new profiles and
  /// used to backfill any key a document is missing.
  static const Map<String, bool> defaults = {
    phone: false,
    salary: false,
    horoscope: false,
    photo: false,
  };

  /// Reads a stored map defensively: coerces string/number values, ignores the
  /// retired keys and backfills the missing ones with "not hidden".
  static Map<String, bool> fromMap(dynamic raw) {
    final out = Map<String, bool>.from(defaults);
    if (raw is Map) {
      for (final key in keys) {
        if (raw.containsKey(key)) out[key] = _boolOf(raw[key]);
      }
      // Legacy alias: the photo switch used to be called hideAdditionalPhotos
      // when a member could upload several photos.
      if (!raw.containsKey(photo) && raw.containsKey('hideAdditionalPhotos')) {
        out[photo] = _boolOf(raw['hideAdditionalPhotos']);
      }
    }
    return out;
  }

  /// Whether [key] is hidden. An absent / unparseable value counts as NOT
  /// hidden — the switch is only on when the member turned it on (§12).
  static bool isHidden(Map<String, bool> settings, String key) =>
      settings[key] ?? false;

  static bool _boolOf(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return false; // unknown → not hidden
  }
}

class ProfileModel {
  final String id;
  final String userId;

  // Who Created
  final String profileCreatedBy;
  final String profileCreatedFor;

  // Personal Details
  final String fullName;
  /// Optional Tamil-script name, shown when the app language is Tamil (§10).
  /// Mirrors the website's `fullNameTamil`; storage of [fullName] stays the
  /// canonical value used for matching / search.
  final String fullNameTamil;
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

  /// Education LEVEL — one of [EducationCatalog.levels] (§3). The grouping
  /// layer above [education]; empty on documents written before the hierarchy
  /// existed, in which case [EducationCatalog.levelForDegree] recovers it.
  final String educationLevel;

  /// The member's PRIMARY qualification. Storage is unchanged from the
  /// flat-list era (and identical to the website's `education`), so matching,
  /// filters and the admin panel keep working. When several degrees are held
  /// this mirrors the first entry of [displayDegrees].
  final String education;

  /// EVERY qualification the member holds (§4) — B.Sc *and* MBA *and* M.Phil.
  /// Empty on documents written before multi-degree support, where [education]
  /// alone is the whole answer; [allDegrees] papers over that difference.
  final List<String> degrees;

  /// The one or two degrees chosen for the profile card (§4).
  ///
  /// Only asked for when the member holds THREE or more — with one or two
  /// there is nothing to choose, so the wizard shows them both and leaves this
  /// empty. [profileDegrees] resolves it either way.
  final List<String> displayDegrees;

  /// Employment STATUS — one of [OccupationCatalog.statuses] (§5). Empty on
  /// legacy documents; [OccupationCatalog.statusForOccupation] recovers it.
  final String employmentStatus;
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

  // Physical
  final String physicalStatus;

  // Marital extras (only relevant when divorced / widow / widower)
  final int childrenCount;
  final String? childrenLivingStatus;

  // Religious extras
  final String gothram;
  final String kuladeivam;

  // Education & career extras
  final String employmentType; // Private / Government / Business / Self Employed
  final String? collegeName;
  final String? companyName;
  final String? workLocation;
  /// Course / degree name — shown & required only for Student occupation
  /// (mirrors the website Career step). Optional otherwise.
  final String? courseDegree;

  // Location extras
  final String? nativePlace;
  final String? citizenship;

  // Lifestyle & habits
  final LifestyleDetails lifestyle;

  // Photo — EXACTLY ONE per member (§1). The image is always a 1:1 square
  // produced by the mandatory crop screen; uploading a new one REPLACES this
  // url. Multi-photo support (the old `additionalPhotos` list) was removed
  // completely, so there is no gallery anywhere in the app.
  final String? profilePhotoUrl;

  /// What this member keeps hidden from other members (§12). Only four
  /// switches exist — `hidePhone`, `hideSalary`, `hideHoroscope`,
  /// `hidePhoto` — and ALL default to OFF (`false`): nothing is hidden until
  /// the member turns a switch on themselves, from Privacy Settings.
  ///
  /// Stored on the PUBLIC profile document (like `contactPrivacy`) so a viewer
  /// can honour it without reading the owner's private `users/{uid}` record.
  final Map<String, bool> privacySettings;

  // Horoscope
  final HoroscopeDetails horoscope;

  // Family
  final FamilyDetails family;

  // Partner Preferences
  final PartnerPreferences partnerPreferences;

  // Contact
  final ContactDetails contact;
  /// How this member shares contact info (§17/§18): 'private' (default — shown
  /// only after a mutually-accepted interest) or 'public' (any signed-in viewer
  /// can see it). Stored on the PUBLIC profile doc so both the UI and the
  /// `contacts/{userId}` read rule can honor it without extra lookups.
  final String contactPrivacy;

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
  // Test/seed profile flag. Dummy profiles are created by the admin "Test Data"
  // tool and can be bulk-deleted from there (or filtered by `isDummy == true`
  // in the Firebase console). Real user profiles never set this.
  final bool isDummy;

  const ProfileModel({
    required this.id,
    required this.userId,
    required this.profileCreatedBy,
    required this.profileCreatedFor,
    required this.fullName,
    this.fullNameTamil = '',
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
    this.educationLevel = '',
    required this.education,
    this.degrees = const [],
    this.displayDegrees = const [],
    this.employmentStatus = '',
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
    this.physicalStatus = '',
    this.childrenCount = 0,
    this.childrenLivingStatus,
    this.gothram = '',
    this.kuladeivam = '',
    this.employmentType = '',
    this.collegeName,
    this.companyName,
    this.workLocation,
    this.courseDegree,
    this.nativePlace,
    this.citizenship,
    this.lifestyle = const LifestyleDetails(),
    this.profilePhotoUrl,
    this.privacySettings = ProfilePrivacy.defaults,
    required this.horoscope,
    required this.family,
    required this.partnerPreferences,
    required this.contact,
    this.contactPrivacy = 'private',
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
    this.isDummy = false,
  });

  factory ProfileModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProfileModel(
      id: doc.id,
      userId: d['userId'] ?? '',
      profileCreatedBy: d['profileCreatedBy'] ?? 'Myself',
      profileCreatedFor: d['profileCreatedFor'] ?? 'Myself',
      fullName: d['fullName'] ?? '',
      fullNameTamil: d['fullNameTamil'] ?? '',
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
      educationLevel: d['educationLevel'] ?? '',
      education: d['education'] ?? '',
      degrees: toStringList(d['degrees']),
      displayDegrees: toStringList(d['displayDegrees']),
      employmentStatus: d['employmentStatus'] ?? '',
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
      physicalStatus: d['physicalStatus'] ?? '',
      childrenCount: d['childrenCount'] ?? 0,
      childrenLivingStatus: d['childrenLivingStatus'],
      gothram: d['gothram'] ?? '',
      kuladeivam: d['kuladeivam'] ?? '',
      employmentType: d['employmentType'] ?? '',
      collegeName: d['collegeName'],
      companyName: d['companyName'],
      workLocation: d['workLocation'],
      courseDegree: d['courseDegree'],
      nativePlace: d['nativePlace'],
      citizenship: d['citizenship'],
      lifestyle: LifestyleDetails.fromMap(d['lifestyle'] ?? {}),
      profilePhotoUrl: d['profilePhotoUrl'],
      privacySettings: ProfilePrivacy.fromMap(d['privacySettings']),
      horoscope: HoroscopeDetails.fromMap(d['horoscope'] ?? {}),
      family: FamilyDetails.fromMap(d['family'] ?? {}),
      partnerPreferences: PartnerPreferences.fromMap(d['partnerPreferences'] ?? {}),
      contact: ContactDetails.fromMap(d['contact'] ?? {}),
      contactPrivacy: d['contactPrivacy'] ?? 'private',
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
      isDummy: d['isDummy'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'profileCreatedBy': profileCreatedBy,
        'profileCreatedFor': profileCreatedFor,
        'fullName': fullName,
        'fullNameTamil': fullNameTamil,
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
        'educationLevel': educationLevel,
        'education': education,
        'degrees': degrees,
        'displayDegrees': displayDegrees,
        'employmentStatus': employmentStatus,
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
        'physicalStatus': physicalStatus,
        'childrenCount': childrenCount,
        'childrenLivingStatus': childrenLivingStatus,
        'gothram': gothram,
        'kuladeivam': kuladeivam,
        'employmentType': employmentType,
        'collegeName': collegeName,
        'companyName': companyName,
        'workLocation': workLocation,
        'courseDegree': courseDegree,
        'nativePlace': nativePlace,
        'citizenship': citizenship,
        'lifestyle': lifestyle.toMap(),
        'profilePhotoUrl': profilePhotoUrl,
        // Written as an empty list so any legacy extra photos are cleared the
        // next time the profile is saved — multi-photo support is gone (§1).
        'additionalPhotos': const <String>[],
        'privacySettings': privacySettings,
        'horoscope': horoscope.toMap(),
        'family': family.toMap(),
        'partnerPreferences': partnerPreferences.toMap(),
        // Contact details are intentionally NOT written into the public profile
        // document — they are stored in the access-gated `contacts/{userId}`
        // collection and unlock only after a mutually-accepted interest.
        // (See FirestoreService.createProfile / saveContact.)
        // The privacy CHOICE, however, is a public setting so viewers and the
        // contacts read rule can honor it (§17/§18).
        'contactPrivacy': contactPrivacy,
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
        'isDummy': isDummy,
      };

  // ── Convenience getters used by UI ────────────────────────────────────
  String get name => fullName;

  /// The name to DISPLAY for the given language: the Tamil-script name in Tamil
  /// mode when one was entered, otherwise the canonical [fullName] (§10).
  String displayName(bool tamil) =>
      tamil && fullNameTamil.trim().isNotEmpty ? fullNameTamil : fullName;

  // ── Education / career hierarchy (§13) ───────────────────────────────────
  //
  // The stored level/status is used when present; otherwise it is recovered
  // from the flat value, so a profile written before the hierarchy existed
  // still renders "Level → Course" and "Status → Sector → Occupation".

  String get effectiveEducationLevel {
    final stored = educationLevel.trim();
    if (stored.isNotEmpty) {
      // Normalises the retired "Doctorate" bucket onto Ph.D (§3).
      return EducationCatalog.canonicalLevel(stored) ?? stored;
    }
    return EducationCatalog.levelForDegree(
            allDegrees.isEmpty ? education : allDegrees.first) ??
        '';
  }

  String get effectiveEmploymentStatus => employmentStatus.trim().isNotEmpty
      ? employmentStatus.trim()
      : (OccupationCatalog.statusForOccupation(occupation,
              employmentType: employmentType) ??
          '');

  /// The employment TYPE (§5, field 2) — "sector" in the pre-§5 vocabulary.
  String get effectiveSector =>
      OccupationCatalog.typeForOccupation(occupation,
          employmentType: employmentType) ??
      '';

  /// Every qualification this member holds (§4), oldest storage format
  /// included: a profile written before multi-degree support only has
  /// [education], and one written after has the full [degrees] list.
  List<String> get allDegrees {
    if (degrees.isNotEmpty) return degrees;
    final single = education.trim();
    return single.isEmpty ? const [] : [single];
  }

  /// The one or two qualifications that belong on the profile card (§4).
  ///
  ///  * one or two held  → show them, nothing to choose;
  ///  * three or more    → show the member's [displayDegrees] pick;
  ///  * three or more but nothing picked (an older profile, or a draft that
  ///    skipped the question) → fall back to the first two, so a card is never
  ///    blank just because a choice was not recorded.
  List<String> get profileDegrees {
    final all = allDegrees;
    if (all.length <= 2) return all;
    final picked = [for (final d in displayDegrees) if (all.contains(d)) d];
    if (picked.isNotEmpty) return picked.take(2).toList();
    return all.take(2).toList();
  }

  /// "UG · B.E, MBA" — the education LEVEL followed by the qualifications
  /// chosen for the card. [localize] is normally `context.localizeValue`, which
  /// renders a degree as "இளங்கலை பொறியியல் (B.E)" in Tamil.
  String educationDisplay(String Function(String) localize) {
    final level = effectiveEducationLevel;
    final shown = [for (final d in profileDegrees) localize(d)];
    if (level.isEmpty) return shown.join(', ');
    if (shown.isEmpty ||
        (shown.length == 1 &&
            profileDegrees.first.toLowerCase() == level.toLowerCase())) {
      return localize(level);
    }
    return '${localize(level)} · ${shown.join(', ')}';
  }

  /// "Employed · Private · Software Engineer" — status, type and occupation,
  /// each rendered through [localize]. Statuses with no occupation of their own
  /// (Student / Job Seeker / Homemaker / Retired / Others) render as just the
  /// status.
  String occupationDisplay(String Function(String) localize) {
    final status = effectiveEmploymentStatus;
    final occ = occupation.trim();
    if (status.isEmpty) return localize(occ);
    final parts = <String>[localize(status)];
    if (OccupationCatalog.statusHasOccupation(status)) {
      final type = effectiveSector;
      if (type.isNotEmpty) parts.add(localize(type));
      if (occ.isNotEmpty) parts.add(localize(occ));
    }
    return parts.join(' · ');
  }

  /// True when this member chose to share contact publicly (§17/§18) — any
  /// signed-in viewer may see it, without a mutually-accepted interest.
  bool get isContactPublic => contactPrivacy == 'public';
  String get about => aboutMe ?? '';

  /// The member's photo(s) — at most ONE (§1). Kept as a list so the existing
  /// call sites (cards, chat avatars, admin panel) keep compiling, but it can
  /// never hold more than a single url.
  List<String> get photos {
    final url = profilePhotoUrl?.trim() ?? '';
    return url.isEmpty ? const <String>[] : <String>[url];
  }

  /// True when the member has a profile photo.
  bool get hasPhoto => (profilePhotoUrl?.trim() ?? '').isNotEmpty;

  // ── Privacy helpers (§16/§17) — default HIDDEN, never auto-revealed. ──
  bool get hidesPhone => ProfilePrivacy.isHidden(privacySettings, ProfilePrivacy.phone);
  bool get hidesSalary =>
      ProfilePrivacy.isHidden(privacySettings, ProfilePrivacy.salary);
  bool get hidesHoroscope =>
      ProfilePrivacy.isHidden(privacySettings, ProfilePrivacy.horoscope);
  bool get hidesPhoto => ProfilePrivacy.isHidden(privacySettings, ProfilePrivacy.photo);

  HoroscopeDetails get horoscopeDetails => horoscope;

  // ── fromMap factory for profile creation flow ─────────────────────────
  factory ProfileModel.fromMap(Map<String, dynamic> d) {
    final horoMap = d['horoscopeDetails'] as Map<String, dynamic>? ?? {};
    final famMap = d['familyDetails'] as Map<String, dynamic>? ?? {};
    final prefMap = d['partnerPreferences'] as Map<String, dynamic>? ?? {};
    final contactMap = d['contactDetails'] as Map<String, dynamic>? ?? {};
    final lifeMap = d['lifestyle'] as Map<String, dynamic>? ?? {};
    final photos = toStringList(d['photos']);
    return ProfileModel(
      id: d['id'] ?? '',
      userId: d['userId'] ?? '',
      profileCreatedBy: d['profileFor'] ?? 'Myself',
      profileCreatedFor: d['profileFor'] ?? 'Myself',
      fullName: d['name'] ?? '',
      fullNameTamil: d['nameTamil'] ?? '',
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
      educationLevel: d['educationLevel'] ?? '',
      education: d['education'] ?? '',
      degrees: toStringList(d['degrees']),
      displayDegrees: toStringList(d['displayDegrees']),
      employmentStatus: d['employmentStatus'] ?? '',
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
      physicalStatus: d['physicalStatus'] ?? '',
      childrenCount:
          (d['childrenCount'] is num) ? (d['childrenCount'] as num).toInt() : 0,
      childrenLivingStatus: d['childrenLivingStatus'],
      gothram: d['gothram'] ?? '',
      kuladeivam: d['kuladeivam'] ?? '',
      employmentType: d['employmentType'] ?? '',
      collegeName: d['collegeName'],
      companyName: d['companyName'],
      workLocation: d['workLocation'],
      courseDegree: d['courseDegree'],
      nativePlace: d['nativePlace'],
      citizenship: d['citizenship'],
      lifestyle: LifestyleDetails.fromMap(lifeMap),
      // Only the FIRST photo is ever kept — one photo per member (§1).
      profilePhotoUrl: photos.isNotEmpty ? photos.first : null,
      privacySettings: ProfilePrivacy.fromMap(d['privacySettings']),
      horoscope: HoroscopeDetails.fromMap(horoMap),
      family: FamilyDetails.fromMap(famMap),
      partnerPreferences: PartnerPreferences.fromMap(prefMap),
      contact: ContactDetails.fromMap(contactMap),
      contactPrivacy: d['contactPrivacy'] ?? 'private',
      status: d['status'] ?? 'pending',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// The INVERSE of [fromMap]: flattens this profile into the wizard's
  /// data-map dialect so Edit Profile can seed the creation steps with the
  /// user's existing values (every field editable after creation).
  Map<String, dynamic> toWizardData() => {
        'id': id,
        'userId': userId,
        'profileFor': profileCreatedFor,
        'name': fullName,
        'nameTamil': fullNameTamil,
        'gender': gender,
        'dateOfBirth': dateOfBirth.toIso8601String(),
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
        'educationLevel': educationLevel,
        'education': education,
        'degrees': degrees,
        'displayDegrees': displayDegrees,
        'employmentStatus': employmentStatus,
        'occupation': occupation,
        'annualIncome': annualIncome,
        'country': country,
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
        'about': aboutMe,
        'physicalStatus': physicalStatus,
        'childrenCount': childrenCount,
        'childrenLivingStatus': childrenLivingStatus,
        'gothram': gothram,
        'kuladeivam': kuladeivam,
        'employmentType': employmentType,
        'collegeName': collegeName,
        'companyName': companyName,
        'workLocation': workLocation,
        'courseDegree': courseDegree,
        'nativePlace': nativePlace,
        'citizenship': citizenship,
        'lifestyle': lifestyle.toMap(),
        'photos': photos, // the one existing URL — kept unless a new file is picked
        'privacySettings': privacySettings,
        'horoscopeDetails': horoscope.toMap(),
        'familyDetails': family.toMap(),
        'partnerPreferences': partnerPreferences.toMap(),
        'contactDetails': contact.toMap(),
        'contactPrivacy': contactPrivacy,
        'status': status,
      };

  ProfileModel copyWith({
    String? fullName,
    String? fullNameTamil,
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
    String? educationLevel,
    String? education,
    List<String>? degrees,
    List<String>? displayDegrees,
    String? employmentStatus,
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
    String? physicalStatus,
    int? childrenCount,
    String? childrenLivingStatus,
    String? gothram,
    String? kuladeivam,
    String? employmentType,
    String? collegeName,
    String? companyName,
    String? workLocation,
    String? courseDegree,
    String? nativePlace,
    String? citizenship,
    LifestyleDetails? lifestyle,
    String? profilePhotoUrl,
    Map<String, bool>? privacySettings,
    HoroscopeDetails? horoscope,
    FamilyDetails? family,
    PartnerPreferences? partnerPreferences,
    ContactDetails? contact,
    String? contactPrivacy,
    String? status,
    bool? isVerified,
    bool? isFeatured,
    bool? isActive,
    bool? isMarried,
    bool? isDummy,
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
        fullNameTamil: fullNameTamil ?? this.fullNameTamil,
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
        educationLevel: educationLevel ?? this.educationLevel,
        education: education ?? this.education,
        degrees: degrees ?? this.degrees,
        displayDegrees: displayDegrees ?? this.displayDegrees,
        employmentStatus: employmentStatus ?? this.employmentStatus,
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
        physicalStatus: physicalStatus ?? this.physicalStatus,
        childrenCount: childrenCount ?? this.childrenCount,
        childrenLivingStatus: childrenLivingStatus ?? this.childrenLivingStatus,
        gothram: gothram ?? this.gothram,
        kuladeivam: kuladeivam ?? this.kuladeivam,
        employmentType: employmentType ?? this.employmentType,
        collegeName: collegeName ?? this.collegeName,
        companyName: companyName ?? this.companyName,
        workLocation: workLocation ?? this.workLocation,
        courseDegree: courseDegree ?? this.courseDegree,
        nativePlace: nativePlace ?? this.nativePlace,
        citizenship: citizenship ?? this.citizenship,
        lifestyle: lifestyle ?? this.lifestyle,
        profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
        privacySettings: privacySettings ?? this.privacySettings,
        horoscope: horoscope ?? this.horoscope,
        family: family ?? this.family,
        partnerPreferences: partnerPreferences ?? this.partnerPreferences,
        contact: contact ?? this.contact,
        contactPrivacy: contactPrivacy ?? this.contactPrivacy,
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
        isDummy: isDummy ?? this.isDummy,
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
        fullNameTamil: fullNameTamil,
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
        educationLevel: educationLevel,
        education: education,
        degrees: degrees,
        displayDegrees: displayDegrees,
        employmentStatus: employmentStatus,
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
        physicalStatus: physicalStatus,
        childrenCount: childrenCount,
        childrenLivingStatus: childrenLivingStatus,
        gothram: gothram,
        kuladeivam: kuladeivam,
        employmentType: employmentType,
        collegeName: collegeName,
        companyName: companyName,
        workLocation: workLocation,
        courseDegree: courseDegree,
        nativePlace: nativePlace,
        citizenship: citizenship,
        lifestyle: lifestyle,
        profilePhotoUrl: url,
        privacySettings: privacySettings,
        horoscope: horoscope,
        family: family,
        partnerPreferences: partnerPreferences,
        contact: contact,
        contactPrivacy: contactPrivacy,
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
        isDummy: isDummy,
      );
}

class HoroscopeDetails {
  final String rasi;
  final String nakshatra;
  final String lagnam;
  final String dosham; // Chevvai / Sevvai dosham
  final String rahuKethuDosham;
  final String kalasarpaDosham;
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
  // Legacy single horoscope PDF (kept for backward compatibility with older
  // documents). New uploads append to [horoscopePdfUrls] so a profile can hold
  // MULTIPLE horoscope PDFs.
  final String? horoscopePdfUrl;
  final List<String> horoscopePdfUrls;
  final List<String> horoscopeImages;

  const HoroscopeDetails({
    required this.rasi,
    required this.nakshatra,
    required this.lagnam,
    this.dosham = '',
    this.rahuKethuDosham = '',
    this.kalasarpaDosham = '',
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
    this.horoscopePdfUrls = const [],
    this.horoscopeImages = const [],
  });

  factory HoroscopeDetails.fromMap(Map<String, dynamic> map) => HoroscopeDetails(
        rasi: map['rasi'] ?? '',
        nakshatra: map['nakshatra'] ?? '',
        lagnam: map['lagnam'] ?? '',
        dosham: map['dosham'] ?? '',
        rahuKethuDosham: map['rahuKethuDosham'] ?? '',
        kalasarpaDosham: map['kalasarpaDosham'] ?? '',
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
        horoscopePdfUrls: toStringList(map['horoscopePdfUrls']),
        horoscopeImages: toStringList(map['horoscopeImages']),
      );

  Map<String, dynamic> toMap() => {
        'rasi': rasi,
        'nakshatra': nakshatra,
        'lagnam': lagnam,
        'dosham': dosham,
        'rahuKethuDosham': rahuKethuDosham,
        'kalasarpaDosham': kalasarpaDosham,
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
        'horoscopePdfUrls': horoscopePdfUrls,
        'horoscopeImages': horoscopeImages,
      };

  HoroscopeDetails copyWith({
    String? rasi,
    String? nakshatra,
    String? lagnam,
    String? dosham,
    String? rahuKethuDosham,
    String? kalasarpaDosham,
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
    String? horoscopePdfUrl,
    List<String>? horoscopePdfUrls,
    List<String>? horoscopeImages,
  }) =>
      HoroscopeDetails(
        rasi: rasi ?? this.rasi,
        nakshatra: nakshatra ?? this.nakshatra,
        lagnam: lagnam ?? this.lagnam,
        dosham: dosham ?? this.dosham,
        rahuKethuDosham: rahuKethuDosham ?? this.rahuKethuDosham,
        kalasarpaDosham: kalasarpaDosham ?? this.kalasarpaDosham,
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
        horoscopePdfUrl: horoscopePdfUrl ?? this.horoscopePdfUrl,
        horoscopePdfUrls: horoscopePdfUrls ?? this.horoscopePdfUrls,
        horoscopeImages: horoscopeImages ?? this.horoscopeImages,
      );

  String get badgeText {
    if (isAstrologerVerified) return 'Astrologer Verified';
    if (isUserEdited) return 'User Edited';
    return 'Auto Generated';
  }

  /// All horoscope PDFs, folding the legacy single [horoscopePdfUrl] into the
  /// multi-PDF [horoscopePdfUrls] list (de-duplicated, non-empty).
  List<String> get allPdfUrls {
    final out = <String>[];
    if ((horoscopePdfUrl ?? '').isNotEmpty) out.add(horoscopePdfUrl!);
    for (final u in horoscopePdfUrls) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }
    return out;
  }
}

class FamilyDetails {
  final String fatherName;
  final String fatherOccupation;
  final String motherName;
  final String motherOccupation;
  final int brothersCount;
  final int sistersCount;
  final int marriedBrothers;
  final int marriedSisters;
  final String familyType;
  final String familyStatus;
  final String aboutFamily;

  const FamilyDetails({
    required this.fatherName,
    required this.fatherOccupation,
    required this.motherName,
    required this.motherOccupation,
    required this.brothersCount,
    required this.sistersCount,
    this.marriedBrothers = 0,
    this.marriedSisters = 0,
    required this.familyType,
    required this.familyStatus,
    this.aboutFamily = '',
  });

  factory FamilyDetails.fromMap(Map<String, dynamic> map) => FamilyDetails(
        fatherName: map['fatherName'] ?? '',
        fatherOccupation: map['fatherOccupation'] ?? '',
        motherName: map['motherName'] ?? '',
        motherOccupation: map['motherOccupation'] ?? '',
        brothersCount: map['brothersCount'] ?? 0,
        sistersCount: map['sistersCount'] ?? 0,
        marriedBrothers: map['marriedBrothers'] ?? 0,
        marriedSisters: map['marriedSisters'] ?? 0,
        familyType: map['familyType'] ?? '',
        familyStatus: map['familyStatus'] ?? '',
        aboutFamily: map['aboutFamily'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'fatherName': fatherName,
        'fatherOccupation': fatherOccupation,
        'motherName': motherName,
        'motherOccupation': motherOccupation,
        'brothersCount': brothersCount,
        'sistersCount': sistersCount,
        'marriedBrothers': marriedBrothers,
        'marriedSisters': marriedSisters,
        'familyType': familyType,
        'familyStatus': familyStatus,
        'aboutFamily': aboutFamily,
      };

  FamilyDetails copyWith({
    String? fatherName,
    String? fatherOccupation,
    String? motherName,
    String? motherOccupation,
    int? brothersCount,
    int? sistersCount,
    int? marriedBrothers,
    int? marriedSisters,
    String? familyType,
    String? familyStatus,
    String? aboutFamily,
  }) =>
      FamilyDetails(
        fatherName: fatherName ?? this.fatherName,
        fatherOccupation: fatherOccupation ?? this.fatherOccupation,
        motherName: motherName ?? this.motherName,
        motherOccupation: motherOccupation ?? this.motherOccupation,
        brothersCount: brothersCount ?? this.brothersCount,
        sistersCount: sistersCount ?? this.sistersCount,
        marriedBrothers: marriedBrothers ?? this.marriedBrothers,
        marriedSisters: marriedSisters ?? this.marriedSisters,
        familyType: familyType ?? this.familyType,
        familyStatus: familyStatus ?? this.familyStatus,
        aboutFamily: aboutFamily ?? this.aboutFamily,
      );
}

class PartnerPreferences {
  final int minAge;
  final int maxAge;

  /// True once the member has ACTIVELY chosen [minAge]/[maxAge] (§11 — the
  /// partner age range is mandatory at profile creation).
  ///
  /// Legacy profiles created before the rule existed leave this false, which
  /// is what lets `resolveAgeRange` keep applying the gender-based default
  /// window for them instead of a range they never picked. Once it is true the
  /// chosen range is used verbatim — even when it happens to equal the old
  /// 18–40 default.
  final bool agePreferenceSet;
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
  final String? district;
  final String? country;
  final String motherTongue; // language preference; 'Any' or a language
  // NOTE: `horoscopeMatchRequired` was removed (§11). The app shows every
  // profile and a member can check compatibility on any of them whenever they
  // want, so a stored "I require a horoscope match" flag decided nothing and
  // only added a question to the form. Old documents may still carry the
  // field; it is simply ignored on read.
  // Extended & lifestyle preferences ('Any' = no preference).
  final String physicalStatus;
  final String employmentType;
  final String? subCaste;
  final String chevvaiDosham;
  final String eatingHabit;
  final String smokingHabit;
  final String drinkingHabit;

  const PartnerPreferences({
    this.minAge = 18,
    this.maxAge = 40,
    this.agePreferenceSet = false,
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
    this.district,
    this.country,
    this.motherTongue = 'Any',
    this.physicalStatus = 'Any',
    this.employmentType = 'Any',
    this.subCaste,
    this.chevvaiDosham = 'Any',
    this.eatingHabit = 'Any',
    this.smokingHabit = 'Any',
    this.drinkingHabit = 'Any',
  });

  factory PartnerPreferences.fromMap(Map<String, dynamic> map) => PartnerPreferences(
        minAge: map['minAge'] ?? 18,
        maxAge: map['maxAge'] ?? 40,
        agePreferenceSet: map['agePreferenceSet'] == true,
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
        district: map['district'],
        country: map['country'],
        motherTongue: map['motherTongue'] ?? 'Any',
        physicalStatus: map['physicalStatus'] ?? 'Any',
        employmentType: map['employmentType'] ?? 'Any',
        subCaste: map['subCaste'],
        chevvaiDosham: map['chevvaiDosham'] ?? 'Any',
        eatingHabit: map['eatingHabit'] ?? 'Any',
        smokingHabit: map['smokingHabit'] ?? 'Any',
        drinkingHabit: map['drinkingHabit'] ?? 'Any',
      );

  Map<String, dynamic> toMap() => {
        'minAge': minAge,
        'maxAge': maxAge,
        'agePreferenceSet': agePreferenceSet,
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
        'district': district,
        'country': country,
        'motherTongue': motherTongue,
        'physicalStatus': physicalStatus,
        'employmentType': employmentType,
        'subCaste': subCaste,
        'chevvaiDosham': chevvaiDosham,
        'eatingHabit': eatingHabit,
        'smokingHabit': smokingHabit,
        'drinkingHabit': drinkingHabit,
      };

  PartnerPreferences copyWith({
    int? minAge,
    int? maxAge,
    bool? agePreferenceSet,
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
    String? district,
    String? country,
    String? motherTongue,
    String? physicalStatus,
    String? employmentType,
    String? subCaste,
    String? chevvaiDosham,
    String? eatingHabit,
    String? smokingHabit,
    String? drinkingHabit,
  }) =>
      PartnerPreferences(
        minAge: minAge ?? this.minAge,
        maxAge: maxAge ?? this.maxAge,
        agePreferenceSet: agePreferenceSet ?? this.agePreferenceSet,
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
        district: district ?? this.district,
        country: country ?? this.country,
        motherTongue: motherTongue ?? this.motherTongue,
        physicalStatus: physicalStatus ?? this.physicalStatus,
        employmentType: employmentType ?? this.employmentType,
        subCaste: subCaste ?? this.subCaste,
        chevvaiDosham: chevvaiDosham ?? this.chevvaiDosham,
        eatingHabit: eatingHabit ?? this.eatingHabit,
        smokingHabit: smokingHabit ?? this.smokingHabit,
        drinkingHabit: drinkingHabit ?? this.drinkingHabit,
      );
}

class ContactDetails {
  final String contactPersonName;
  final String relationship;
  final String mobileNumber;
  final String? whatsappNumber;

  /// Contact email address (§5 — every profile field must be editable).
  ///
  /// This is deliberately SEPARATE from the Google sign-in identity, which the
  /// member cannot change from inside the app. It is the address they want to
  /// be reached on, and it is editable like any other field.
  final String email;

  const ContactDetails({
    required this.contactPersonName,
    required this.relationship,
    required this.mobileNumber,
    this.whatsappNumber,
    this.email = '',
  });

  factory ContactDetails.fromMap(Map<String, dynamic> map) => ContactDetails(
        contactPersonName: map['contactPersonName'] ?? '',
        relationship: map['relationship'] ?? '',
        mobileNumber: map['mobileNumber'] ?? '',
        whatsappNumber: map['whatsappNumber'],
        email: map['email'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'contactPersonName': contactPersonName,
        'relationship': relationship,
        'mobileNumber': mobileNumber,
        'whatsappNumber': whatsappNumber,
        'email': email,
      };

  /// True when this record carries ANY reachable detail.
  ///
  /// The gated `contacts/{userId}` record used to be written only when a
  /// MOBILE or WhatsApp number was present, so a member who entered just an
  /// e-mail (or only a contact person) ended up with no record at all and the
  /// Contact Details popup reported "not provided". Every write path now gates
  /// on this instead.
  bool get hasAnyValue => [
        contactPersonName,
        relationship,
        mobileNumber,
        whatsappNumber ?? '',
        email,
      ].any((v) => v.trim().isNotEmpty);

  ContactDetails copyWith({
    String? contactPersonName,
    String? relationship,
    String? mobileNumber,
    String? whatsappNumber,
    String? email,
  }) =>
      ContactDetails(
        contactPersonName: contactPersonName ?? this.contactPersonName,
        relationship: relationship ?? this.relationship,
        mobileNumber: mobileNumber ?? this.mobileNumber,
        whatsappNumber: whatsappNumber ?? this.whatsappNumber,
        email: email ?? this.email,
      );
}

/// Lifestyle & habits — all optional. Habit fields use the constant option
/// lists; hobbies / interests are free text; languagesKnown is a list.
class LifestyleDetails {
  final String eatingHabit;
  final String smokingHabit;
  final String drinkingHabit;
  final String hobbies;
  final String interests;
  final List<String> languagesKnown;

  const LifestyleDetails({
    this.eatingHabit = '',
    this.smokingHabit = '',
    this.drinkingHabit = '',
    this.hobbies = '',
    this.interests = '',
    this.languagesKnown = const [],
  });

  factory LifestyleDetails.fromMap(Map<String, dynamic> map) => LifestyleDetails(
        eatingHabit: map['eatingHabit'] ?? '',
        smokingHabit: map['smokingHabit'] ?? '',
        drinkingHabit: map['drinkingHabit'] ?? '',
        hobbies: map['hobbies'] ?? '',
        interests: map['interests'] ?? '',
        languagesKnown: toStringList(map['languagesKnown']),
      );

  Map<String, dynamic> toMap() => {
        'eatingHabit': eatingHabit,
        'smokingHabit': smokingHabit,
        'drinkingHabit': drinkingHabit,
        'hobbies': hobbies,
        'interests': interests,
        'languagesKnown': languagesKnown,
      };

  LifestyleDetails copyWith({
    String? eatingHabit,
    String? smokingHabit,
    String? drinkingHabit,
    String? hobbies,
    String? interests,
    List<String>? languagesKnown,
  }) =>
      LifestyleDetails(
        eatingHabit: eatingHabit ?? this.eatingHabit,
        smokingHabit: smokingHabit ?? this.smokingHabit,
        drinkingHabit: drinkingHabit ?? this.drinkingHabit,
        hobbies: hobbies ?? this.hobbies,
        interests: interests ?? this.interests,
        languagesKnown: languagesKnown ?? this.languagesKnown,
      );
}
