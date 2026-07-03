import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/payroll_payment.dart';

/// One row of weekly-payroll history — shared by the admin Employees page
/// history sheet and the employee's own earnings view.
class PayrollHistoryTile extends StatelessWidget {
  final PayrollPayment payment;
  const PayrollHistoryTile({super.key, required this.payment});

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final period = p.periodStart == null
        ? 'Up to ${DateFormat('d MMM yyyy').format(p.paidAt)}'
        : '${DateFormat('d MMM').format(p.periodStart!)} – '
            '${DateFormat('d MMM yyyy').format(p.paidAt)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.success.withOpacity(0.12),
        child: const Icon(Icons.payments_outlined,
            color: AppColors.success, size: 20),
      ),
      title: Text('₹${p.amount}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      subtitle: Text(
          '$period · ${p.reportsCount} report(s) × ₹${p.ratePerReport}',
          style: const TextStyle(fontSize: 12)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('Paid',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.success)),
      ),
    );
  }
}
