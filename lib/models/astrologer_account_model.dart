import 'package:cloud_firestore/cloud_firestore.dart';
import 'astrologer_certificate.dart';
import 'astrologer_model.dart';

/// Canonical Monday→Sunday weekday names, ordered so that
/// `kWeekdays[DateTime.weekday - 1]` (Dart's weekday is Mon=1…Sun=7) yields
/// today's name. Single source of truth for the availability / working-days
/// feature — the model, the selector widget and the badges all read this.
const List<String> kWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The weekday name for [date] (defaults to now), e.g. "Wednesday".
String weekdayName([DateTime? date]) =>
    kWeekdays[(date ?? DateTime.now()).weekday - 1];

/// Certificate verification status set by the admin.
enum VerificationStatus { pending, approved, rejected }

extension VerificationStatusX on VerificationStatus {
  String get label {
    switch (this) {
      case VerificationStatus.pending:
        return 'Pending Verification';
      case VerificationStatus.approved:
        return 'Approved';
      case VerificationStatus.rejected:
        return 'Rejected';
    }
  }
}

/// The logged-in astrologer's own account/profile created during onboarding.
///
/// Maps to Firestore `astrologers/{uid}` + `astrologer_certificates` +
/// `astrologer_services`. The profile cannot go live until [status] is
/// `approved` by an admin.
class AstrologerAccount {
  final String id;
  // Basic
  final String fullName;
  final String gender;
  final DateTime? dob;
  final String mobile;
  final String email;
  final String city;
  final String state;
  final String district;
  final String country;
  final double? latitude;
  final double? longitude;
  final String photoUrl;
  // Professional
  final int experienceYears;
  final List<String> expertise;
  final List<String> languages;
  final String about;
  final List<String> consultationModes; // Chat, Audio Call, Video Call, In-Person
  final String qualification; // highest astrology/academic qualification
  // Certification (legacy single-cert fields, kept for backward compatibility).
  final String certName;
  final String certOrg;
  final String certNumber;
  final String certFileName;
  // Uploaded certificate documents (for admin verification).
  final List<AstrologerCertificate> certificates;
  // Consultation
  final double consultationFee; // per session, in INR
  final String availability; // e.g. "Monday – Saturday" (legacy free-text)
  final String workingHours; // e.g. "10:00 AM – 6:00 PM"
  final String consultationMode; // Online | Offline | Both
  // Days the astrologer accepts consultations on (subset of [kWeekdays]).
  // Empty means "no working days"; legacy docs without the field default to all.
  final List<String> workingDays;
  // Astrologer-controlled on/off switch. When false the astrologer is shown as
  // unavailable even on a working day, and new bookings are blocked.
  final bool manuallyAvailable;
  // "Available for Assignment" — whether the admin may assign this astrologer a
  // reassigned/expired booking. Independent of [manuallyAvailable]; defaults on.
  final bool availableForAssignment;
  // Temporarily on leave. Excluded from admin assignment even when otherwise
  // eligible (the admin's "Not On Leave" filter).
  final bool onLeave;

  // ── Consultation availability (slot booking) ───────────────────────────────
  // One continuous available window, as minutes-from-midnight (e.g. 8:00 AM =
  // 480, 9:00 PM = 1260). No separate morning/evening sections.
  final int availableStartMinutes;
  final int availableEndMinutes;
  // Optional lunch break — no slots are generated inside it. Null = no break.
  final int? lunchStartMinutes;
  final int? lunchEndMinutes;
  // Slot length in minutes (15 / 30 / 45 / 60).
  final int slotDurationMinutes;
  // Specific dates the astrologer is unavailable (`yyyy-MM-dd`). Users cannot
  // book on these. Replaces any "available date range" concept.
  final List<String> unavailableDates;
  // Cap on bookings per day (0 = no cap). A day at the cap shows "Fully Booked".
  final int maxBookingsPerDay;
  // Which consultation modes the astrologer offers.
  final bool offersInApp;
  final bool offersDirectVisit;
  // Set once the astrologer has completed the post-Google profile setup.
  final bool profileCompleted;
  // Status & services
  final VerificationStatus status;
  // Reason shown to the astrologer when [status] is rejected (set by admin).
  final String rejectionReason;
  final List<AstrologerService> services;
  final double rating;
  final int reviewCount;
  // Reputation breakdown: star (1-5) → number of reviews at that rating.
  final Map<int, int> ratingBreakdown;
  // Marketplace stats (populated by the platform; default 0 until tracked).
  final int profileViews;
  final int contactUnlocks;
  // Subscription — the visibility gate for the marketplace.
  final String subscriptionPlan; // '' | 'monthly' | 'yearly'
  final DateTime? subscriptionExpiry;
  // When the astrologer account was first created (registration date). Read
  // from the Firestore `createdAt` server timestamp; may be null for older docs.
  final DateTime? createdAt;

