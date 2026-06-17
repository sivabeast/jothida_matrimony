import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/dev_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_account_model.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../../../providers/notification_provider.dart';
import '../profile/astrologer_certificates_screen.dart';
import '../profile/astrologer_profile_sections.dart';
import 'astrologer_common.dart';

/// Dashboard overview for the marketplace astrologer: revenue, customer and
/// rating stats, profile/subscription status, quick actions and recent
/// activity. No appointments, user lists or user management — astrologers are
/// service providers, not user managers.
class AstrologerOverviewTab extends ConsumerWidget {
  /// Lets quick actions switch the dashboard's bottom-nav tab (Reviews,
  /// Notifications) that live as siblings of this tab.
  final void Function(int index)? onSelectTab;
  const AstrologerOverviewTab({super.key, this.onSelectTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAstrologerAccountProvider);
    if (account == null) return const AstrologerLoading();

    final requests =
        ref.watch(astrologerRequestsProvider).valueOrNull ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (!account.isApproved) _verificationBanner(account),
        // ── Revenue ─────────────────────────────────────────────────────
        const AstrologerSectionTitle('Revenue'),
        _revenueRow(requests),
        const SizedBox(height: 18),
        // ── Customers ───────────────────────────────────────────────────
        const AstrologerSectionTitle('Customers'),
        _customersRow(requests, account),
        const SizedBox(height: 18),
        // ── Ratings ─────────────────────────────────────────────────────
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
        const SizedBox(height: 18),
        // ── Profile status ──────────────────────────────────────────────
        const AstrologerSectionTitle('Profile Status'),
        _profileStatusCard(account),
        const SizedBox(height: 20),
        // ── Subscription ────────────────────────────────────────────────
        const AstrologerSectionTitle('Subscription'),
        _subscriptionCard(context, ref, account),
        const SizedBox(height: 20),
        // ── Quick actions ───────────────────────────────────────────────
        const AstrologerSectionTitle('Quick Actions'),
        _quickActions(context, ref),
        const SizedBox(height: 20),
        // ── Recent activity ─────────────────────────────────────────────
        const AstrologerSectionTitle('Recent Activity'),
        _recentActivity(ref),
      ],
    );
  }

  // ── Revenue (Today / Monthly / Total) ──────────────────────────────────
  Widget _revenueRow(List<AstrologerRequestModel> requests) {
    final now = DateTime.now();
    var today = 0, month = 0, total = 0;
    for (final r in requests) {
      if (r.status != AstrologerRequestStatus.completed) continue;
      final d = r.respondedAt ?? r.createdAt;
      total += r.amount;
      if (d.year == now.year && d.month == now.month) {
        month += r.amount;
        if (d.day == now.day) today += r.amount;
      }
    }
    return Row(
      children: [
        Expanded(
            child: _StatCard("Today's", '₹$today', Icons.today,
                AppColors.success)),
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

  // ── Customers ──────────────────────────────────────────────────────────
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

  // ── Profile status ─────────────────────────────────────────────────────
  Widget _profileStatusCard(AstrologerAccount a) {
    Color c;
    IconData icon;
    switch (a.status) {
      case VerificationStatus.approved:
        c = AppColors.success;
        icon = Icons.verified;
        break;
      case VerificationStatus.rejected:
        c = AppColors.error;
        icon = Icons.cancel;
        break;
      case VerificationStatus.pending:
        c = AppColors.warning;
        icon = Icons.hourglass_top;
        break;
    }
    return AstrologerCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: c),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Verification', style: TextStyle(
                    fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(a.status.label,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: c, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick actions ──────────────────────────────────────────────────────
  Widget _quickActions(BuildContext context, WidgetRef ref) {
    Widget tile(IconData icon, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AstrologerCard(
            onTap: onTap,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Icon(icon, size: 19, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                const Icon(Icons.arrow_forward_ios, size: 14),
              ],
            ),
          ),
        );

    void open(Widget screen) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));

    return Column(
      children: [
        tile(Icons.person_outline, 'Edit Profile',
            () => open(const AstrologerPersonalDetailsScreen())),
        tile(Icons.workspace_premium_outlined, 'Manage Certificates',
            () => open(const AstrologerCertificatesScreen())),
        tile(Icons.star_outline, 'View Reviews', () => onSelectTab?.call(1)),
        tile(Icons.card_membership_outlined, 'Subscription Plans',
            () => kSubscriptionTestMode
                ? _activate(context, ref)
                : _renew(context)),
        tile(Icons.notifications_none, 'Notifications',
            () => onSelectTab?.call(2)),
      ],
    );
  }

  // ── Subscription card ─────────────────────────────────────────────────
  Widget _subscriptionCard(
      BuildContext context, WidgetRef ref, AstrologerAccount a) {
    final active = a.subscriptionActive;
    final hasPlan = a.subscriptionExpiry != null;
    final planLabel = a.subscriptionPlan == 'yearly'
        ? 'Yearly Plan'
        : a.subscriptionPlan == 'monthly'
            ? 'Monthly Plan'
            : 'No active plan';
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                'Subscribe to a monthly or yearly plan to appear in user '
                'listings, search and recommendations.',
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
                ? _activate(context, ref)
                : _renew(context),
            icon: Icon(kSubscriptionTestMode
                ? Icons.workspace_premium
                : Icons.autorenew),
            label: Text(kSubscriptionTestMode
                ? 'Activate Plan'
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

  /// TEST MODE — pick Monthly / Yearly and activate instantly (no payment).
  void _activate(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Activate Plan (Test Mode)',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Payment is bypassed — the plan activates immediately.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
              const SizedBox(height: 16),
              _planTile(sheetCtx, ref, 'monthly', 'Monthly Plan', '30 days'),
              const SizedBox(height: 10),
              _planTile(sheetCtx, ref, 'yearly', 'Yearly Plan', '365 days'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planTile(BuildContext sheetCtx, WidgetRef ref, String type,
          String title, String validity) =>
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          Navigator.pop(sheetCtx);
          final messenger = ScaffoldMessenger.of(sheetCtx);
          await ref
              .read(myAstrologerAccountProvider.notifier)
              .activateSubscription(type);
          messenger.showSnackBar(
              SnackBar(content: Text('$title activated (test mode).')));
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium, color: AppColors.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('Valid for $validity',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 14, color: AppColors.primary),
            ],
          ),
        ),
      );

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
            'To renew your monthly or yearly plan, please contact the platform '
            'admin. Your profile stays visible to users while your subscription '
            'is active.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // ── Recent activity (from the astrologer's notifications) ──────────────
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

  Widget _verificationBanner(AstrologerAccount a) {
    final rejected = a.status == VerificationStatus.rejected;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            (rejected ? AppColors.error : AppColors.warning).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
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
    );
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
