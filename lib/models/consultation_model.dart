import 'package:cloud_firestore/cloud_firestore.dart';

/// How a consultation is delivered.
enum ConsultationMode {
  /// Everything happens inside the app: booking → pay → deep match analysis →
  /// report.
  inApp,

  /// The user meets the astrologer in person at a booked date + time slot.
  directVisit,
}

extension ConsultationModeX on ConsultationMode {
  String get key => name;

  String get label {
    switch (this) {
      case ConsultationMode.inApp:
        return 'In-App Consultation';
      case ConsultationMode.directVisit:
        return 'Direct Visit';
    }
  }

  static ConsultationMode fromKey(String? k) => ConsultationMode.values
      .firstWhere((m) => m.name == k, orElse: () => ConsultationMode.inApp);
}

/// Lifecycle of a consultation booking.
///
/// SPEC RULE: payment is collected ONLY after the astrologer accepts — never
/// before — so a rejected booking is never charged and refunds are avoided.
/// `accepted` is the Direct-Visit "Visit Confirmed" state; `waitingForPayment`
/// is the In-App post-acceptance state where the user must pay.
enum ConsultationStatus {
  pending,
  accepted,
  rejected,
  waitingForPayment,
  paid,
  analysisInProgress,
  reportSubmitted,
  completed,
  cancelled,
  refunded,
}

extension ConsultationStatusX on ConsultationStatus {
  String get key => name;

  static ConsultationStatus fromKey(String? k) => ConsultationStatus.values
      .firstWhere((s) => s.name == k, orElse: () => ConsultationStatus.pending);
}

/// One consultation booking between a matrimony user and an astrologer.
///
/// Firestore: `consultations/{id}`. For a Direct Visit the doc id is
/// deterministic (`{astrologerId}_{yyyyMMdd}_{HHmm}`) so a slot can be booked by
/// only ONE user — a second booking of the same slot fails the create.
///
/// Revenue model: there is NO platform commission. `amount` belongs 100% to the
/// astrologer; the platform earns only from astrologer subscription plans.
class ConsultationBooking {
  final String id;
  final String astrologerId;
  final String astrologerName;
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final ConsultationMode mode;
  final ConsultationStatus status;
  final int amount;
  final String note;

  // ── Direct-visit scheduling ────────────────────────────────────────────────
  /// Visit day (midnight, local). Null for In-App bookings.
  final DateTime? visitDate;

  /// Slot start as minutes-from-midnight (e.g. 8:30 AM = 510). Null for In-App.
  final int? slotStartMinutes;

  // ── In-App report (deep match analysis) ────────────────────────────────────
  final String reportText;
  final List<String> reportImages;
  final List<String> reportPdfs;

  // ── Payment ────────────────────────────────────────────────────────────────
  // In-App: collected UPFRONT at booking ("Book & Pay") and held by the admin.
  // Direct-Visit: still collected at the in-person visit (on completion).
  final bool paid;
  final String paymentId;
  final DateTime? paidAt;

  // ── Settlement / payout (admin → astrologer, 100%, no commission) ──────────
  // `settled` is set once the admin has paid the booking's amount out to the
  // astrologer; `settlementId` links to the `settlements/{id}` history batch.
  final bool settled;
  final DateTime? settledAt;
  final String settlementId;
  // Set when the admin refunds a paid booking the astrologer rejected.
  final DateTime? refundedAt;

  final DateTime createdAt;
  final DateTime? respondedAt;
  final DateTime? completedAt;

  const ConsultationBooking({
    required this.id,
    required this.astrologerId,
    this.astrologerName = '',
    required this.userId,
    required this.userName,
    this.userPhotoUrl = '',
    required this.mode,
    this.status = ConsultationStatus.pending,
    this.amount = 0,
    this.note = '',
    this.visitDate,
    this.slotStartMinutes,
    this.reportText = '',
    this.reportImages = const [],
    this.reportPdfs = const [],
    this.paid = false,
    this.paymentId = '',
    this.paidAt,
    this.settled = false,
    this.settledAt,
    this.settlementId = '',
    this.refundedAt,
    required this.createdAt,
    this.respondedAt,
    this.completedAt,
  });

