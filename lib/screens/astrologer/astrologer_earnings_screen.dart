import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/consultation_model.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../providers/consultation_provider.dart';

/// Astrologer earnings dashboard + transaction history.
///
/// Revenue model: NO commission — every consultation rupee belongs to the
/// astrologer. The platform earns only from subscription plans.
class AstrologerEarningsScreen extends ConsumerWidget {
  const AstrologerEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnings = ref.watch(consultationEarningsProvider);
    final txns = [...(ref.watch(astrologerConsultationsProvider).valueOrNull ??
        const <ConsultationBooking>[])]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              _EarningTile('Total Earnings', earnings.total,
                  Icons.account_balance_wallet, AppColors.primary),
              _EarningTile('Pending Earnings', earnings.pending,
                  Icons.hourglass_top, AppColors.warning),
              _EarningTile('Completed Earnings', earnings.completed,
                  Icons.check_circle, AppColors.success),
              _EarningTile('This Month', earnings.monthly, Icons.calendar_month,
                  const Color(0xFF2F80ED)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined,
                    size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No commission is deducted — you keep 100% of every '
                    'consultation payment.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _settlementCard(context, ref, earnings),
          const SizedBox(height: 20),
          const Text('Transaction History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          if (txns.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Center(
                child: Text('No transactions yet',
                    style: TextStyle(color: Colors.grey[600])),
              ),
            )
          else
            for (final t in txns)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TransactionRow(booking: t),
              ),
        ],
      ),
    );
  }

  /// Weekly-settlement summary: last + next settlement dates and the amount due
  /// at the next payout, plus the payout-account status / edit link.
  Widget _settlementCard(BuildContext context, WidgetRef ref, dynamic earnings) {
    final now = DateTime.now();
    final next = _nextWeekly(now);
    final last = next.subtract(const Duration(days: 7));
    final int amount = earnings.completed as int; // delivered, payable balance
    final account = ref.watch(myAstrologerAccountProvider);
    final hasBank = account?.hasBankDetails ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Settlement Details',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Weekly',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _settlementRow(
              'Last Settlement', DateFormat('d MMM yyyy').format(last)),
          _settlementRow(
              'Next Settlement', DateFormat('d MMM yyyy').format(next)),
          _settlementRow('Amount To Be Paid', '₹$amount', highlight: true),
          const Divider(height: 22),
          Row(
            children: [
              Icon(hasBank ? Icons.check_circle : Icons.info_outline,
                  size: 16,
                  color: hasBank ? AppColors.success : AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasBank
                      ? 'Payout account on file.'
                      : 'Add your bank / UPI details to receive payouts.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/astrologer-bank-details'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: Text(hasBank ? 'Edit' : 'Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Next weekly settlement date — the upcoming Monday (never today).
  DateTime _nextWeekly(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    var add = (DateTime.monday - today.weekday + 7) % 7;
    if (add == 0) add = 7;
    return today.add(Duration(days: add));
  }

  Widget _settlementRow(String label, String value, {bool highlight = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            Text(value,
                style: TextStyle(
                    fontSize: highlight ? 15 : 13,
                    fontWeight:
                        highlight ? FontWeight.bold : FontWeight.w600,
                    color: highlight ? AppColors.primary : Colors.black87)),
          ],
        ),
      );
}

class _EarningTile extends StatelessWidget {
  final String label;
  final int amount;
  final IconData icon;
  final Color color;
  const _EarningTile(this.label, this.amount, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: color, size: 17),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Text('₹$amount',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, height: 1.1)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final ConsultationBooking booking;
  const _TransactionRow({required this.booking});

  ({Color color, String text}) get _status {
    final s = booking.transactionStatusLabel;
    switch (s) {
      case 'Completed':
        return (color: AppColors.success, text: s);
      case 'Paid':
        return (color: const Color(0xFF2F80ED), text: s);
      case 'Cancelled':
        return (color: AppColors.error, text: s);
      case 'Refunded':
        return (color: Colors.deepPurple, text: s);
      default:
        return (color: AppColors.warning, text: s);
    }
  }

  String get _shortId =>
      booking.id.length <= 8 ? booking.id : booking.id.substring(0, 8);

  @override
  Widget build(BuildContext context) {
    final st = _status;
    return Container(
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
                Text(booking.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '#$_shortId · ${DateFormat('d MMM yyyy').format(booking.createdAt)}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${booking.amount}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 3),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: st.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(st.text,
                    style: TextStyle(
                        fontSize: 10,
                        color: st.color,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
