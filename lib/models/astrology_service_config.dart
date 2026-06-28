import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin-editable configuration for the single internal **Horoscope
/// Compatibility Report** service. Stored at `astrology_service/config`.
///
/// This drives the user-facing service details page, the in-person appointment
/// booking (slot window + working days + charge) and the confirmation screen
/// (office address + contact number). The super-admin / internal astrology
/// account edits it from the admin "Astrology Service" screen; sensible
/// [AstrologyServiceConfig.defaults] are used until then so the flow always
/// works out of the box.
class AstrologyServiceConfig {
  // ── Service details page copy ──────────────────────────────────────────
  final String serviceIntro;
  final List<String> reportIncludes;
  final String deliveryTime;

  /// One-time service charge for the horoscope compatibility report (₹).
  final int serviceCharge;

  // ── Meet Our Astrology Expert card ─────────────────────────────────────
  final String expertName;
  final String expertPhotoUrl;
  final String expertExperience; // e.g. "15+ years"
  final String expertSpecialization; // e.g. "Tamil Jathagam · Porutham"
  final String expertIntro;

  /// Professional services the astrologer offers, shown on the user-facing
  /// Astrology page ("Services Offered"). Admin-managed — never hardcoded.
  final List<String> services;

  /// Phone number the "Contact Expert" dialer opens. Falls back to
  /// [officeContactNumber] when empty.
  final String expertContactPhone;

  // ── Office / appointment confirmation ──────────────────────────────────
  final String officeAddress;
  final String officeContactNumber;

  // ── Appointment slot configuration (minutes-from-midnight) ─────────────
  /// Mon→Fri only (spec §8). Weekday ints 1..7 (Mon=1). Default Mon–Fri.
  final List<int> workingWeekdays;
  final int slotStartMinutes; // 10:00 AM
  final int slotEndMinutes; // 5:00 PM
  final int lunchStartMinutes; // 1:00 PM
  final int lunchEndMinutes; // 2:00 PM
  final int slotDurationMinutes; // 60

  /// How many working days ahead are bookable (spec §9: next 5 working days).
  final int maxAdvanceWorkingDays;

  // ── Admin appointment controls ─────────────────────────────────────────
  /// Master switch — when false, appointment booking is closed for everyone
  /// and the user-facing "Book Your Appointment" button is disabled.
  final bool bookingEnabled;

  /// Specific calendar days (`yyyy-MM-dd`) the office is closed (holidays),
  /// removed from the rolling-week schedule even if they fall on a working day.
  final List<String> holidayDates;

  /// Slot start times (minutes-from-midnight) the admin has switched OFF. A
  /// disabled slot is hidden/greyed out for users even though it falls inside
  /// the working window.
  final List<int> disabledSlotMinutes;

  /// Free-text appointment rules / instructions shown on the booking screen
  /// (e.g. "Carry both horoscopes", "Arrive 10 minutes early").
  final String appointmentRules;

  /// The internal astrology account's REAL Firebase uid, captured on its first
  /// login. Used to pre-create the Astrology Analysis Chat after purchase so the
  /// user and the team share one thread.
  final String internalUid;

