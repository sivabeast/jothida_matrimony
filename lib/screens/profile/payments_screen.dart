import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/consultation_model.dart';
import '../../providers/consultation_provider.dart';
import '../../providers/match_analysis_provider.dart';

/// Wallet / Payments — the user's payment history across both booking
/// pipelines. Development mode: every paid booking carries a demo transaction
/// id. Shows a "total paid" summary and a chronological transaction list.
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisAsync = ref.watch(myMatchAnalysisRequestsProvider);
    final consultAsync = ref.watch(myConsultationsProvider);

    final analysis =
        analysisAsync.valueOrNull ?? const <AstrologerRequestModel>[];
    final consults = consultAsync.valueOrNull ?? const <ConsultationBooking>[];
    final loading = analysisAsync.isLoading || consultAsync.isLoading;

    // Build a unified, date-sorted list of completed payments.
    final txns = <_Txn>[
      for (final r in analysis)
        if (r.paid)
          _Txn(
            title: '${r.profileAName ?? 'Groom'} × ${r.profileBName ?? 'Bride'}',
            subtitle: 'Match Analysis · ${r.astrologerName}',
            amount: r.amount,
            date: r.paidAt ?? r.createdAt,
            ref: r.paymentId,
          ),
      for (final c in consults)
        if (_consultPaid(c))
          _Txn(
            title: c.mode.label,
            subtitle: 'Consultation · ${c.astrologerName}',
            amount: c.amount,
            date: c.createdAt,
            ref: c.id,
          ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    final totalPaid = txns.fold<int>(0, (sum, t) => sum + t.amount);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Wallet / Payments'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: loading && txns.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summaryCard(totalPaid, txns.length),
                const SizedBox(height: 20),
                const Text('Payment History',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                if (txns.isEmpty)
                  _empty()
                else
                  for (final t in txns)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _txnRow(t),
                    ),
              ],
            ),
    );
  }

  static bool _consultPaid(ConsultationBooking c) =>
      c.status == ConsultationStatus.paid ||
      c.status == ConsultationStatus.analysisInProgress ||
      c.status == ConsultationStatus.reportSubmitted ||
      c.status == ConsultationStatus.completed;

  Widget _summaryCard(int total, int count) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet,
                color: AppColors.gold, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('₹$total',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold)),
                  Text('Total paid · $count transaction${count == 1 ? '' : 's'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _txnRow(_Txn t) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5)
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(t.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(
                    '${t.ref.isEmpty ? '' : '#${t.ref.length <= 12 ? t.ref : t.ref.substring(0, 12)} · '}'
                    '${DateFormat('d MMM yyyy').format(t.date)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${t.amount}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Paid',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.success,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 56, color: AppColors.primary.withOpacity(0.35)),
              const SizedBox(height: 12),
              Text('No payments yet',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ],
          ),
        ),
      );
}

class _Txn {
  final String title;
  final String subtitle;
  final int amount;
  final DateTime date;
  final String ref;
  const _Txn({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.date,
    required this.ref,
  });
}
