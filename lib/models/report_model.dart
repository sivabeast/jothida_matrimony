import 'package:cloud_firestore/cloud_firestore.dart';

/// A user-submitted report (spec §5 profile reports & §7 chat reports).
///
/// Both kinds live in the same `reports` collection, distinguished by [type]:
///   * `'profile'` — reporting a member's profile.
///   * `'chat'`    — reporting a conversation (carries [chatThreadId] and an
///                   optional [screenshotUrl]).
///
/// [status] drives the admin Report Management workflow (spec §8):
/// `pending → warned | suspended | deleted | rejected | resolved`. The legacy
/// [isResolved] boolean is kept in sync for backward compatibility.
class ReportModel {
  static const String typeProfile = 'profile';
  static const String typeChat = 'chat';

  final String id;
  final String type;
  final String reporterUserId;
  final String reporterName;
  final String reportedUserId;
  final String reportedProfileId; // '' for chat reports
  final String reportedName;
  final String reason;
  final String? description;
  // Chat reports only.
  final String? chatThreadId;
  final String? screenshotUrl;
  final String alertLevel; // normal, warning, high, critical
  final String status; // pending, warned, suspended, deleted, rejected, resolved
  final bool isResolved;
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const ReportModel({
    required this.id,
    this.type = typeProfile,
    required this.reporterUserId,
    required this.reporterName,
    required this.reportedUserId,
    required this.reportedProfileId,
    required this.reportedName,
    required this.reason,
    this.description,
    this.chatThreadId,
    this.screenshotUrl,
    required this.alertLevel,
    this.status = 'pending',
    this.isResolved = false,
    this.adminNotes,
    required this.createdAt,
    this.resolvedAt,
  });

  factory ReportModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final resolved = d['isResolved'] ?? false;
    return ReportModel(
      id: doc.id,
      type: d['type'] ?? typeProfile,
      reporterUserId: d['reporterUserId'] ?? '',
      reporterName: d['reporterName'] ?? '',
      reportedUserId: d['reportedUserId'] ?? '',
      reportedProfileId: d['reportedProfileId'] ?? '',
      reportedName: d['reportedName'] ?? '',
      reason: d['reason'] ?? '',
      description: d['description'],
      chatThreadId: d['chatThreadId'],
      screenshotUrl: d['screenshotUrl'],
      alertLevel: d['alertLevel'] ?? 'normal',
      // Older docs have no `status`; derive it from the legacy flag.
      status: d['status'] ?? (resolved == true ? 'resolved' : 'pending'),
      isResolved: resolved,
      adminNotes: d['adminNotes'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolvedAt:
          d['resolvedAt'] != null ? (d['resolvedAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type,
        'reporterUserId': reporterUserId,
        'reporterName': reporterName,
        'reportedUserId': reportedUserId,
        'reportedProfileId': reportedProfileId,
        'reportedName': reportedName,
        'reason': reason,
        'description': description,
        'chatThreadId': chatThreadId,
        'screenshotUrl': screenshotUrl,
        'alertLevel': alertLevel,
        'status': status,
        'isResolved': isResolved,
        'adminNotes': adminNotes,
        'createdAt': Timestamp.fromDate(createdAt),
        'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      };

  bool get isChat => type == typeChat;

  static String getAlertLevel(int reportCount) {
    if (reportCount >= 10) return 'critical';
    if (reportCount >= 5) return 'high';
    if (reportCount >= 3) return 'warning';
    return 'normal';
  }
}
