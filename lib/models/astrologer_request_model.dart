import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/working_hours.dart';

/// Kind of request a matrimony user sends to an astrologer.
enum AstrologerRequestType { consultation, inquiry, matching }

/// Lifecycle of a request.
///
/// NOTE: "Expired" and "Reassigned" are intentionally NOT enum values — they
/// are represented by the [AstrologerRequestModel.expired] /
/// [AstrologerRequestModel.reassigned] flags and surfaced through
/// [AstrologerRequestModel.displayStatusKey]. Keeping the enum at four values
/// avoids breaking the many `switch`es across the app while still giving the
/// booking workflow its richer, user-visible states.
enum AstrologerRequestStatus { pending, accepted, completed, rejected }

/// What should happen if the selected astrologer does NOT respond before the
/// booking expires. Chosen by the user when booking a match analysis.
///
/// SPEC RULE: a booking always belongs to exactly ONE astrologer at a time —
/// these modes only decide *who* may pick the next astrologer after expiry,
/// never fan a booking out to several astrologers at once.
enum BookingReassignMode {
  /// Option 1 — wait only for this astrologer. Booking simply stays pending /
  /// expired; the user can take manual action later.
  waitOnly,

  /// Option 2 — the user will choose another astrologer later. On expiry the
  /// user is notified and can re-point the booking to a new astrologer.
  chooseLater,

  /// Option 3 — allow the admin to assign another astrologer. On expiry the
  /// booking shows up under Admin → Expired Bookings for manual reassignment.
  allowAdmin,
}

extension BookingReassignModeX on BookingReassignMode {
  /// Stable key persisted to Firestore.
  String get key => name;

  /// English label (localised copy lives in the ARB files keyed by [key]).
  String get label {
    switch (this) {
      case BookingReassignMode.waitOnly:
        return 'Wait only for this astrologer';
      case BookingReassignMode.chooseLater:
        return 'Let me choose another astrologer later';
      case BookingReassignMode.allowAdmin:
        return 'Allow admin to assign another astrologer';
    }
  }

  static BookingReassignMode fromKey(String? key) =>
      BookingReassignMode.values.firstWhere(
        (m) => m.name == key,
        orElse: () => BookingReassignMode.waitOnly,
      );
}

/// Default window an astrologer has to respond before a booking expires.
const Duration kBookingResponseWindow = Duration(hours: 24);

extension AstrologerRequestTypeX on AstrologerRequestType {
  String get label {
    switch (this) {
      case AstrologerRequestType.consultation:
        return 'Consultation';
      case AstrologerRequestType.inquiry:
        return 'Inquiry';
      case AstrologerRequestType.matching:
        return 'Match Analysis';
    }
  }
}

extension AstrologerRequestStatusX on AstrologerRequestStatus {
  String get label {
    switch (this) {
      case AstrologerRequestStatus.pending:
        return 'Pending';
      case AstrologerRequestStatus.accepted:
        return 'Accepted';
      case AstrologerRequestStatus.completed:
        return 'Completed';
      case AstrologerRequestStatus.rejected:
        return 'Rejected';
    }
  }
}

/// One immutable entry in a booking's audit trail (newest appended last):
/// "Booking created", "Sent to Astrologer A", "Expired",
/// "Assigned by Admin to Astrologer B", "Accepted", …
class BookingHistoryEntry {
  final DateTime at;
  final String label;

  const BookingHistoryEntry({required this.at, required this.label});

  factory BookingHistoryEntry.fromMap(Map<String, dynamic> m) =>
      BookingHistoryEntry(
        at: m['at'] is Timestamp
            ? (m['at'] as Timestamp).toDate()
            : DateTime.now(),
        label: m['label']?.toString() ?? '',
      );

  /// Firestore map. Uses a client [Timestamp] (NOT a server timestamp) because
  /// `FieldValue.serverTimestamp()` is not allowed inside `arrayUnion`.
  Map<String, dynamic> toMap() => {
        'at': Timestamp.fromDate(at),
        'label': label,
      };

  static BookingHistoryEntry now(String label) =>
      BookingHistoryEntry(at: DateTime.now(), label: label);
}