  const AstrologerAccount({
    required this.id,
    required this.fullName,
    required this.gender,
    required this.dob,
    required this.mobile,
    required this.email,
    required this.city,
    required this.state,
    this.district = '',
    required this.country,
    this.latitude,
    this.longitude,
    this.photoUrl = '',
    required this.experienceYears,
    required this.expertise,
    required this.languages,
    required this.about,
    required this.consultationModes,
    this.qualification = '',
    required this.certName,
    required this.certOrg,
    required this.certNumber,
    required this.certFileName,
    this.certificates = const [],
    this.consultationFee = 0,
    this.availability = '',
    this.workingHours = '',
    this.consultationMode = 'Online',
    this.workingDays = kWeekdays,
    this.manuallyAvailable = true,
    this.availableForAssignment = true,
    this.onLeave = false,
    this.availableStartMinutes = 8 * 60,
    this.availableEndMinutes = 21 * 60,
    this.lunchStartMinutes,
    this.lunchEndMinutes,
    this.slotDurationMinutes = 30,
    this.unavailableDates = const [],
    this.maxBookingsPerDay = 0,
    this.offersInApp = true,
    this.offersDirectVisit = true,
    this.profileCompleted = false,
    this.status = VerificationStatus.pending,
    this.rejectionReason = '',
    this.services = const [],
    this.rating = 0,
    this.reviewCount = 0,
    this.ratingBreakdown = const {},
    this.profileViews = 0,
    this.contactUnlocks = 0,
    this.subscriptionPlan = '',
    this.subscriptionExpiry,
    this.createdAt,
  });

  bool get isApproved => status == VerificationStatus.approved;

  /// True when today's weekday is one of the astrologer's [workingDays].
  bool get isWorkingToday => workingDays.contains(weekdayName());

  /// Whether the astrologer is open for new bookings right now: today must be a
  /// working day AND the manual switch must be on. Drives the user-facing
  /// "Available Today" badge and the booking guard.
  bool get isAvailableNow => manuallyAvailable && isWorkingToday;

  /// Eligible to receive an admin-reassigned (expired) booking: an ACTIVE,
  /// approved account that is available for assignment and not on leave.
  /// `isApproved` also enforces "not suspended" (suspension reverts the account
  /// to `pending`).
  bool get isEligibleForAssignment =>
      isApproved && availableForAssignment && !onLeave;

  /// Human label of the consultation modes the astrologer offers.
  String get consultationModesLabel {
    final modes = <String>[
      if (offersInApp) 'In-App Consultation',
      if (offersDirectVisit) 'Direct Visit',
    ];
    return modes.isEmpty ? 'Not set' : modes.join(' · ');
  }

  /// Human-readable working-days summary, e.g. "All Days",
  /// "Monday, Tuesday, …" or "Not set".
  String get workingDaysLabel {
    if (workingDays.isEmpty) return 'Not set';
    if (kWeekdays.every(workingDays.contains)) return 'All Days';
    // Preserve Monday→Sunday order regardless of stored order.
    return kWeekdays.where(workingDays.contains).join(', ');
  }

  /// True while the subscription has not expired.
  bool get subscriptionActive =>
      subscriptionExpiry != null &&
      subscriptionExpiry!.isAfter(DateTime.now());

  /// Whole days left on the subscription (0 if none/expired).
  int get subscriptionDaysRemaining => subscriptionExpiry == null
      ? 0
      : subscriptionExpiry!.difference(DateTime.now()).inDays.clamp(0, 100000);

  /// Marketplace visibility gate: an astrologer is shown to users only when
  /// approved by an admin AND holding an active subscription.
  bool get isVisibleToUsers => isApproved && subscriptionActive;

