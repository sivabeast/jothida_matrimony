import 'package:cloud_firestore/cloud_firestore.dart';

/// A certificate / qualification shown on the Astrology page. Image OR PDF.
/// Stored inside the config doc under a `certificates` array.
class AstrologyCertificate {
  final String id;
  final String title;
  final String description;
  final String url; // Cloudinary public URL of the image/PDF
  final String fileType; // 'pdf' | 'image'

  const AstrologyCertificate({
    required this.id,
    required this.title,
    this.description = '',
    required this.url,
    this.fileType = 'image',
  });

  bool get isPdf => fileType.toLowerCase() == 'pdf';

  factory AstrologyCertificate.fromMap(Map<String, dynamic> m) =>
      AstrologyCertificate(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? 'Certificate').toString(),
        description: (m['description'] ?? '').toString(),
        url: (m['url'] ?? '').toString(),
        fileType: (m['fileType'] ?? 'image').toString().toLowerCase(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'url': url,
        'fileType': fileType,
      };

  AstrologyCertificate copyWith(
          {String? title, String? description, String? url, String? fileType}) =>
      AstrologyCertificate(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        url: url ?? this.url,
        fileType: fileType ?? this.fileType,
      );
}

/// An award / medal / recognition shown on the Astrology page.
class AstrologyAward {
  final String id;
  final String title;
  final String description;
  final String year; // optional
  final String imageUrl;

  const AstrologyAward({
    required this.id,
    required this.title,
    this.description = '',
    this.year = '',
    this.imageUrl = '',
  });