/// A request from a matrimony user to an astrologer.
///
/// Firestore: `astrologer_requests/{id}`
/// { astrologerId, astrologerName, userId, userName, userPhotoUrl, type, status,
///   message, amount, profileAId, profileAName, profileBId, profileBName,
///   analysisText, analysisImages, analysisPdfs, createdAt, respondedAt,
///   completedAt, reassignMode, expiresAt, expired, expiredAt, reassigned,
///   reassignedAt, userLanguage, history }
///
/// For [AstrologerRequestType.matching] (a "Book Match Analysis" booking),
/// `profileAId` / `profileBId` are the GROOM / BRIDE matrimony profiles whose
/// horoscopes should be compared, and `message` is the user's optional note.
/// Once the astrologer completes the analysis, `analysisText` /
/// `analysisImages` / `analysisPdfs` hold the report the user can read back.
class AstrologerRequestModel {
  final String id;
  final String astrologerId;
  final String astrologerName;

  /// The responder's REAL Firebase uid. Match-analysis requests are addressed to
  /// the synthetic [kInternalAstrologyId], so this is empty until the internal
  /// astrology account accepts — at which point it stamps its actual uid here so
  /// the USER side can open the same chat thread the internal account created.
  final String astrologerUid;

  /// The assigned astrologer's registered Gmail. This is the STABLE key the
  /// astrologer dashboard queries on — it is stamped at assignment time even
  /// before the astrologer has signed in (so requests appear the moment they
  /// first log in), whereas [astrologerUid] is only filled once they do.
  final String astrologerEmail;

  /// When the request was assigned to its astrologer.
  final DateTime? assignedAt;

  /// Who performed the assignment: 'admin' | 'auto' (round robin) | ''.
  final String assignedBy;

  /// 'assigned' once an astrologer holds it; '' / 'unassigned' otherwise.
  final String assignmentStatus;

  /// Explicit astrologer-facing workflow state: 'new' → 'in_progress' →
  /// 'completed'. Kept in sync with [status]/[inProgress] and used by the
  /// astrologer dashboard tabs so a query can filter on it directly.
  final String workflowStatus;

  final String userId;
  final String userName;
  final String userPhotoUrl;
  final String userLocation;

  /// Denormalised booking user's mobile number, captured at booking time so the
  /// admin Appointment Management list can display + search by mobile without an
  /// extra profile read. Empty for older records.
  final String userPhone;

  final AstrologerRequestType type;
  final AstrologerRequestStatus status;
  final String message;
  final int amount;

  // ── Match-analysis (type == matching): groom / bride profiles ──────────────
  final String? profileAId; // Groom
  final String? profileAName;
  final String? profileBId; // Bride
  final String? profileBName;

  // ── Astrologer's submitted analysis (populated once completed) ─────────────
  final String analysisText;
  final List<String> analysisImages;
  final List<String> analysisPdfs;

  final DateTime createdAt;
  final DateTime? respondedAt;
  final DateTime? completedAt;

  // ── Reassignment workflow ───────────────────────────────────────────────────
  /// What happens if this astrologer doesn't respond before [expiresAt].
  final BookingReassignMode reassignMode;

  /// Hard deadline for the current astrologer to respond. Past this, the
  /// booking is treated as Expired ([isEffectivelyExpired]).
  final DateTime? expiresAt;

  /// Persisted "expired" flag, set by the client-side expiry sweep once the
  /// deadline lapses (there is no Cloud Functions backend). Display also falls
  /// back to a live time check via [isExpiredByTime] before the flag is written.
  final bool expired;
  final DateTime? expiredAt;

  /// Set when the booking has been re-pointed to a different astrologer (by the
  /// admin, or by the user in [BookingReassignMode.chooseLater]).
  final bool reassigned;
  final DateTime? reassignedAt;

  /// The user's preferred language ('ta' | 'en') captured at booking time, so
  /// the astrologer's report is written/displayed in the user's language.
  final String userLanguage;

  /// Append-only audit trail of the booking's lifecycle.
  final List<BookingHistoryEntry> history;

