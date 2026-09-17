import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of an admin-assisted password reset request.
enum PasswordResetStatus {
  pending('pending', 'Pending'),
  underReview('under_review', 'Under Review'),
  resolved('resolved', 'Resolved'),
  rejected('rejected', 'Rejected');

  final String stored;
  final String label;
  const PasswordResetStatus(this.stored, this.label);

  static PasswordResetStatus parse(Object? raw) {
    final v = '${raw ?? ''}'.trim().toLowerCase();
    for (final s in values) {
      if (s.stored == v) return s;
    }
    return PasswordResetStatus.pending;
  }

  bool get isOpen =>
      this == PasswordResetStatus.pending ||
      this == PasswordResetStatus.underReview;
}

/// `password_reset_requests/{mobile}_{dayKey}` — a member who cannot recover
/// their password by OTP asks the administrator for help.
///
/// Deliberately holds NO password, OTP or account id: the member only gives
/// the registered mobile number, an optional name and a short description, and
/// the admin identifies the account themselves.
class PasswordResetRequest {
  final String id;
  final String mobile;
  final String name;
  final String description;
  final PasswordResetStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String adminNote;
  final String handledBy;
  final String resolution;

  /// Raised by the backend when OTP recovery refused to pick between several
  /// matrimony profiles on one number.
  final bool needsReview;
  final String reason;
  final String source;
  final List<Map<String, dynamic>> history;

  const PasswordResetRequest({
    required this.id,
    required this.mobile,
    required this.name,
    required this.description,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.adminNote = '',
    this.handledBy = '',
    this.resolution = '',
    this.needsReview = false,
    this.reason = '',
    this.source = '',
    this.history = const [],
  });

  factory PasswordResetRequest.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime? date(Object? v) => v is Timestamp ? v.toDate() : null;
    return PasswordResetRequest(
      id: doc.id,
      mobile: '${d['mobile'] ?? ''}',
      name: '${d['name'] ?? ''}',
      description: '${d['description'] ?? ''}',
      status: PasswordResetStatus.parse(d['status']),
      createdAt: date(d['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: date(d['updatedAt']),
      adminNote: '${d['adminNote'] ?? ''}',
      handledBy: '${d['handledBy'] ?? ''}',
      resolution: '${d['resolution'] ?? ''}',
      needsReview: d['needsReview'] == true,
      reason: '${d['reason'] ?? ''}',
      source: '${d['source'] ?? ''}',
      history: [
        for (final h in (d['history'] as List? ?? const []))
          if (h is Map) Map<String, dynamic>.from(h),
      ],
    );
  }

  /// UTC day number — part of the document id, which is what limits a number
  /// to one request per day at the security-rule level.
  static int dayKeyFor(DateTime now) =>
      now.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  static String idFor(String mobile, int dayKey) => '${mobile}_$dayKey';

  static const int maxDescriptionLength = 500;
  static const int maxNameLength = 80;
}