  bool get isInApp => mode == ConsultationMode.inApp;
  bool get isDirectVisit => mode == ConsultationMode.directVisit;

  bool get hasReport =>
      reportText.trim().isNotEmpty ||
      reportImages.isNotEmpty ||
      reportPdfs.isNotEmpty;

  /// A booking that occupies a slot / counts toward a day's load (i.e. not
  /// rejected / cancelled / refunded).
  bool get isActive =>
      status != ConsultationStatus.rejected &&
      status != ConsultationStatus.cancelled &&
      status != ConsultationStatus.refunded;

  /// Money received but the consultation isn't finished yet → Pending Earnings.
  bool get isPendingEarning =>
      paid && status != ConsultationStatus.completed && isActive;

  /// Finished → Completed Earnings.
  bool get isCompletedEarning => status == ConsultationStatus.completed;

  /// The booking is waiting for the astrologer to Accept / Reject. In-App
  /// bookings are paid upfront so they wait at `paid`; Direct-Visit bookings are
  /// unpaid and wait at `pending`.
  bool get isAwaitingAcceptance =>
      isInApp ? status == ConsultationStatus.paid : status == ConsultationStatus.pending;

  /// Delivered + paid + not yet settled → counts toward the astrologer's
  /// Pending Payout (the admin still owes them this amount, 100%).
  bool get isSettleable =>
      paid &&
      status == ConsultationStatus.completed &&
      !settled &&
      refundedAt == null;

  /// A paid booking the astrologer rejected → the admin must refund the user.
  bool get needsRefund =>
      paid && status == ConsultationStatus.rejected && refundedAt == null;

  /// `yyyy-MM-dd` of [visitDate] (empty for In-App).
  String get dateKey => visitDate == null ? '' : _dateKey(visitDate!);

  /// `HHmm` of the slot (empty for In-App).
  String get slotKey =>
      slotStartMinutes == null ? '' : _slotKey(slotStartMinutes!);

  /// Status text shown to users / astrologers, sensitive to the mode (a
  /// Direct-Visit `accepted` reads "Visit Confirmed").
  String get statusLabel {
    switch (status) {
      case ConsultationStatus.pending:
        return 'Pending';
      case ConsultationStatus.accepted:
        return isDirectVisit ? 'Visit Confirmed' : 'Accepted';
      case ConsultationStatus.rejected:
        return 'Rejected';
      case ConsultationStatus.waitingForPayment:
        return 'Waiting for Payment';
      case ConsultationStatus.paid:
        // In-App is paid upfront, so `paid` means "paid, awaiting the
        // astrologer's acceptance". Direct-Visit reaches `paid` only at
        // completion (cash at the visit), where plain "Paid" is correct.
        return isInApp ? 'Paid · Awaiting Acceptance' : 'Paid';
      case ConsultationStatus.analysisInProgress:
        return 'In Progress';
      case ConsultationStatus.reportSubmitted:
        return 'Report Submitted';
      case ConsultationStatus.completed:
        return 'Completed';
      case ConsultationStatus.cancelled:
        return 'Cancelled';
      case ConsultationStatus.refunded:
        return 'Refunded';
    }
  }