  const AstrologyServiceConfig({
    this.serviceIntro =
        'Get a detailed, professional horoscope compatibility analysis for you '
            'and your matched partner, prepared personally by our astrology '
            'expert.',
    this.reportIncludes = const [
      'Star (Nakshatra) & Rasi compatibility',
      'Porutham / Guna matching with detailed notes',
      'Dosha check and remedies (if any)',
      'Overall compatibility verdict & recommendation',
    ],
    this.deliveryTime = 'Within 2 working days after your appointment',
    this.serviceCharge = 499,
    this.expertName = 'Our Astrology Expert',
    this.expertPhotoUrl = '',
    this.expertExperience = '15+ years experience',
    this.expertSpecialization = 'Tamil Jathagam · Porutham Matching',
    this.expertIntro =
        'A trusted astrologer with years of experience in marriage horoscope '
            'matching, guiding families with clear and reliable compatibility '
            'analysis.',
    this.services = const [
      'Horoscope (Jathagam) Compatibility Matching',
      'Star & Rasi Porutham Analysis',
      'Dosha Check & Remedies',
      'Marriage Muhurtham Guidance',
      'Personal Astrology Consultation',
    ],
    this.expertContactPhone = '',
    this.officeAddress =
        'Jothida Matrimony Office, Main Road, Tamil Nadu',
    this.officeContactNumber = '+91 90000 00000',
    this.workingWeekdays = const [1, 2, 3, 4, 5],
    this.slotStartMinutes = 600, // 10:00 AM
    this.slotEndMinutes = 1020, // 5:00 PM
    this.lunchStartMinutes = 780, // 1:00 PM
    this.lunchEndMinutes = 840, // 2:00 PM
    this.slotDurationMinutes = 60,
    this.maxAdvanceWorkingDays = 5,
    this.bookingEnabled = true,
    this.holidayDates = const [],
    this.disabledSlotMinutes = const [],
    this.appointmentRules =
        'This is an in-person office visit. Please arrive 10 minutes before '
            'your slot and carry both horoscopes.',
    this.internalUid = '',
  });

  /// Built-in defaults used before any admin edit exists.
  static const AstrologyServiceConfig defaults = AstrologyServiceConfig();

  /// The number to dial from "Contact Expert" (expert phone → office number).
  String get contactPhone =>
      expertContactPhone.trim().isNotEmpty
          ? expertContactPhone.trim()
          : officeContactNumber;

  static List<String> _toStringList(dynamic v, List<String> fallback) {
    if (v is List && v.isNotEmpty) return v.map((e) => e.toString()).toList();
    return fallback;
  }

  static List<int> _toIntList(dynamic v, List<int> fallback) {
    if (v is List && v.isNotEmpty) {
      return v.map((e) => (e as num).toInt()).toList();
    }
    return fallback;
  }

  static int _toInt(dynamic v, int fallback) =>
      v is num ? v.toInt() : fallback;

  static String _toStr(dynamic v, String fallback) =>
      (v is String && v.trim().isNotEmpty) ? v : fallback;