  factory AstrologyAward.fromMap(Map<String, dynamic> m) => AstrologyAward(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        year: (m['year'] ?? '').toString(),
        imageUrl: (m['imageUrl'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'year': year,
        'imageUrl': imageUrl,
      };

  AstrologyAward copyWith({
    String? title,
    String? description,
    String? year,
    String? imageUrl,
  }) =>
      AstrologyAward(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        year: year ?? this.year,
        imageUrl: imageUrl ?? this.imageUrl,
      );
}

/// A News & Media item (article, magazine, newspaper, TV interview, recognition)
/// shown on the Astrology page.
class AstrologyNews {
  final String id;
  final String headline;
  final String description;
  final String date; // free-text or yyyy-MM-dd
  final String source;
  final String imageUrl;

  const AstrologyNews({
    required this.id,
    required this.headline,
    this.description = '',
    this.date = '',
    this.source = '',
    this.imageUrl = '',
  });

  factory AstrologyNews.fromMap(Map<String, dynamic> m) => AstrologyNews(
        id: (m['id'] ?? '').toString(),
        headline: (m['headline'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        date: (m['date'] ?? '').toString(),
        source: (m['source'] ?? '').toString(),
        imageUrl: (m['imageUrl'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'headline': headline,
        'description': description,
        'date': date,
        'source': source,
        'imageUrl': imageUrl,
      };

  AstrologyNews copyWith({
    String? headline,
    String? description,
    String? date,
    String? source,
    String? imageUrl,
  }) =>
      AstrologyNews(
        id: id,
        headline: headline ?? this.headline,
        description: description ?? this.description,
        date: date ?? this.date,
        source: source ?? this.source,
        imageUrl: imageUrl ?? this.imageUrl,
      );
}

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

  // ── Astrologer commission (per COMPLETED request) ───────────────────────
  /// Commission paid to the assigned astrologer for each completed Horoscope
  /// Analysis report (₹). Drives the astrologer earnings calculation.
  final int analysisCommission;

  /// Commission paid to the astrologer for each completed direct office-visit
  /// appointment (₹).
  final int appointmentCommission;

  // ── Meet Our Astrology Expert card ─────────────────────────────────────
  final String expertName;
  final String expertPhotoUrl;
  final String expertExperience; // e.g. "15+ years"
  final String expertSpecialization; // e.g. "Tamil Jathagam · Porutham"
  final String expertIntro;

  /// Professional services the astrologer offers, shown on the user-facing
  /// Astrology page ("Services Offered"). Admin-managed — never hardcoded.
  final List<String> services;

  /// Certificates / qualifications (image or PDF), admin-uploaded.
  final List<AstrologyCertificate> certificates;

  /// Awards / medals / recognitions, admin-managed.
  final List<AstrologyAward> awards;

  /// News & media features, admin-managed.
  final List<AstrologyNews> news;

  /// Phone number the "Contact Expert" dialer opens. Falls back to
  /// [officeContactNumber] when empty.
  final String expertContactPhone;

  // ── Office / appointment confirmation + contact details ────────────────
  final String officeAddress;
  final String officeContactNumber; // primary Phone

  /// Additional contact channels for the user-facing Contact Details section.
  final String whatsappNumber;
  final String email;

  /// Free-text location / Google Maps link shown in Contact Details.
  final String mapLocation;

  // ── Appointment slot configuration (minutes-from-midnight) ─────────────
  /// Mon→Fri only (spec §8). Weekday ints 1..7 (Mon=1). Default Mon–Fri.
  final List<int> workingWeekdays;
  final int slotStartMinutes; // 10:00 AM
  final int slotEndMinutes; // 5:00 PM
  final int lunchStartMinutes; // 1:00 PM
  final int lunchEndMinutes; // 2:00 PM
  final int slotDurationMinutes; // 60

  /// Gap (minutes) inserted AFTER each slot before the next one starts. 0 = no
  /// break (back-to-back slots). Admin picks 5 / 10 / 15 / 30.
  final int breakDurationMinutes;

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
    this.deliveryTime = 'Within 2 working days after your payment is confirmed',
    this.serviceCharge = 399,
    this.analysisCommission = 150,
    this.appointmentCommission = 20,
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
    this.certificates = const [],
    this.awards = const [],
    this.news = const [],
    this.expertContactPhone = '',
    this.officeAddress =
        'Jothida Matrimony Office, Main Road, Tamil Nadu',
    this.officeContactNumber = '+91 90000 00000',
    this.whatsappNumber = '',
    this.email = '',
    this.mapLocation = '',
    this.workingWeekdays = const [1, 2, 3, 4, 5],
    this.slotStartMinutes = 600, // 10:00 AM
    this.slotEndMinutes = 1020, // 5:00 PM
    this.lunchStartMinutes = 780, // 1:00 PM
    this.lunchEndMinutes = 840, // 2:00 PM
    this.slotDurationMinutes = 60,
    this.breakDurationMinutes = 0,
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

  /// Like [_toStringList] but, when the FIELD EXISTS (even as an empty list),
  /// the stored value wins — so an admin clearing every entry does NOT revert
  /// to the built-in defaults. Used for editable lists (services).
  static List<String> _editableStringList(
      Map<String, dynamic> d, String key, List<String> fallback) {
    if (!d.containsKey(key)) return fallback;
    final v = d[key];
    if (v is List) return v.map((e) => e.toString()).toList();
    return fallback;
  }

  static List<Map<String, dynamic>> _toMapList(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  factory AstrologyServiceConfig.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    const def = AstrologyServiceConfig.defaults;
    return AstrologyServiceConfig(
      serviceIntro: _toStr(d['serviceIntro'], def.serviceIntro),
      reportIncludes: _toStringList(d['reportIncludes'], def.reportIncludes),
      deliveryTime: _toStr(d['deliveryTime'], def.deliveryTime),
      serviceCharge: _toInt(d['serviceCharge'], def.serviceCharge),
      analysisCommission:
          _toInt(d['analysisCommission'], def.analysisCommission),
      appointmentCommission:
          _toInt(d['appointmentCommission'], def.appointmentCommission),
      expertName: _toStr(d['expertName'], def.expertName),
      expertPhotoUrl: (d['expertPhotoUrl'] ?? '').toString(),
      expertExperience: _toStr(d['expertExperience'], def.expertExperience),
      expertSpecialization:
          _toStr(d['expertSpecialization'], def.expertSpecialization),
      expertIntro: _toStr(d['expertIntro'], def.expertIntro),
      services: _editableStringList(
          Map<String, dynamic>.from(d), 'services', def.services),
      certificates: _toMapList(d['certificates'])
          .map(AstrologyCertificate.fromMap)
          .toList(),
      awards: _toMapList(d['awards']).map(AstrologyAward.fromMap).toList(),
      news: _toMapList(d['news']).map(AstrologyNews.fromMap).toList(),
      expertContactPhone: (d['expertContactPhone'] ?? '').toString(),
      officeAddress: _toStr(d['officeAddress'], def.officeAddress),
      officeContactNumber:
          _toStr(d['officeContactNumber'], def.officeContactNumber),
      whatsappNumber: (d['whatsappNumber'] ?? '').toString(),
      email: (d['email'] ?? '').toString(),
      mapLocation: (d['mapLocation'] ?? '').toString(),
      workingWeekdays: _toIntList(d['workingWeekdays'], def.workingWeekdays),
      slotStartMinutes: _toInt(d['slotStartMinutes'], def.slotStartMinutes),
      slotEndMinutes: _toInt(d['slotEndMinutes'], def.slotEndMinutes),
      lunchStartMinutes: _toInt(d['lunchStartMinutes'], def.lunchStartMinutes),
      lunchEndMinutes: _toInt(d['lunchEndMinutes'], def.lunchEndMinutes),
      slotDurationMinutes:
          _toInt(d['slotDurationMinutes'], def.slotDurationMinutes),
      breakDurationMinutes:
          _toInt(d['breakDurationMinutes'], def.breakDurationMinutes),
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
        'analysisCommission': analysisCommission,
        'appointmentCommission': appointmentCommission,
        'expertName': expertName,
        'expertPhotoUrl': expertPhotoUrl,
        'expertExperience': expertExperience,
        'expertSpecialization': expertSpecialization,
        'expertIntro': expertIntro,
        'services': services,
        'certificates': certificates.map((e) => e.toMap()).toList(),
        'awards': awards.map((e) => e.toMap()).toList(),
        'news': news.map((e) => e.toMap()).toList(),
        'expertContactPhone': expertContactPhone,
        'officeAddress': officeAddress,
        'officeContactNumber': officeContactNumber,
        'whatsappNumber': whatsappNumber,
        'email': email,
        'mapLocation': mapLocation,
        'workingWeekdays': workingWeekdays,
        'slotStartMinutes': slotStartMinutes,
        'slotEndMinutes': slotEndMinutes,
        'lunchStartMinutes': lunchStartMinutes,
        'lunchEndMinutes': lunchEndMinutes,
        'slotDurationMinutes': slotDurationMinutes,
        'breakDurationMinutes': breakDurationMinutes,
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
    int? analysisCommission,
    int? appointmentCommission,
    String? expertName,
    String? expertPhotoUrl,
    String? expertExperience,
    String? expertSpecialization,
    String? expertIntro,
    List<String>? services,
    List<AstrologyCertificate>? certificates,
    List<AstrologyAward>? awards,
    List<AstrologyNews>? news,
    String? expertContactPhone,
    String? officeAddress,
    String? officeContactNumber,
    String? whatsappNumber,
    String? email,
    String? mapLocation,
    List<int>? workingWeekdays,
    int? slotStartMinutes,
    int? slotEndMinutes,
    int? lunchStartMinutes,
    int? lunchEndMinutes,
    int? slotDurationMinutes,
    int? breakDurationMinutes,
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
        analysisCommission: analysisCommission ?? this.analysisCommission,
        appointmentCommission:
            appointmentCommission ?? this.appointmentCommission,
        expertName: expertName ?? this.expertName,
        expertPhotoUrl: expertPhotoUrl ?? this.expertPhotoUrl,
        expertExperience: expertExperience ?? this.expertExperience,
        expertSpecialization: expertSpecialization ?? this.expertSpecialization,
        expertIntro: expertIntro ?? this.expertIntro,
        services: services ?? this.services,
        certificates: certificates ?? this.certificates,
        awards: awards ?? this.awards,
        news: news ?? this.news,
        expertContactPhone: expertContactPhone ?? this.expertContactPhone,
        officeAddress: officeAddress ?? this.officeAddress,
        officeContactNumber: officeContactNumber ?? this.officeContactNumber,
        whatsappNumber: whatsappNumber ?? this.whatsappNumber,
        email: email ?? this.email,
        mapLocation: mapLocation ?? this.mapLocation,
        workingWeekdays: workingWeekdays ?? this.workingWeekdays,
        slotStartMinutes: slotStartMinutes ?? this.slotStartMinutes,
        slotEndMinutes: slotEndMinutes ?? this.slotEndMinutes,
        lunchStartMinutes: lunchStartMinutes ?? this.lunchStartMinutes,
        lunchEndMinutes: lunchEndMinutes ?? this.lunchEndMinutes,
        slotDurationMinutes: slotDurationMinutes ?? this.slotDurationMinutes,
        breakDurationMinutes: breakDurationMinutes ?? this.breakDurationMinutes,
        maxAdvanceWorkingDays:
            maxAdvanceWorkingDays ?? this.maxAdvanceWorkingDays,
        bookingEnabled: bookingEnabled ?? this.bookingEnabled,
        holidayDates: holidayDates ?? this.holidayDates,
        disabledSlotMinutes: disabledSlotMinutes ?? this.disabledSlotMinutes,
        appointmentRules: appointmentRules ?? this.appointmentRules,
        internalUid: internalUid ?? this.internalUid,
      );
}