  // ── Payment (dev-mode) ──────────────────────────────────────────────────────
  /// Whether the user has paid the analysis fee. Kept as a FLAG (not an enum
  /// value) so the 4-value [AstrologerRequestStatus] and its many switches stay
  /// intact, mirroring how `expired` / `reassigned` are modelled. The spec
  /// payment step (Accepted → Payment Pending → Paid → Completed) is driven by
  /// this flag together with [status].
  final bool paid;
  final DateTime? paidAt;

  /// Demo transaction id generated at payment time (real gateway is a future
  /// extension point — see [kSubscriptionTestMode]).
  final String paymentId;

  // ── Analysis progress (spec §11: Accepted → Analysis In Progress) ──────────
  /// Set once the astrologer begins working on an accepted booking ("Start
  /// Analysis"). Distinguishes the "Accepted" and "In Progress" buckets on the
  /// astrologer Requests page without adding a new [AstrologerRequestStatus]
  /// value (which would break the app's many 4-value switches).
  final bool inProgress;
  final DateTime? startedAt;

  // ── In-person appointment (Horoscope Compatibility Report booking) ─────────
  /// The office-visit day (date-only). Null for non-appointment requests.
  final DateTime? visitDate;

  /// Visit slot start as minutes-from-midnight (e.g. 10:00 AM = 600). Null when
  /// there is no appointment.
  final int? slotStartMinutes;

  /// Office address + contact number snapshotted at booking time, so the
  /// confirmation stays stable even if the admin later edits the service config.
  final String officeAddress;
  final String officeContact;

  const AstrologerRequestModel({
    required this.id,
    required this.astrologerId,
    this.astrologerName = '',
    this.astrologerUid = '',
    this.astrologerEmail = '',
    this.assignedAt,
    this.assignedBy = '',
    this.assignmentStatus = '',
    this.workflowStatus = '',
    required this.userId,
    required this.userName,
    this.userPhotoUrl = '',
    this.userLocation = '',
    this.userPhone = '',
    required this.type,
    this.status = AstrologerRequestStatus.pending,
    this.message = '',
    this.amount = 0,
    this.profileAId,
    this.profileAName,
    this.profileBId,
    this.profileBName,
    this.analysisText = '',
    this.analysisImages = const [],
    this.analysisPdfs = const [],
    required this.createdAt,
    this.respondedAt,
    this.completedAt,
    this.reassignMode = BookingReassignMode.waitOnly,
    this.expiresAt,
    this.expired = false,
    this.expiredAt,
    this.reassigned = false,
    this.reassignedAt,
    this.userLanguage = 'en',
    this.history = const [],
    this.paid = false,
    this.paidAt,
    this.paymentId = '',
    this.inProgress = false,
    this.startedAt,
    this.visitDate,
    this.slotStartMinutes,
    this.officeAddress = '',
    this.officeContact = '',
  });

  /// True for a "Book Match Analysis" booking (groom + bride porutham request).
  bool get isMatchAnalysis => type == AstrologerRequestType.matching;

  /// True once an astrologer has actually been assigned (auto or manual). The
  /// admin shows the assigned name/email + the Reassign action only when true.
  bool get isAssigned => astrologerEmail.trim().isNotEmpty;

  /// True when this request was purchased via an in-person appointment.
  bool get hasAppointment => visitDate != null && slotStartMinutes != null;

  /// `yyyy-MM-dd` of the appointment day (empty when none).
  String get visitDateKey => visitDate == null
      ? ''
      : '${visitDate!.year.toString().padLeft(4, '0')}-${visitDate!.month.toString().padLeft(2, '0')}-${visitDate!.day.toString().padLeft(2, '0')}';

  /// `HHmm` of the slot (empty when none).
  String get slotKey => slotStartMinutes == null
      ? ''
      : '${(slotStartMinutes! ~/ 60).toString().padLeft(2, '0')}${(slotStartMinutes! % 60).toString().padLeft(2, '0')}';

  /// Deterministic doc id for an appointment so one slot can be held by only
  /// one user (a second booking of the same slot fails the create).
  static String appointmentDocId(
      String astrologerId, DateTime date, int slotStartMinutes) {
    final dateKey =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final slotKey =
        '${(slotStartMinutes ~/ 60).toString().padLeft(2, '0')}${(slotStartMinutes % 60).toString().padLeft(2, '0')}';
    return '${astrologerId}_${dateKey}_$slotKey';
  }

