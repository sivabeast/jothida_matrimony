import 'package:cloud_firestore/cloud_firestore.dart';

class ReportModel {
  final String id;
  final String reporterUserId;
  final String reporterName;
  final String reportedUserId;
  final String reportedProfileId;
  final String reportedName;
  final String reason;
  final String? description;
  final String alertLevel; // normal, warning, high, critical
  final bool isResolved;
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const ReportModel({
    required this.id,
    required this.reporterUserId,
    required this.reporterName,
    required this.reportedUserId,
    required this.reportedProfileId,
    required this.reportedName,
    required this.reason,
    this.description,
    required this.alertLevel,
    this.isResolved = false,
    this.adminNotes,
    required this.createdAt,
    this.resolvedAt,
  });

  factory ReportModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ReportModel(
      id: doc.id,
      reporterUserId: d['reporterUserId'] ?? '',
      reporterName: d['reporterName'] ?? '',
      reportedUserId: d['reportedUserId'] ?? '',
      reportedProfileId: d['reportedProfileId'] ?? '',
      reportedName: d['reportedName'] ?? '',
      reason: d['reason'] ?? '',
      description: d['description'],
      alertLevel: d['alertLevel'] ?? 'normal',
      isResolved: d['isResolved'] ?? false,
      adminNotes: d['adminNotes'],
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      resolvedAt: d['resolvedAt'] != null ? (d['resolvedAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'reporterUserId': reporterUserId,
        'reporterName': reporterName,
        'reportedUserId': reportedUserId,
        'reportedProfileId': reportedProfileId,
        'reportedName': reportedName,
        'reason': reason,
        'description': description,
        'alertLevel': alertLevel,
        'isResolved': isResolved,
        'adminNotes': adminNotes,
        'createdAt': Timestamp.fromDate(createdAt),
        'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      };

  static String getAlertLevel(int reportCount) {
    if (reportCount >= 10) return 'critical';
    if (reportCount >= 5) return 'high';
    if (reportCount >= 3) return 'warning';
    return 'normal';
  }
}
