import 'package:cloud_firestore/cloud_firestore.dart';

class PoruthamsModel {
  final String id;
  final String requestedByUserId;
  final String brideProfileId;
  final String groomProfileId;
  final String brideName;
  final String groomName;
  final String status; // requested, completed
  final int amountPaid; // 199 INR
  final String? razorpayPaymentId;
  final DateTime requestedAt;
  final DateTime? completedAt;
  final String? astrologerId;
  final PoruthamsResult? result;
  final bool isFreeRequest; // for medium/premium plans

  const PoruthamsModel({
    required this.id,
    required this.requestedByUserId,
    required this.brideProfileId,
    required this.groomProfileId,
    required this.brideName,
    required this.groomName,
    required this.status,
    required this.amountPaid,
    this.razorpayPaymentId,
    required this.requestedAt,
    this.completedAt,
    this.astrologerId,
    this.result,
    this.isFreeRequest = false,
  });

  factory PoruthamsModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PoruthamsModel(
      id: doc.id,
      requestedByUserId: d['requestedByUserId'] ?? '',
      brideProfileId: d['brideProfileId'] ?? '',
      groomProfileId: d['groomProfileId'] ?? '',
      brideName: d['brideName'] ?? '',
      groomName: d['groomName'] ?? '',
      status: d['status'] ?? 'requested',
      amountPaid: d['amountPaid'] ?? 0,
      razorpayPaymentId: d['razorpayPaymentId'],
      requestedAt: (d['requestedAt'] as Timestamp).toDate(),
      completedAt: d['completedAt'] != null ? (d['completedAt'] as Timestamp).toDate() : null,
      astrologerId: d['astrologerId'],
      result: d['result'] != null ? PoruthamsResult.fromMap(d['result']) : null,
      isFreeRequest: d['isFreeRequest'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'requestedByUserId': requestedByUserId,
        'brideProfileId': brideProfileId,
        'groomProfileId': groomProfileId,
        'brideName': brideName,
        'groomName': groomName,
        'status': status,
        'amountPaid': amountPaid,
        'razorpayPaymentId': razorpayPaymentId,
        'requestedAt': Timestamp.fromDate(requestedAt),
        'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
        'astrologerId': astrologerId,
        'result': result?.toMap(),
        'isFreeRequest': isFreeRequest,
      };
}

class PoruthamsResult {
  final bool dinaPorutham;
  final bool ganaPorutham;
  final bool mahendraPorutham;
  final bool rajjuPorutham;
  final bool yoniPorutham;
  final bool rasiPorutham;
  final String finalVerdict; // 'Suitable Match', 'Average Match', 'Not Recommended'
  final String astrologerNotes;
  final String astrologerName;
  final DateTime analyzedAt;

  const PoruthamsResult({
    required this.dinaPorutham,
    required this.ganaPorutham,
    required this.mahendraPorutham,
    required this.rajjuPorutham,
    required this.yoniPorutham,
    required this.rasiPorutham,
    required this.finalVerdict,
    required this.astrologerNotes,
    required this.astrologerName,
    required this.analyzedAt,
  });

  factory PoruthamsResult.fromMap(Map<String, dynamic> map) => PoruthamsResult(
        dinaPorutham: map['dinaPorutham'] ?? false,
        ganaPorutham: map['ganaPorutham'] ?? false,
        mahendraPorutham: map['mahendraPorutham'] ?? false,
        rajjuPorutham: map['rajjuPorutham'] ?? false,
        yoniPorutham: map['yoniPorutham'] ?? false,
        rasiPorutham: map['rasiPorutham'] ?? false,
        finalVerdict: map['finalVerdict'] ?? '',
        astrologerNotes: map['astrologerNotes'] ?? '',
        astrologerName: map['astrologerName'] ?? '',
        analyzedAt: (map['analyzedAt'] as Timestamp).toDate(),
      );

  Map<String, dynamic> toMap() => {
        'dinaPorutham': dinaPorutham,
        'ganaPorutham': ganaPorutham,
        'mahendraPorutham': mahendraPorutham,
        'rajjuPorutham': rajjuPorutham,
        'yoniPorutham': yoniPorutham,
        'rasiPorutham': rasiPorutham,
        'finalVerdict': finalVerdict,
        'astrologerNotes': astrologerNotes,
        'astrologerName': astrologerName,
        'analyzedAt': Timestamp.fromDate(analyzedAt),
      };

  int get matchedCount {
    int count = 0;
    if (dinaPorutham) count++;
    if (ganaPorutham) count++;
    if (mahendraPorutham) count++;
    if (rajjuPorutham) count++;
    if (yoniPorutham) count++;
    if (rasiPorutham) count++;
    return count;
  }

  double get matchPercentage => (matchedCount / 6) * 100;
}
