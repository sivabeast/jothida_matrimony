import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_account_model.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../../../providers/notification_provider.dart';
import 'astrologer_common.dart';

/// Dashboard overview for the marketplace astrologer: headline stats,
/// subscription status, and recent activity. No appointments, leads or user
/// data — just the astrologer's own performance and account.
class AstrologerOverviewTab extends ConsumerWidget {
  const AstrologerOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAstrologerAccountProvider);
    if (account == null) return const AstrologerLoading();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (!account.isApproved) _verificationBanner(account),
        // ── Headline stats ──────────────────────────────────────────────
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _StatCard('Profile Views', '${account.profileViews}',
                Icons.visibility_outlined, AppColors.primary),
            _StatCard('Contact Unlocks', '${account.contactUnlocks}',
                Icons.lock_open_outlined, AppColors.info),
            _StatCard('Avg Rating', account.rating.toStringAsFixed(1),
                Icons.star_outline, AppColors.gold),
            _StatCard('Total Reviews', '${account.reviewCount}',
                Icons.reviews_outlined, AppColors.success),
          ],
        ),
        const SizedBox(height: 20),
        // ── Subscription ────────────────────────────────────────────────
        const AstrologerSectionTitle('Subscription'),
        _subscriptionCard(context, account),
        const SizedBox(height: 20),
        // ── Recent activity ─────────────────────────────────────────────
        const AstrologerSectionTitle('Recent Activity'),
        _recentActivity(ref),
      ],
    );
  }

  // ── Subscription card ─────────────────────────────────────────────────
  Widget _subscriptionCard(BuildContext context, AstrologerAccount a) {
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
            onPressed: () => _renew(context),
            icon: const Icon(Icons.autorenew),
            label: const Text('Renew Subscription'),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      );
}