  AstrologerAccount copyWith({
    String? fullName,
    String? gender,
    DateTime? dob,
    String? mobile,
    String? email,
    String? city,
    String? state,
    String? district,
    String? country,
    double? latitude,
    double? longitude,
    String? photoUrl,
    int? experienceYears,
    List<String>? expertise,
    List<String>? languages,
    String? about,
    List<String>? consultationModes,
    String? qualification,
    String? certName,
    String? certOrg,
    String? certNumber,
    String? certFileName,
    List<AstrologerCertificate>? certificates,
    double? consultationFee,
    String? availability,
    String? workingHours,
    String? consultationMode,
    List<String>? workingDays,
    bool? manuallyAvailable,
    bool? availableForAssignment,
    bool? onLeave,
    int? availableStartMinutes,
    int? availableEndMinutes,
    int? lunchStartMinutes,
    int? lunchEndMinutes,
    bool clearLunch = false,
    int? slotDurationMinutes,
    List<String>? unavailableDates,
    int? maxBookingsPerDay,
    bool? offersInApp,
    bool? offersDirectVisit,
    bool? profileCompleted,
    VerificationStatus? status,
    List<AstrologerService>? services,
    Map<int, int>? ratingBreakdown,
    int? profileViews,
    int? contactUnlocks,
    String? subscriptionPlan,
    DateTime? subscriptionExpiry,
  }) =>
      AstrologerAccount(
        id: id,
        fullName: fullName ?? this.fullName,
        gender: gender ?? this.gender,
        dob: dob ?? this.dob,
        mobile: mobile ?? this.mobile,
        email: email ?? this.email,
        city: city ?? this.city,
        state: state ?? this.state,
        district: district ?? this.district,
        country: country ?? this.country,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        photoUrl: photoUrl ?? this.photoUrl,
        experienceYears: experienceYears ?? this.experienceYears,
        expertise: expertise ?? this.expertise,
        languages: languages ?? this.languages,
        about: about ?? this.about,
        consultationModes: consultationModes ?? this.consultationModes,
        qualification: qualification ?? this.qualification,
        certName: certName ?? this.certName,
        certOrg: certOrg ?? this.certOrg,
        certNumber: certNumber ?? this.certNumber,
        certFileName: certFileName ?? this.certFileName,
        certificates: certificates ?? this.certificates,
        consultationFee: consultationFee ?? this.consultationFee,
        availability: availability ?? this.availability,
        workingHours: workingHours ?? this.workingHours,
        consultationMode: consultationMode ?? this.consultationMode,
        workingDays: workingDays ?? this.workingDays,
        manuallyAvailable: manuallyAvailable ?? this.manuallyAvailable,
        availableForAssignment:
            availableForAssignment ?? this.availableForAssignment,
        onLeave: onLeave ?? this.onLeave,
        availableStartMinutes:
            availableStartMinutes ?? this.availableStartMinutes,
        availableEndMinutes: availableEndMinutes ?? this.availableEndMinutes,
        lunchStartMinutes:
            clearLunch ? null : (lunchStartMinutes ?? this.lunchStartMinutes),
        lunchEndMinutes:
            clearLunch ? null : (lunchEndMinutes ?? this.lunchEndMinutes),
        slotDurationMinutes: slotDurationMinutes ?? this.slotDurationMinutes,
        unavailableDates: unavailableDates ?? this.unavailableDates,
        maxBookingsPerDay: maxBookingsPerDay ?? this.maxBookingsPerDay,
        offersInApp: offersInApp ?? this.offersInApp,
        offersDirectVisit: offersDirectVisit ?? this.offersDirectVisit,
        profileCompleted: profileCompleted ?? this.profileCompleted,
        status: status ?? this.status,
        rejectionReason: rejectionReason,
        services: services ?? this.services,
        ratingBreakdown: ratingBreakdown ?? this.ratingBreakdown,
        profileViews: profileViews ?? this.profileViews,
        contactUnlocks: contactUnlocks ?? this.contactUnlocks,
        subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
        subscriptionExpiry: subscriptionExpiry ?? this.subscriptionExpiry,
        rating: rating,
        reviewCount: reviewCount,
        createdAt: createdAt,
      );

