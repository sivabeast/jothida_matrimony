import 'package:cloud_firestore/cloud_firestore.dart';

/// Kind of request a matrimony user sends to an astrologer.
enum AstrologerRequestType { consultation, inquiry, matching }

/// Lifecycle of a request.
enum AstrologerRequestStatus { pending, accepted, completed, rejected }

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

/// A request from a matrimony user to an astrologer.
///
/// Firestore: `astrologer_requests/{id}`
/// { astrologerId, astrologerName, userId, userName, userPhotoUrl, type, status,
///   message, amount, profileAId, profileAName, profileBId, profileBName,
///   analysisText, analysisImages, analysisPdfs, createdAt, respondedAt,
///   completedAt }
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

  static List<String> _toStringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String && v.isNotEmpty) return [v];
    return const [];
  }

  static DateTime? _toDate(dynamic v) =>
      v is Timestamp ? v.toDate() : null;

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
      };

  AstrologerRequestModel copyWith({
    AstrologerRequestStatus? status,
    String? analysisText,
    List<String>? analysisImages,
    List<String>? analysisPdfs,
    DateTime? respondedAt,
    DateTime? completedAt,
  }) =>
      AstrologerRequestModel(
        id: id,
        astrologerId: astrologerId,
        astrologerName: astrologerName,
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
      );
}
