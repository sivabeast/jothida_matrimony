import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final String userLocation;
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

  const AstrologerRequestModel({
    required this.id,
    required this.astrologerId,
    this.astrologerName = '',
    required this.userId,
    required this.userName,
    this.userPhotoUrl = '',
    this.userLocation = '',
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
  });

  /// True for a "Book Match Analysis" booking (groom + bride porutham request).
  bool get isMatchAnalysis => type == AstrologerRequestType.matching;

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
      userId: d['userId'] ?? '',
      userName: d['userName'] ?? 'User',
      userPhotoUrl: d['userPhotoUrl'] ?? '',
      userLocation: d['userLocation'] ?? d['location'] ?? '',
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
    );
  }

  Map<String, dynamic> toFirestore() => {
        'astrologerId': astrologerId,
        'astrologerName': astrologerName,
        'userId': userId,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'userLocation': userLocation,
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
      };

  AstrologerRequestModel copyWith({
    String? astrologerId,
    String? astrologerName,
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
  }) =>
      AstrologerRequestModel(
        id: id,
        astrologerId: astrologerId ?? this.astrologerId,
        astrologerName: astrologerName ?? this.astrologerName,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        userLocation: userLocation,
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
      );
}