  factory AstrologerAccount.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final cert = (d['certification'] as Map<String, dynamic>?) ?? const {};
    return AstrologerAccount(
      id: doc.id,
      fullName: d['fullName'] ?? '',
      gender: d['gender'] ?? '',
      dob: d['dob'] != null ? DateTime.tryParse(d['dob']) : null,
      mobile: d['mobile'] ?? '',
      email: d['email'] ?? '',
      city: d['city'] ?? '',
      state: d['state'] ?? '',
      district: d['district'] ?? '',
      country: d['country'] ?? 'India',
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      photoUrl: d['photoUrl'] ?? '',
      experienceYears: (d['experienceYears'] ?? 0) is int
          ? d['experienceYears'] ?? 0
          : int.tryParse('${d['experienceYears']}') ?? 0,
      expertise: List<String>.from(d['expertise'] ?? const []),
      languages: List<String>.from(d['languages'] ?? const []),
      about: d['about'] ?? '',
      consultationModes:
          List<String>.from(d['consultationModes'] ?? const ['Chat']),
      qualification: d['qualification'] ?? '',
      certName: cert['name'] ?? '',
      certOrg: cert['organization'] ?? '',
      certNumber: cert['number'] ?? '',
      certFileName: cert['fileName'] ?? '',
      certificates: ((d['certificates'] as List?) ?? const [])
          .map((c) =>
              AstrologerCertificate.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
      consultationFee: (d['consultationFee'] ?? 0).toDouble(),
      availability: d['availability'] ?? '',
      workingHours: d['workingHours'] ?? '',
      consultationMode: d['consultationMode'] ?? 'Online',
      // Legacy docs (field absent) default to all days so they stay available;
      // an explicit empty list is respected (astrologer unchecked every day).
      workingDays: d['workingDays'] is List
          ? List<String>.from(d['workingDays'])
          : List<String>.from(kWeekdays),
      manuallyAvailable: d['manuallyAvailable'] ?? true,
      availableForAssignment: d['availableForAssignment'] ?? true,
      onLeave: d['onLeave'] ?? false,
      availableStartMinutes: (d['availableStartMinutes'] as num?)?.toInt() ?? 8 * 60,
      availableEndMinutes: (d['availableEndMinutes'] as num?)?.toInt() ?? 21 * 60,
      lunchStartMinutes: (d['lunchStartMinutes'] as num?)?.toInt(),
      lunchEndMinutes: (d['lunchEndMinutes'] as num?)?.toInt(),
      slotDurationMinutes: (d['slotDurationMinutes'] as num?)?.toInt() ?? 30,
      unavailableDates: List<String>.from(d['unavailableDates'] ?? const []),
      maxBookingsPerDay: (d['maxBookingsPerDay'] as num?)?.toInt() ?? 0,
      offersInApp: d['offersInApp'] ?? true,
      offersDirectVisit: d['offersDirectVisit'] ?? true,
      profileCompleted: d['profileCompleted'] ?? false,
      status: VerificationStatus.values.firstWhere(
        (s) => s.name == (d['status'] ?? 'pending'),
        orElse: () => VerificationStatus.pending,
      ),
      rejectionReason: d['rejectionReason'] ?? '',
      services: ((d['services'] as List?) ?? const [])
          .map((s) => AstrologerService.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      rating: (d['rating'] ?? 0).toDouble(),
      reviewCount: d['reviewCount'] ?? 0,
      ratingBreakdown: _parseBreakdown(d['ratingBreakdown']),
      profileViews: d['profileViews'] ?? 0,
      contactUnlocks: d['contactUnlocks'] ?? 0,
      subscriptionPlan: d['subscriptionPlan'] ?? '',
      subscriptionExpiry: d['subscriptionExpiry'] is Timestamp
          ? (d['subscriptionExpiry'] as Timestamp).toDate()
          : null,
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Parses a Firestore `ratingBreakdown` map (string keys) into {star: count}.
  static Map<int, int> _parseBreakdown(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <int, int>{};
    raw.forEach((k, v) {
      final star = int.tryParse('$k');
      if (star != null) out[star] = (v is int) ? v : int.tryParse('$v') ?? 0;
    });
    return out;
  }

  Map<String, dynamic> toFirestore() => {
        'fullName': fullName,
        'gender': gender,
        'dob': dob?.toIso8601String(),
        'mobile': mobile,
        'email': email,
        'city': city,
        'state': state,
        'district': district,
        'country': country,
        'latitude': latitude,
        'longitude': longitude,
        'photoUrl': photoUrl,
        'experienceYears': experienceYears,
        'expertise': expertise,
        'languages': languages,
        'about': about,
        'consultationModes': consultationModes,
        'qualification': qualification,
        'certification': {
          'name': certName,
          'organization': certOrg,
          'number': certNumber,
          'fileName': certFileName,
        },
        'certificates': certificates.map((c) => c.toMap()).toList(),
        'consultationFee': consultationFee,
        'availability': availability,
        'workingHours': workingHours,
        'consultationMode': consultationMode,
        'workingDays': workingDays,
        'manuallyAvailable': manuallyAvailable,
        'availableForAssignment': availableForAssignment,
        'onLeave': onLeave,
        'availableStartMinutes': availableStartMinutes,
        'availableEndMinutes': availableEndMinutes,
        'lunchStartMinutes': lunchStartMinutes,
        'lunchEndMinutes': lunchEndMinutes,
        'slotDurationMinutes': slotDurationMinutes,
        'unavailableDates': unavailableDates,
        'maxBookingsPerDay': maxBookingsPerDay,
        'offersInApp': offersInApp,
        'offersDirectVisit': offersDirectVisit,
        'profileCompleted': profileCompleted,
        'status': status.name,
        'services': services.map((s) => s.toMap()).toList(),
        'rating': rating,
        'reviewCount': reviewCount,
        'ratingBreakdown':
            ratingBreakdown.map((k, v) => MapEntry(k.toString(), v)),
        'profileViews': profileViews,
        'contactUnlocks': contactUnlocks,
        'subscriptionPlan': subscriptionPlan,
        'subscriptionExpiry': subscriptionExpiry != null
            ? Timestamp.fromDate(subscriptionExpiry!)
            : null,
      };
}
