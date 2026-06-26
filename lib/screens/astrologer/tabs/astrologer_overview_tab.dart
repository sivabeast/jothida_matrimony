import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/dev_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../models/astrologer_account_model.dart';
import '../../../models/astrologer_plan.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../providers/astrologer_dashboard_provider.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/service_providers.dart';
import '../profile/astrologer_availability_screen.dart';
import 'astrologer_common.dart';

/// Dashboard overview for the marketplace astrologer.
///
/// The dashboard no longer lists request cards (spec §1) — those live on the
/// dedicated Requests page. Instead a single compact UNREAD banner sits at the
/// top; tapping it opens the Requests page and clears the badge. Below it sit
/// availability, revenue, customer/rating stats and the subscription card.
/// Approval status lives in the top header. Revenue counts COMPLETED requests
/// only.
class AstrologerOverviewTab extends ConsumerWidget {
  /// Opens the dashboard's Requests bottom-nav tab (optionally on a sub-tab:
  /// 0 = Match Analysis, 1 = Direct Visit) and clears the unread banner.
  final void Function([int subTab])? onOpenRequests;
  const AstrologerOverviewTab({super.key, this.onOpenRequests});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAstrologerAccountProvider);
    if (account == null) return const AstrologerLoading();

    final requests =
        ref.watch(astrologerRequestsProvider).valueOrNull ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (!account.isApproved) _verificationBanner(context, ref, account),
        // ── Compact unread "new requests" banner (spec §1) ──────────────────
        _newRequestsBanner(context, ref),
        const SizedBox(height: 18),
        // ── Availability (working days + manual on/off) ─────────────────────
        _availabilityCard(context, ref, account),
        const SizedBox(height: 18),
        // ── Revenue (completed requests only) ───────────────────────────────
        Row(
          children: [
            const Expanded(child: AstrologerSectionTitle('Revenue')),
            TextButton.icon(
              onPressed: () => context.push('/astrologer-earnings'),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
              label: const Text('Earnings'),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        _revenueRow(requests),
        const SizedBox(height: 18),
        // ── Customers ───────────────────────────────────────────────────────
        const AstrologerSectionTitle('Customers'),
        _customersRow(requests, account),
        const SizedBox(height: 18),
        // ── Ratings ─────────────────────────────────────────────────────────
        const AstrologerSectionTitle('Ratings'),
        Row(
          children: [
            Expanded(
              child: _StatCard('Avg Rating', account.rating.toStringAsFixed(1),
                  Icons.star_outline, AppColors.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard('Total Reviews', '${account.reviewCount}',
                  Icons.reviews_outlined, AppColors.success),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // ── Subscription ────────────────────────────────────────────────────
        const AstrologerSectionTitle('Subscription'),
        _subscriptionCard(context, ref, account),
        const SizedBox(height: 20),
        // ── Recent activity ─────────────────────────────────────────────────
        const AstrologerSectionTitle('Recent Activity'),
        _recentActivity(ref),
      ],
    );
  }

  // ── Compact unread "new requests" banner (spec §1) ─────────────────────────
  /// A single unread-style banner replacing the old request lists. Shows a red
  /// dot + a count-aware message ("New Match Analysis Request Received",
  /// "3 New Match Analysis Requests", "New Direct Visit Booking"). Tapping opens
  /// the Requests page on the matching tab and clears the badge.
  Widget _newRequestsBanner(BuildContext context, WidgetRef ref) {
    final matchNew = ref.watch(newMatchAnalysisCountProvider);
    final visitNew = ref.watch(newDirectVisitCountProvider);
    final total = matchNew + visitNew;

    if (total == 0) {
      return AstrologerCard(
        onTap: () => onOpenRequests?.call(0),
        child: Row(
          children: [
            Icon(Icons.inbox_outlined, size: 18, color: Colors.grey[400]),
            const SizedBox(width: 10),
            Expanded(
              child: Text('No new requests right now. Tap to view all requests.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      );
    }

    final String message;
    final int subTab;
    if (matchNew > 0 && visitNew > 0) {
      message = '$total New Requests';
      subTab = 0;
    } else if (matchNew > 0) {
      message = matchNew == 1
          ? 'New Match Analysis Request Received'
          : '$matchNew New Match Analysis Requests';
      subTab = 0;
    } else {
      message = visitNew == 1
          ? 'New Direct Visit Booking'
          : '$visitNew New Direct Visit Bookings';
      subTab = 1;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onOpenRequests?.call(subTab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: AppColors.error, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.error)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(20)),
              child: Text('$total',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.error),
          ],
        ),
      ),
    );
  }

  // ── Revenue (Today / Monthly / Total — COMPLETED requests only) ────────────
  Widget _revenueRow(List<AstrologerRequestModel> requests) {
    final now = DateTime.now();
    var today = 0, month = 0, total = 0;
    for (final r in requests) {
      // Revenue is recognised ONLY when a report has been submitted and the
      // request is Completed — never for pending / accepted / unpaid requests.
      if (r.status != AstrologerRequestStatus.completed) continue;
      final d = r.completedAt ?? r.respondedAt ?? r.createdAt;
      total += r.amount;
      if (d.year == now.year && d.month == now.month) {
        month += r.amount;
        if (d.day == now.day) today += r.amount;
      }
    }
    return Row(
      children: [
        Expanded(
            child: _StatCard(
                "Today's", '₹$today', Icons.today, AppColors.success)),
        const SizedBox(width: 10),
        Expanded(
            child: _StatCard('Monthly', '₹$month', Icons.calendar_month,
                AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(
            child: _StatCard('Total', '₹$total',
                Icons.account_balance_wallet_outlined, AppColors.info)),
      ],
    );
  }

  // ── Customers ──────────────────────────────────────────────────────────────
  Widget _customersRow(
      List<AstrologerRequestModel> requests, AstrologerAccount a) {
    final customers = requests.map((r) => r.userId).toSet().length;
    return Row(
      children: [
        Expanded(
          child: _StatCard('Total Customers', '$customers',
              Icons.people_outline, AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard('Contact Requests', '${a.contactUnlocks}',
              Icons.lock_open_outlined, AppColors.info),
        ),
      ],
    );
  }

  // ── Subscription card (Monthly / Yearly only) ──────────────────────────────
  Widget _subscriptionCard(
      BuildContext context, WidgetRef ref, AstrologerAccount a) {
    final active = a.subscriptionActive;
    final hasPlan = a.subscriptionExpiry != null;
    final tierLabel = AstrologerPlan.labelFor(a.subscriptionPlan);
    final planLabel = tierLabel.isNotEmpty ? tierLabel : 'No active plan';
    final statusColor = active ? AppColors.success : AppColors.error;
    final statusText = active
        ? 'Active'
        : hasPlan
            ? 'Expired'
            : 'Inactive';

    return AstrologerCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kSubscriptionTestMode) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: Text('🧪 TEST MODE · payment bypassed',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning.withOpacity(0.95))),
            ),
          ],
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: AppColors.gold),
              const SizedBox(width: 10),
              Text(planLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusText,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (hasPlan) ...[
            const SizedBox(height: 12),
            _subRow('Expiry Date', astrologerDateOnly(a.subscriptionExpiry!)),
            _subRow('Days Remaining', '${a.subscriptionDaysRemaining} days'),
          ] else ...[
            const SizedBox(height: 8),
            Text(
                'Choose a Monthly or Yearly plan to appear in user listings, '
                'search and recommendations.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          ],
          if (!active) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Your profile is hidden from users until your '
                        'subscription is active. Editing stays available.',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey[800])),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => kSubscriptionTestMode
                ? _choosePlan(context, ref)
                : _renew(context),
            icon: const Icon(kSubscriptionTestMode
                ? Icons.workspace_premium
                : Icons.autorenew),
            label: Text(kSubscriptionTestMode
                ? (hasPlan ? 'Change Plan' : 'Activate Plan')
                : 'Renew Subscription'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  /// Subscription plan picker — Monthly or Yearly. In TEST MODE the plan
  /// activates instantly with no payment; otherwise this is where the payment
  /// flow would run before activation.
  void _choosePlan(BuildContext context, WidgetRef ref) {
    final current = ref.read(myAstrologerAccountProvider)?.subscriptionPlan;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Choose a Plan',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (AstrologerPlan.launchOfferActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('🚀 Launch Offer',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              kSubscriptionTestMode
                  ? 'Test mode — the plan activates immediately, no payment.'
                  : 'Pick Monthly or Yearly billing.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            for (final plan in AstrologerPlan.all) ...[
              _planCard(sheetCtx, ref, plan, current: current),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _planCard(BuildContext sheetCtx, WidgetRef ref, AstrologerPlan plan,
      {String? current}) {
    final isCurrent = current == plan.id;
    const launch = AstrologerPlan.launchOfferActive;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        Navigator.pop(sheetCtx);
        final messenger = ScaffoldMessenger.of(sheetCtx);
        await ref.read(myAstrologerAccountProvider.notifier).activateSubscription(
            plan.id,
            days: plan.durationDays,
            amount: plan.currentPrice);
        messenger.showSnackBar(SnackBar(
            content: Text(
                '${plan.name} plan activated${kSubscriptionTestMode ? ' (test mode)' : ''}.')));
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isCurrent ? AppColors.primary.withOpacity(0.04) : Colors.white,
          border: Border.all(
              color: isCurrent
                  ? AppColors.primary
                  : AppColors.primary.withOpacity(0.25),
              width: isCurrent ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(plan.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${plan.name}${isCurrent ? '  · current' : ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₹${plan.currentPrice}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.primary)),
                        Text('/${plan.unit}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    if (launch && plan.regularPrice != plan.launchPrice)
                      Text('₹${plan.regularPrice}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              decoration: TextDecoration.lineThrough)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...plan.perks.map((perk) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 15, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(perk,
                              style: const TextStyle(fontSize: 12.5))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _subRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  void _renew(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renew Subscription'),
        content: const Text(
            'To renew your Monthly or Yearly plan, please contact the platform '
            'admin. Your profile stays visible to users while your subscription '
            'is active.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // ── Recent activity (from the astrologer's notifications) ──────────────────
  Widget _recentActivity(WidgetRef ref) {
    final items = ref.watch(notificationsProvider).valueOrNull ?? const [];
    if (items.isEmpty) {
      return AstrologerCard(
        child: Row(
          children: [
            Icon(Icons.history, size: 18, color: Colors.grey[400]),
            const SizedBox(width: 10),
            Text('No recent activity',
                style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }
    final recent = [...items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      children: [
        for (final n in recent.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AstrologerCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: const Icon(Icons.notifications_none,
                        size: 16, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        n.title.isEmpty ? 'Activity update' : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 13.5)),
                  ),
                  Text(astrologerRelativeTime(n.createdAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Availability card (dashboard header status + toggle) ────────────────────
  Widget _availabilityCard(
      BuildContext context, WidgetRef ref, AstrologerAccount a) {
    final availableNow = a.isAvailableNow;
    final statusColor = availableNow ? AppColors.success : AppColors.error;

    Future<void> toggle(bool value) async {
      try {
        await ref
            .read(myAstrologerAccountProvider.notifier)
            .setManualAvailability(value);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not update availability — please try again.'),
              backgroundColor: AppColors.error));
        }
      }
    }

    return AstrologerCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(availableNow ? Icons.circle : Icons.circle_outlined,
                  size: 14, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  availableNow ? '🟢 Available' : '🔴 Not Available',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: statusColor),
                ),
              ),
              Switch(
                value: a.manuallyAvailable,
                activeColor: AppColors.success,
                onChanged: toggle,
              ),
            ],
          ),
          if (a.manuallyAvailable && !a.isWorkingToday) ...[
            const SizedBox(height: 4),
            Text('Today (${weekdayName()}) is not one of your working days.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
          const Divider(height: 20),
          _assignmentToggle(
            context,
            ref,
            icon: Icons.assignment_ind_outlined,
            title: context.l10n.availableForAssignment,
            subtitle: 'Admin may assign you bookings other astrologers missed.',
            value: a.availableForAssignment,
            onChanged: (v) async {
              try {
                await ref
                    .read(myAstrologerAccountProvider.notifier)
                    .setAvailableForAssignment(v);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Could not update — please try again.'),
                      backgroundColor: AppColors.error));
                }
              }
            },
          ),
          const SizedBox(height: 6),
          _assignmentToggle(
            context,
            ref,
            icon: Icons.beach_access_outlined,
            title: context.l10n.onLeave,
            subtitle: 'Pause new assignments while you are away.',
            value: a.onLeave,
            onChanged: (v) async {
              try {
                await ref
                    .read(myAstrologerAccountProvider.notifier)
                    .setOnLeave(v);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Could not update — please try again.'),
                      backgroundColor: AppColors.error));
                }
              }
            },
          ),
          const Divider(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.event_available_outlined,
                  size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    children: [
                      const TextSpan(
                          text: 'Working Days: ',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: a.workingDaysLabel),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AstrologerAvailabilityScreen())),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A compact labelled switch row used for the assignment-availability and
  /// on-leave controls inside the availability card.
  Widget _assignmentToggle(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            ],
          ),
        ),
        Switch(
          value: value,
          activeColor: AppColors.success,
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// Pending / rejected verification alert (with a reapply action when
  /// rejected). Shown only while the account is not approved — the persistent
  /// approval indicator lives in the dashboard top header.
  Widget _verificationBanner(
      BuildContext context, WidgetRef ref, AstrologerAccount a) {
    final rejected = a.status == VerificationStatus.rejected;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            (rejected ? AppColors.error : AppColors.warning).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(rejected ? Icons.cancel : Icons.hourglass_top,
                  color: rejected ? AppColors.error : AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rejected
                      ? 'Your certificate was rejected. Please re-submit valid documents.'
                      : 'Your profile is under review. You will be visible to users '
                          'once an admin approves your certificate.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          if (rejected) ...[
            if (a.rejectionReason.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Reason: ${a.rejectionReason.trim()}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[800])),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _reapply(context, ref, a),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reapply for Verification'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reapply(
      BuildContext context, WidgetRef ref, AstrologerAccount a) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(astrologerServiceProvider).reapplyForVerification(a.id);
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Re-submitted for verification. Update your profile / certificates if needed.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not re-submit. Please try again.'),
          backgroundColor: AppColors.error));
    }
  }
}


class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => AstrologerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      );
}
