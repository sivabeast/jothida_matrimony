import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../providers/astrology_team_stats_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/data_states.dart';
import '../../widgets/common/payroll_history_tile.dart';
import '../../widgets/common/skeletons.dart';

/// The admin **Employees** page body:
///
///  • TOP SUMMARY — Total / Available / Unavailable employees.
///  • WEEKLY PAYROLL SUMMARY — total commission payable this week (sum of
///    every employee's current unpaid cycle).
///  • EMPLOYEE CARDS — name, availability, this week's assigned / completed /
///    pending, this-week commission, last payment date, payment status, with
///    **Mark As Paid** (closes the current cycle and restarts it from ₹0),
///    Payment History and View Details.
class AstrologerPerformanceList extends ConsumerWidget {
  /// Extra bottom padding so a floating "Add" button never covers the last card.
  final double bottomPadding;
  const AstrologerPerformanceList({super.key, this.bottomPadding = 24});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(astrologerStatsProvider);
    final payable = ref.watch(totalPayableCommissionProvider);

    final total = stats.length;
    final available = stats.where((s) => s.member.isAssignable).length;
    final unavailable = total - available;

    if (stats.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        message: 'No employee accounts yet',
        subtitle: 'Add one by Gmail to see performance here.',
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 14, 14, bottomPadding),
      children: [
        // ── Top summary ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
                child: _summaryTile('Total\nEmployees', '$total',
                    Icons.badge_outlined, AppColors.primary)),
            const SizedBox(width: 10),
            Expanded(
                child: _summaryTile('Available\nEmployees', '$available',
                    Icons.how_to_reg_outlined, AppColors.success)),
            const SizedBox(width: 10),
            Expanded(
                child: _summaryTile('Unavailable\nEmployees', '$unavailable',
                    Icons.person_off_outlined, AppColors.error)),
          ],
        ),
        const SizedBox(height: 12),

        // ── Weekly payroll summary ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.payments_outlined,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Total Commission Payable This Week',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              Text('₹$payable',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Employee cards ──────────────────────────────────────────────
        for (final s in stats) ...[
          AstrologerPerformanceCard(stats: s),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _summaryTile(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.bold, height: 1.1)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 2,
                style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
          ],
        ),
      );
}

class AstrologerPerformanceCard extends ConsumerWidget {
  final AstrologerStats stats;
  const AstrologerPerformanceCard({super.key, required this.stats});

  static String _date(DateTime? d) =>
      d == null ? '—' : DateFormat('d MMM yyyy').format(d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = stats.member;
    final availColor = m.isAssignable ? AppColors.success : AppColors.error;
    final payColor = switch (stats.paymentStatusLabel) {
      'Paid' => AppColors.success,
      'Pending' => AppColors.warning,
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage:
                    m.photoUrl.isNotEmpty ? NetworkImage(m.photoUrl) : null,
                child: m.photoUrl.isEmpty
                    ? const Icon(Icons.person, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.displayName.isEmpty ? m.email : m.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                    Text(m.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: availColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(m.isAssignable ? 'Available' : 'Unavailable',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: availColor)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // This week's workload (spec fields).
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('Assigned This Wk', '${stats.thisWeek.assigned}',
                  Icons.event_available, Colors.teal),
              _stat('Completed This Wk', '${stats.thisWeek.completed}',
                  Icons.done_all, Colors.green),
              _stat('Pending', '${stats.pending + stats.inProgress}',
                  Icons.hourglass_bottom, Colors.orange),
              _stat('This Wk Commission', '₹${stats.cycleCommission}',
                  Icons.savings_outlined, AppColors.primary),
            ],
          ),
          const Divider(height: 22),
          // Payroll line: last payment + status.
          Row(
            children: [
              Icon(Icons.event_repeat_outlined,
                  size: 15, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Last Payment: ${_date(m.lastPaidDate)}',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: payColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(stats.paymentStatusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: payColor)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: stats.cycleCommission <= 0
                      ? null
                      : () => _confirmMarkPaid(context, ref),
                  icon: const Icon(Icons.task_alt, size: 16),
                  label: Text(stats.cycleCommission <= 0
                      ? 'Nothing Due'
                      : 'Mark As Paid · ₹${stats.cycleCommission}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade200,
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Payment History',
                onPressed: () => _showHistory(context),
                icon: const Icon(Icons.history, color: AppColors.primary),
                style: IconButton.styleFrom(
                  side: BorderSide(
                      color: AppColors.primary.withOpacity(0.5)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'View Details',
                onPressed: () => context.push(
                    '/admin/astrologer-account/${Uri.encodeComponent(m.id)}'),
                icon: const Icon(Icons.open_in_new, color: AppColors.primary),
                style: IconButton.styleFrom(
                  side: BorderSide(
                      color: AppColors.primary.withOpacity(0.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Mark As Paid": closes the CURRENT cycle (writes a payroll_payments doc)
  /// and restarts the employee's commission from ₹0.
  Future<void> _confirmMarkPaid(BuildContext context, WidgetRef ref) async {
    final m = stats.member;
    final ok = await showAppConfirmDialog(
      context,
      title: 'Mark As Paid?',
      message: 'Pay ₹${stats.cycleCommission} to '
          '${m.displayName.isEmpty ? m.email : m.displayName} for '
          '${stats.cycleCompleted} completed report(s)?\n\n'
          'This closes the current week\'s payroll — the next week starts '
          'again from ₹0.',
      confirmLabel: 'Mark As Paid',
      icon: Icons.task_alt_rounded,
    );
    if (!ok) return;
    if (!context.mounted) return;
    try {
      await ref.read(astrologyTeamServiceProvider).markPayrollPaid(
            m,
            amount: stats.cycleCommission,
            reportsCount: stats.cycleCompleted,
            ratePerReport: stats.commissionPerReport,
          );
      if (context.mounted) {
        showAppSnack(context,
            '₹${stats.cycleCommission} paid — next week starts from ₹0.');
      }
    } catch (e) {
      debugPrint('[AstrologerPerformance] payroll payment failed: $e');
      if (context.mounted) {
        showAppSnack(
            context, 'Could not record the payment. Please try again.',
            error: true);
      }
    }
  }

  /// Bottom sheet with this employee's weekly payment history.
  void _showHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PayrollHistorySheet(
          emailKey: stats.member.id,
          name: stats.member.displayName.isEmpty
              ? stats.member.email
              : stats.member.displayName),
    );
  }

  Widget _stat(String label, String value, IconData icon,
          [Color color = AppColors.primary]) =>
      Container(
        width: 150,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(label,
                style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
          ],
        ),
      );
}

/// Weekly payment history for one employee (admin view).
class _PayrollHistorySheet extends ConsumerWidget {
  final String emailKey;
  final String name;
  const _PayrollHistorySheet({required this.emailKey, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(payrollHistoryProvider(emailKey));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment History — $name',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Flexible(
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SkeletonList(items: 4, showAvatar: false),
                ),
                error: (e, _) => ErrorStateView(
                  message: 'Unable to load the payment history.',
                  onRetry: () =>
                      ref.invalidate(payrollHistoryProvider(emailKey)),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'No payments recorded yet',
                      subtitle:
                          'Weekly payouts will appear here once recorded.',
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => PayrollHistoryTile(payment: items[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