  /// Transaction-history status: Pending Payment / Paid / Completed / Refunded /
  /// Cancelled.
  String get transactionStatusLabel {
    switch (status) {
      case ConsultationStatus.pending:
      case ConsultationStatus.accepted:
      case ConsultationStatus.waitingForPayment:
        return 'Pending Payment';
      case ConsultationStatus.paid:
      case ConsultationStatus.analysisInProgress:
      case ConsultationStatus.reportSubmitted:
        return 'Paid';
      case ConsultationStatus.completed:
        return 'Completed';
      case ConsultationStatus.refunded:
        return 'Refunded';
      case ConsultationStatus.rejected:
      case ConsultationStatus.cancelled:
        return 'Cancelled';
    }
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _slotKey(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}${(minutes % 60).toString().padLeft(2, '0')}';

  /// Deterministic doc id for a Direct-Visit booking, enforcing one-booking-per
  /// slot at the Firestore level.
  static String directVisitDocId(
          String astrologerId, DateTime date, int slotStartMinutes) =>
      '${astrologerId}_${_dateKey(date)}_${_slotKey(slotStartMinutes)}';

  static List<String> _toStringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String && v.isNotEmpty) return [v];
    return const [];
  }

  static DateTime? _toDate(dynamic v) => v is Timestamp ? v.toDate() : null;

  factory ConsultationBooking.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ConsultationBooking(
      id: doc.id,
      astrologerId: d['astrologerId'] ?? '',
      astrologerName: d['astrologerName'] ?? '',
      userId: d['userId'] ?? '',
      userName: d['userName'] ?? 'User',
      userPhotoUrl: d['userPhotoUrl'] ?? '',
      mode: ConsultationModeX.fromKey(d['mode']),
      status: ConsultationStatusX.fromKey(d['status']),
      amount: (d['amount'] ?? 0) is num ? (d['amount'] as num).toInt() : 0,
      note: d['note'] ?? '',
      visitDate: _toDate(d['visitDate']),
      slotStartMinutes: (d['slotStartMinutes'] as num?)?.toInt(),
      reportText: d['reportText'] ?? '',
      reportImages: _toStringList(d['reportImages']),
      reportPdfs: _toStringList(d['reportPdfs']),
      paid: d['paid'] == true,
      paymentId: d['paymentId'] ?? '',
      paidAt: _toDate(d['paidAt']),
      settled: d['settled'] == true,
      settledAt: _toDate(d['settledAt']),
      settlementId: d['settlementId'] ?? '',
      refundedAt: _toDate(d['refundedAt']),
      createdAt: _toDate(d['createdAt']) ?? DateTime.now(),
      respondedAt: _toDate(d['respondedAt']),
      completedAt: _toDate(d['completedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'astrologerId': astrologerId,
        'astrologerName': astrologerName,
        'userId': userId,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'mode': mode.key,
        'status': status.key,
        'amount': amount,
        'note': note,
        'visitDate': visitDate != null ? Timestamp.fromDate(visitDate!) : null,
        'slotStartMinutes': slotStartMinutes,
        // Denormalised keys so a date's taken slots can be read without parsing.
        'dateKey': dateKey,
        'slotKey': slotKey,
        'reportText': reportText,
        'reportImages': reportImages,
        'reportPdfs': reportPdfs,
        'paid': paid,
        'paymentId': paymentId,
        'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
        'settled': settled,
        'settledAt': settledAt != null ? Timestamp.fromDate(settledAt!) : null,
        'settlementId': settlementId,
        'refundedAt': refundedAt != null ? Timestamp.fromDate(refundedAt!) : null,
        'createdAt': Timestamp.fromDate(createdAt),
        'respondedAt':
            respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
        'completedAt':
            completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      };

  ConsultationBooking copyWith({
    ConsultationStatus? status,
    String? reportText,
    List<String>? reportImages,
    List<String>? reportPdfs,
    bool? paid,
    String? paymentId,
    DateTime? paidAt,
    bool? settled,
    DateTime? settledAt,
    String? settlementId,
    DateTime? refundedAt,
    DateTime? respondedAt,
    DateTime? completedAt,
  }) =>
      ConsultationBooking(
        id: id,
        astrologerId: astrologerId,
        astrologerName: astrologerName,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        mode: mode,
        status: status ?? this.status,
        amount: amount,
        note: note,
        visitDate: visitDate,
        slotStartMinutes: slotStartMinutes,
        reportText: reportText ?? this.reportText,
        reportImages: reportImages ?? this.reportImages,
        reportPdfs: reportPdfs ?? this.reportPdfs,
        paid: paid ?? this.paid,
        paymentId: paymentId ?? this.paymentId,
        paidAt: paidAt ?? this.paidAt,
        settled: settled ?? this.settled,
        settledAt: settledAt ?? this.settledAt,
        settlementId: settlementId ?? this.settlementId,
        refundedAt: refundedAt ?? this.refundedAt,
        createdAt: createdAt,
        respondedAt: respondedAt ?? this.respondedAt,
        completedAt: completedAt ?? this.completedAt,
      );
}