  /// Display bucket for the astrologer Requests page (spec §2 / §11):
  /// 'pending' | 'expired' | 'accepted' | 'inProgress' | 'completed' |
  /// 'rejected'. An accepted booking the astrologer has started working on is
  /// "In Progress"; otherwise it is "Accepted".
  String get displayBucket {
    if (status == AstrologerRequestStatus.pending) {
      return isEffectivelyExpired ? 'expired' : 'pending';
    }
    if (status == AstrologerRequestStatus.accepted) {
      return inProgress ? 'inProgress' : 'accepted';
    }
    return status.name; // completed | rejected
  }

  /// WORKING time left before the acceptance deadline lapses (spec §6/§7).
  /// Pauses overnight (00:00–07:00). Null when there is no deadline; zero or
  /// negative once expired.
  Duration? get workingTimeRemaining => expiresAt == null
      ? null
      : workingTimeBetween(DateTime.now(), expiresAt!);

  // Explicit groom / bride accessors (the booking stores profileA = groom,
  // profileB = bride). Also persisted under `groomProfileId` / `brideProfileId`
  // in Firestore for clarity.
  String? get groomProfileId => profileAId;
  String? get groomName => profileAName;
  String? get brideProfileId => profileBId;
  String? get brideName => profileBName;

  /// True once the astrologer has submitted a report.
  bool get hasAnalysis =>
      analysisText.trim().isNotEmpty ||
      analysisImages.isNotEmpty ||
      analysisPdfs.isNotEmpty;

