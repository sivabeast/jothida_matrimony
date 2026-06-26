import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/consultation_model.dart';
import '../../models/settlement_model.dart';
import '../../providers/consultation_provider.dart';
import '../../providers/settlement_provider.dart';
import '../../widgets/common/data_states.dart';
import 'admin_export.dart' show inr;

/// Admin → Settlements & Payouts.
///
/// The platform takes NO commission: every consultation rupee belongs to the
/// astrologer. The admin collects the upfront payment and pays it out in full.
/// Two tabs:
///  • **Payouts** — per-astrologer pending / paid amounts (weekly settlement
///    tracking) with "Mark as Paid".
///  • **Refunds** — paid bookings an astrologer rejected, awaiting a refund.
class AdminSettlementsScreen extends ConsumerWidget {
  const AdminSettlementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refunds = ref.watch(refundsDueProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Settlements & Payouts'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: TabBar(
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              const Tab(text: 'Payouts'),
              Tab(text: 'Refunds${refunds.isEmpty ? '' : ' (${refunds.length})'}'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_PayoutsTab(), _RefundsTab()],
        ),
      ),
    );
  }
}

// ── Payouts tab ──────────────────────────────────────────────────────────────
class _PayoutsTab extends ConsumerWidget {
  const _PayoutsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allConsultationsProvider);
    final totals = ref.watch(platformSettlementTotalsProvider);
    final rows = ref.watch(astrologerSettlementsProvider)
        .where((s) => s.total > 0)
        .toList();

    return async.when(
      loading: () => const LoadingState(message: 'Loading settlements…'),
      error: (e, _) => ErrorStateView(
        message: 'Could not load settlements.',
        onRetry: () => ref.invalidate(allConsultationsProvider),
      ),
      data: (_) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                  child: _StatCard('Pending Payout',
                      inr(totals.pendingSettlements), AppColors.warning,
                      Icons.hourglass_bottom)),
              const SizedBox(width: 10),
              Expanded(
                  child: _StatCard('Total Settled', inr(totals.totalSettled),
                      AppColors.success, Icons.verified)),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Astrologer Payouts',
              style: TextStyle(
                  fontSize: 16, fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Tap an astrologer to view details and settle (100%, no commission).',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  message: 'No completed consultations yet'),
            )
          else
            for (final s in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AstrologerPayoutCard(settlement: s),
              ),
        ],
      ),
    );
  }
}

class _AstrologerPayoutCard extends StatelessWidget {
  final AstrologerSettlement settlement;
  const _AstrologerPayoutCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    final hasPending = s.pendingPayout > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SettlementDetailSheet(settlement: s),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: hasPending
                  ? AppColors.warning.withOpacity(0.4)
                  : Colors.grey.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withOpacity(0.12),
                  child: Text(
                    s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name.isEmpty ? 'Astrologer' : s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text('${s.completedBookings} completed · last '
                          '${s.lastSettlement == null ? '—' : DateFormat('d MMM').format(s.lastSettlement!)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(inr(s.pendingPayout),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: hasPending
                                ? AppColors.warning
                                : Colors.grey)),
                    Text('pending',
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey[500])),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                _miniStat('This Week', inr(s.thisWeek)),
                _miniStat('This Month', inr(s.thisMonth)),
                _miniStat('Total', inr(s.total)),
                _miniStat('Paid', inr(s.paidAmount)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 1),
            Text(label,
                style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
          ],
        ),
      );
}

// ── Settlement detail bottom sheet (unsettled bookings + Mark as Paid + history)
class _SettlementDetailSheet extends ConsumerWidget {
  final AstrologerSettlement settlement;
  const _SettlementDetailSheet({required this.settlement});

  Future<void> _markPaid(
      BuildContext context, WidgetRef ref, List<ConsultationBooking> due) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Paid'),
        content: Text(
            'Settle ${inr(settlement.pendingPayout)} to ${settlement.name} for '
            '${due.length} consultation${due.length == 1 ? '' : 's'}? This records '
            'a full (100%) payout.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Payout'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(consultationControllerProvider.notifier).settle(
          astrologerId: settlement.astrologerId,
          astrologerName: settlement.name,
          bookings: due,
        );
    final st = ref.read(consultationControllerProvider);
    if (context.mounted) Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not settle. Please try again.'
          : 'Payout settled to ${settlement.name}.'),
      backgroundColor: st.hasError ? AppColors.error : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(settleableBookingsProvider(settlement.astrologerId));
    final history = ref
        .watch(settlementsHistoryProvider)
        .valueOrNull
        ?.where((h) => h.astrologerId == settlement.astrologerId)
        .toList() ??
        const <Settlement>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.scaffoldBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(settlement.name.isEmpty ? 'Astrologer' : settlement.name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('Pending payout ${inr(settlement.pendingPayout)} · '
                'Total paid ${inr(settlement.paidAmount)}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
            const SizedBox(height: 16),
            if (due.isEmpty)
              _emptyBox('No bookings awaiting settlement')
            else ...[
              const Text('Awaiting Settlement',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              for (final b in due) _bookingRow(b),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _markPaid(context, ref, due),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text('Mark ${inr(settlement.pendingPayout)} as Paid'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            const Text('Settlement History',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            if (history.isEmpty)
              _emptyBox('No settlements yet')
            else
              for (final h in history) _historyRow(h),
          ],
        ),
      ),
    );
  }

  Widget _bookingRow(ConsultationBooking b) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5)),
                  Text('#${b.id.length <= 8 ? b.id : b.id.substring(0, 8)} · '
                      '${DateFormat('d MMM yyyy').format(b.completedAt ?? b.createdAt)}',
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                ],
              ),
            ),
            Text(inr(b.amount),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );

  Widget _historyRow(Settlement h) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${h.bookingCount} consultation'
                      '${h.bookingCount == 1 ? '' : 's'} settled',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(DateFormat('d MMM yyyy · h:mm a').format(h.createdAt),
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                ],
              ),
            ),
            Text(inr(h.amount),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.success)),
          ],
        ),
      );

  Widget _emptyBox(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Center(
            child: Text(text, style: TextStyle(color: Colors.grey[600]))),
      );
}

// ── Refunds tab ──────────────────────────────────────────────────────────────
class _RefundsTab extends ConsumerWidget {
  const _RefundsTab();

  Future<void> _refund(
      BuildContext context, WidgetRef ref, ConsultationBooking b) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Process Refund'),
        content: Text('Refund ${inr(b.amount)} to ${b.userName}? '
            '${b.astrologerName} rejected this booking.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(consultationControllerProvider.notifier).refund(b);
    final st = ref.read(consultationControllerProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not process the refund. Please try again.'
          : 'Refunded ${inr(b.amount)} to ${b.userName}.'),
      backgroundColor: st.hasError ? AppColors.error : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refunds = ref.watch(refundsDueProvider);
    if (refunds.isEmpty) {
      return const EmptyState(
          icon: Icons.replay_circle_filled_outlined,
          message: 'No refunds pending');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: refunds.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final b = refunds[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.error.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.userName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text('Rejected by ${b.astrologerName} · '
                            '${DateFormat('d MMM yyyy').format(b.respondedAt ?? b.createdAt)}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Text(inr(b.amount),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _refund(context, ref, b),
                  icon: const Icon(Icons.replay, size: 18),
                  label: Text('Refund ${inr(b.amount)}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Shared stat card ─────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _StatCard(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ),
    );
  }
}
