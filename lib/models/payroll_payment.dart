import 'package:cloud_firestore/cloud_firestore.dart';

/// One closed weekly-payroll payout to an employee (`payroll_payments`).
///
/// Written when the admin taps **Mark As Paid** on the Employees page: the
/// employee's current payroll cycle (all commission earned since their last
/// payment) is closed at [paidAt] and the next cycle starts from ₹0 —
/// commission never accumulates across paid weeks.
class PayrollPayment {
  final String id;

  /// The employee registry key (lowercased Gmail — `astrology_team` doc id).
  final String employeeId;
  final String employeeEmail;
  final String employeeName;

  /// Commission paid out for this cycle (₹).
  final int amount;

  /// Completed reports covered by this payout.
  final int reportsCount;

  /// Commission rate (₹ per report) in force when the cycle was closed.
  final int ratePerReport;

  /// The cycle this payout covers: from the previous payment (or the
  /// employee's start) up to [paidAt].
  final DateTime? periodStart;
  final DateTime paidAt;

  const PayrollPayment({
    required this.id,
    required this.employeeId,
    required this.employeeEmail,
    required this.employeeName,
    required this.amount,
    required this.reportsCount,
    required this.ratePerReport,
    this.periodStart,
    required this.paidAt,
  });

  factory PayrollPayment.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return PayrollPayment(
      id: doc.id,
      employeeId: (d['employeeId'] ?? '').toString(),
      employeeEmail: (d['employeeEmail'] ?? '').toString(),
      employeeName: (d['employeeName'] ?? '').toString(),
      amount: (d['amount'] as num?)?.toInt() ?? 0,
      reportsCount: (d['reportsCount'] as num?)?.toInt() ?? 0,
      ratePerReport: (d['ratePerReport'] as num?)?.toInt() ?? 0,
      periodStart: ts(d['periodStart']),
      paidAt: ts(d['paidAt']) ?? DateTime.now(),
    );
  }
}