  /// True when the response deadline has lapsed while still pending (live check,
  /// independent of whether the [expired] flag has been written yet).
  bool get isExpiredByTime =>
      status == AstrologerRequestStatus.pending &&
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!);

  /// Whether the booking should be shown / treated as Expired.
  bool get isEffectivelyExpired =>
      status == AstrologerRequestStatus.pending && (expired || isExpiredByTime);

  /// True while the booking is awaiting the current astrologer's accept/reject.
  bool get isAwaitingResponse =>
      status == AstrologerRequestStatus.pending && !isEffectivelyExpired;

  /// Stable status key driving labels/colours (and ARB localisation):
  /// 'expired' | 'reassigned' | 'pending' | 'accepted' | 'completed' |
  /// 'rejected'.
  String get displayStatusKey {
    if (isEffectivelyExpired) return 'expired';
    if (status == AstrologerRequestStatus.pending && reassigned) {
      return 'reassigned';
    }
    return status.name;
  }

  /// True once the astrologer has accepted but the user hasn't paid the fee yet
  /// (the spec's "Payment Pending" gate). Bookings with no fee skip payment.
  bool get awaitingPayment =>
      status == AstrologerRequestStatus.accepted && amount > 0 && !paid;

  /// Payment status key driving the Bookings page / cards: 'paid' | 'pending'
  /// (payment due) | 'none' (no payment due yet — still pending/expired/free).
  String get paymentStatusKey {
    if (paid) return 'paid';
    if (amount > 0 &&
        (status == AstrologerRequestStatus.accepted ||
            status == AstrologerRequestStatus.completed)) {
      return 'pending';
    }
    return 'none';
  }

  /// Human label for [paymentStatusKey].
  String get paymentStatusLabel {
    switch (paymentStatusKey) {
      case 'paid':
        return 'Paid';
      case 'pending':
        return 'Payment Pending';
      default:
        return 'Not Due';
    }
  }

  /// Whole hours/minutes left before expiry (negative once expired).
  Duration? get timeUntilExpiry =>
      expiresAt == null ? null : expiresAt!.difference(DateTime.now());

  static List<String> _toStringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String && v.isNotEmpty) return [v];
    return const [];
  }

  static DateTime? _toDate(dynamic v) => v is Timestamp ? v.toDate() : null;

  static List<BookingHistoryEntry> _toHistory(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) => BookingHistoryEntry.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  factory AstrologerRequestModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AstrologerRequestModel(
      id: doc.id,
      astrologerId: d['astrologerId'] ?? '',
      astrologerName: d['astrologerName'] ?? '',
      astrologerUid: d['astrologerUid'] ?? '',
      astrologerEmail: d['astrologerEmail'] ?? '',
      assignedAt: _toDate(d['assignedAt']),
      assignedBy: d['assignedBy'] ?? '',
      assignmentStatus: d['assignmentStatus'] ?? '',
      workflowStatus: d['workflowStatus'] ?? '',
      userId: d['userId'] ?? '',
      userName: d['userName'] ?? 'User',
      userPhotoUrl: d['userPhotoUrl'] ?? '',
      userLocation: d['userLocation'] ?? d['location'] ?? '',
      userPhone: (d['userPhone'] ?? '').toString(),
      type: AstrologerRequestType.values.firstWhere(
        (t) => t.name == (d['type'] ?? 'inquiry'),
        orElse: () => AstrologerRequestType.inquiry,
      ),
      status: AstrologerRequestStatus.values.firstWhere(
        (s) => s.name == (d['status'] ?? 'pending'),
        orElse: () => AstrologerRequestStatus.pending,
      ),
      message: d['message'] ?? '',
      amount: (d['amount'] ?? 0) is num ? (d['amount'] as num).toInt() : 0,
      // Read the explicit groom/bride field names, falling back to the
      // profileA/profileB names used by earlier documents.
      profileAId: d['profileAId'] ?? d['groomProfileId'],
      profileAName: d['profileAName'] ?? d['groomProfileName'],
      profileBId: d['profileBId'] ?? d['brideProfileId'],
      profileBName: d['profileBName'] ?? d['brideProfileName'],
      analysisText: d['analysisText'] ?? '',
      analysisImages: _toStringList(d['analysisImages']),
      analysisPdfs: _toStringList(d['analysisPdfs']),
      createdAt: _toDate(d['createdAt']) ?? DateTime.now(),
      respondedAt: _toDate(d['respondedAt']),
      completedAt: _toDate(d['completedAt']),
      reassignMode: BookingReassignModeX.fromKey(d['reassignMode']),
      expiresAt: _toDate(d['expiresAt']),
      expired: d['expired'] == true,
      expiredAt: _toDate(d['expiredAt']),
      reassigned: d['reassigned'] == true,
      reassignedAt: _toDate(d['reassignedAt']),
      userLanguage: (d['userLanguage'] ?? 'en').toString(),
      history: _toHistory(d['history']),
      paid: d['paid'] == true,
      paidAt: _toDate(d['paidAt']),
      paymentId: (d['paymentId'] ?? '').toString(),
      inProgress: d['inProgress'] == true,
      startedAt: _toDate(d['startedAt']),
      visitDate: _toDate(d['visitDate']),
      slotStartMinutes: (d['slotStartMinutes'] as num?)?.toInt(),
      officeAddress: (d['officeAddress'] ?? '').toString(),
      officeContact: (d['officeContact'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'astrologerId': astrologerId,
        'astrologerName': astrologerName,
        'astrologerUid': astrologerUid,
        'astrologerEmail': astrologerEmail,
        'assignedAt': assignedAt != null ? Timestamp.fromDate(assignedAt!) : null,
        'assignedBy': assignedBy,
        'assignmentStatus': assignmentStatus,
        'workflowStatus': workflowStatus,
        'userId': userId,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'userLocation': userLocation,
        'userPhone': userPhone,
        'type': type.name,
        'status': status.name,
        'message': message,
        'amount': amount,
        'profileAId': profileAId,
        'profileAName': profileAName,
        'profileBId': profileBId,
        'profileBName': profileBName,
        // Explicit groom/bride field names (kept in sync with profileA/profileB)
        // so every match-analysis booking stores groomProfileId & brideProfileId.
        'groomProfileId': profileAId,
        'groomProfileName': profileAName,
        'brideProfileId': profileBId,
        'brideProfileName': profileBName,
        'analysisText': analysisText,
        'analysisImages': analysisImages,
        'analysisPdfs': analysisPdfs,
        'createdAt': Timestamp.fromDate(createdAt),
        'respondedAt':
            respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
        'completedAt':
            completedAt != null ? Timestamp.fromDate(completedAt!) : null,
        'reassignMode': reassignMode.key,
        'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
        'expired': expired,
        'expiredAt': expiredAt != null ? Timestamp.fromDate(expiredAt!) : null,
        'reassigned': reassigned,
        'reassignedAt':
            reassignedAt != null ? Timestamp.fromDate(reassignedAt!) : null,
        'userLanguage': userLanguage,
        'history': history.map((h) => h.toMap()).toList(),
        'paid': paid,
        'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
        'paymentId': paymentId,
        'inProgress': inProgress,
        'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
        'visitDate': visitDate != null ? Timestamp.fromDate(visitDate!) : null,
        'slotStartMinutes': slotStartMinutes,
        // Denormalised keys so a date's taken slots can be derived without
        // parsing (mirrors the consultations booked-slots index).
        'visitDateKey': visitDateKey,
        'slotKey': slotKey,
        'officeAddress': officeAddress,
        'officeContact': officeContact,
      };

  AstrologerRequestModel copyWith({
    String? astrologerId,
    String? astrologerName,
    String? astrologerUid,
    String? astrologerEmail,
    DateTime? assignedAt,
    String? assignedBy,
    String? assignmentStatus,
    String? workflowStatus,
    AstrologerRequestStatus? status,
    String? analysisText,
    List<String>? analysisImages,
    List<String>? analysisPdfs,
    DateTime? respondedAt,
    DateTime? completedAt,
    BookingReassignMode? reassignMode,
    DateTime? expiresAt,
    bool? expired,
    DateTime? expiredAt,
    bool? reassigned,
    DateTime? reassignedAt,
    String? userLanguage,
    List<BookingHistoryEntry>? history,
    bool? paid,
    DateTime? paidAt,
    String? paymentId,
    bool? inProgress,
    DateTime? startedAt,
  }) =>
      AstrologerRequestModel(
        id: id,
        astrologerId: astrologerId ?? this.astrologerId,
        astrologerName: astrologerName ?? this.astrologerName,
        astrologerUid: astrologerUid ?? this.astrologerUid,
        astrologerEmail: astrologerEmail ?? this.astrologerEmail,
        assignedAt: assignedAt ?? this.assignedAt,
        assignedBy: assignedBy ?? this.assignedBy,
        assignmentStatus: assignmentStatus ?? this.assignmentStatus,
        workflowStatus: workflowStatus ?? this.workflowStatus,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        userLocation: userLocation,
        userPhone: userPhone,
        type: type,
        status: status ?? this.status,
        message: message,
        amount: amount,
        profileAId: profileAId,
        profileAName: profileAName,
        profileBId: profileBId,
        profileBName: profileBName,
        analysisText: analysisText ?? this.analysisText,
        analysisImages: analysisImages ?? this.analysisImages,
        analysisPdfs: analysisPdfs ?? this.analysisPdfs,
        createdAt: createdAt,
        respondedAt: respondedAt ??
            (status != null && status != AstrologerRequestStatus.pending
                ? DateTime.now()
                : this.respondedAt),
        completedAt: completedAt ??
            (status == AstrologerRequestStatus.completed
                ? DateTime.now()
                : this.completedAt),
        reassignMode: reassignMode ?? this.reassignMode,
        expiresAt: expiresAt ?? this.expiresAt,
        expired: expired ?? this.expired,
        expiredAt: expiredAt ?? this.expiredAt,
        reassigned: reassigned ?? this.reassigned,
        reassignedAt: reassignedAt ?? this.reassignedAt,
        userLanguage: userLanguage ?? this.userLanguage,
        history: history ?? this.history,
        paid: paid ?? this.paid,
        paidAt: paidAt ?? (paid == true ? DateTime.now() : this.paidAt),
        paymentId: paymentId ?? this.paymentId,
        inProgress: inProgress ?? this.inProgress,
        startedAt: startedAt ??
            (inProgress == true ? DateTime.now() : this.startedAt),
        // Appointment details are fixed at booking time.
        visitDate: visitDate,
        slotStartMinutes: slotStartMinutes,
        officeAddress: officeAddress,
        officeContact: officeContact,
      );
}