  factory AstrologyServiceConfig.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    const def = AstrologyServiceConfig.defaults;
    return AstrologyServiceConfig(
      serviceIntro: _toStr(d['serviceIntro'], def.serviceIntro),
      reportIncludes: _toStringList(d['reportIncludes'], def.reportIncludes),
      deliveryTime: _toStr(d['deliveryTime'], def.deliveryTime),
      serviceCharge: _toInt(d['serviceCharge'], def.serviceCharge),
      expertName: _toStr(d['expertName'], def.expertName),
      expertPhotoUrl: (d['expertPhotoUrl'] ?? '').toString(),
      expertExperience: _toStr(d['expertExperience'], def.expertExperience),
      expertSpecialization:
          _toStr(d['expertSpecialization'], def.expertSpecialization),
      expertIntro: _toStr(d['expertIntro'], def.expertIntro),
      services: _toStringList(d['services'], def.services),
      expertContactPhone: (d['expertContactPhone'] ?? '').toString(),
      officeAddress: _toStr(d['officeAddress'], def.officeAddress),
      officeContactNumber:
          _toStr(d['officeContactNumber'], def.officeContactNumber),
      workingWeekdays: _toIntList(d['workingWeekdays'], def.workingWeekdays),
      slotStartMinutes: _toInt(d['slotStartMinutes'], def.slotStartMinutes),
      slotEndMinutes: _toInt(d['slotEndMinutes'], def.slotEndMinutes),
      lunchStartMinutes: _toInt(d['lunchStartMinutes'], def.lunchStartMinutes),
      lunchEndMinutes: _toInt(d['lunchEndMinutes'], def.lunchEndMinutes),
      slotDurationMinutes:
          _toInt(d['slotDurationMinutes'], def.slotDurationMinutes),
      maxAdvanceWorkingDays:
          _toInt(d['maxAdvanceWorkingDays'], def.maxAdvanceWorkingDays),
      bookingEnabled: d['bookingEnabled'] is bool
          ? d['bookingEnabled'] as bool
          : def.bookingEnabled,
      holidayDates: _toStringList(d['holidayDates'], def.holidayDates),
      disabledSlotMinutes:
          _toIntList(d['disabledSlotMinutes'], def.disabledSlotMinutes),
      appointmentRules: _toStr(d['appointmentRules'], def.appointmentRules),
      internalUid: (d['internalUid'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'serviceIntro': serviceIntro,
        'reportIncludes': reportIncludes,
        'deliveryTime': deliveryTime,
        'serviceCharge': serviceCharge,
        'expertName': expertName,
        'expertPhotoUrl': expertPhotoUrl,
        'expertExperience': expertExperience,
        'expertSpecialization': expertSpecialization,
        'expertIntro': expertIntro,
        'services': services,
        'expertContactPhone': expertContactPhone,
        'officeAddress': officeAddress,
        'officeContactNumber': officeContactNumber,
        'workingWeekdays': workingWeekdays,
        'slotStartMinutes': slotStartMinutes,
        'slotEndMinutes': slotEndMinutes,
        'lunchStartMinutes': lunchStartMinutes,
        'lunchEndMinutes': lunchEndMinutes,
        'slotDurationMinutes': slotDurationMinutes,
        'maxAdvanceWorkingDays': maxAdvanceWorkingDays,
        'bookingEnabled': bookingEnabled,
        'holidayDates': holidayDates,
        'disabledSlotMinutes': disabledSlotMinutes,
        'appointmentRules': appointmentRules,
        'internalUid': internalUid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  AstrologyServiceConfig copyWith({
    String? serviceIntro,
    List<String>? reportIncludes,
    String? deliveryTime,
    int? serviceCharge,
    String? expertName,
    String? expertPhotoUrl,
    String? expertExperience,
    String? expertSpecialization,
    String? expertIntro,
    List<String>? services,
    String? expertContactPhone,
    String? officeAddress,
    String? officeContactNumber,
    List<int>? workingWeekdays,
    int? slotStartMinutes,
    int? slotEndMinutes,
    int? lunchStartMinutes,
    int? lunchEndMinutes,
    int? slotDurationMinutes,
    int? maxAdvanceWorkingDays,
    bool? bookingEnabled,
    List<String>? holidayDates,
    List<int>? disabledSlotMinutes,
    String? appointmentRules,
    String? internalUid,
  }) =>
      AstrologyServiceConfig(
        serviceIntro: serviceIntro ?? this.serviceIntro,
        reportIncludes: reportIncludes ?? this.reportIncludes,
        deliveryTime: deliveryTime ?? this.deliveryTime,
        serviceCharge: serviceCharge ?? this.serviceCharge,
        expertName: expertName ?? this.expertName,
        expertPhotoUrl: expertPhotoUrl ?? this.expertPhotoUrl,
        expertExperience: expertExperience ?? this.expertExperience,
        expertSpecialization: expertSpecialization ?? this.expertSpecialization,
        expertIntro: expertIntro ?? this.expertIntro,
        services: services ?? this.services,
        expertContactPhone: expertContactPhone ?? this.expertContactPhone,
        officeAddress: officeAddress ?? this.officeAddress,
        officeContactNumber: officeContactNumber ?? this.officeContactNumber,
        workingWeekdays: workingWeekdays ?? this.workingWeekdays,
        slotStartMinutes: slotStartMinutes ?? this.slotStartMinutes,
        slotEndMinutes: slotEndMinutes ?? this.slotEndMinutes,
        lunchStartMinutes: lunchStartMinutes ?? this.lunchStartMinutes,
        lunchEndMinutes: lunchEndMinutes ?? this.lunchEndMinutes,
        slotDurationMinutes: slotDurationMinutes ?? this.slotDurationMinutes,
        maxAdvanceWorkingDays:
            maxAdvanceWorkingDays ?? this.maxAdvanceWorkingDays,
        bookingEnabled: bookingEnabled ?? this.bookingEnabled,
        holidayDates: holidayDates ?? this.holidayDates,
        disabledSlotMinutes: disabledSlotMinutes ?? this.disabledSlotMinutes,
        appointmentRules: appointmentRules ?? this.appointmentRules,
        internalUid: internalUid ?? this.internalUid,
      );
}
