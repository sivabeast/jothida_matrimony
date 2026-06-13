import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_account_model.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../models/chat_model.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../../../providers/chat_provider.dart';
import 'astrologer_common.dart';

/// Dashboard overview: headline stats + recent activity. All figures are
/// computed from real Firestore data (requests, account rating, earnings).
class AstrologerOverviewTab extends ConsumerWidget {
  const AstrologerOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAstrologerAccountProvider);
    final requestsAsync = ref.watch(astrologerRequestsProvider);

    if (account == null) return const AstrologerLoading();

    return requestsAsync.when(
      loading: () => const AstrologerLoading(),
      error: (_, __) => AstrologerErrorState(
        onRetry: () => ref.invalidate(astrologerRequestsProvider),
      ),
      data: (requests) => _content(context, ref, account, requests),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    AstrologerAccount account,
    List<AstrologerRequestModel> requests,
  ) {
    int countOf(AstrologerRequestStatus s) =>
        requests.where((r) => r.status == s).length;

    final total = requests.length;
    final pending = countOf(AstrologerRequestStatus.pending);
    final accepted = countOf(AstrologerRequestStatus.accepted);
    final completed = countOf(AstrologerRequestStatus.completed);
    final earnings = ref.watch(astrologerEarningsProvider).valueOrNull ?? 0;

    final recentRequests = [
      for (final r in requests)
        if (r.status == AstrologerRequestStatus.pending) r,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final upcoming = [
      for (final r in requests)
        if (r.status == AstrologerRequestStatus.accepted) r,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (!account.isApproved) _verificationBanner(account),
        // ── Stats grid ──────────────────────────────────────────────────
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            _StatCard('Total Requests', '$total', Icons.assignment_outlined,
                AppColors.primary),
            _StatCard('Pending', '$pending',
                Icons.hourglass_top_outlined, AppColors.warning),
            _StatCard('Accepted', '$accepted',
                Icons.check_circle_outline, AppColors.info),
            _StatCard('Completed', '$completed',
                Icons.task_alt_outlined, AppColors.success),
            _StatCard('Avg Rating', account.rating.toStringAsFixed(1),
                Icons.star_outline, AppColors.gold),
            _StatCard('Total Earnings', '₹$earnings',
                Icons.payments_outlined, AppColors.success),
            _StatCard('Profile Views', '0', Icons.visibility_outlined,
                AppColors.textSecondary),
          ],
        ),
        const SizedBox(height: 18),
        // ── Rating summary (aggregate only — never reviewer identities) ──
        _ratingSummary(account),
        const SizedBox(height: 20),
        // ── Recent activity ─────────────────────────────────────────────
        const AstrologerSectionTitle('New Consultation Requests'),
        if (recentRequests.isEmpty)
          _mutedTile('No new requests')
        else
          ...recentRequests.take(3).map((r) => _activityTile(
                icon: Icons.assignment_outlined,
                title: r.userName,
                subtitle: r.type.label,
                trailing: astrologerRelativeTime(r.createdAt),
              )),
        const SizedBox(height: 16),
        const AstrologerSectionTitle('Upcoming Appointments'),
        if (upcoming.isEmpty)
          _mutedTile('No upcoming appointments')
        else
          ...upcoming.take(3).map((r) => _activityTile(
                icon: Icons.event_available_outlined,
                title: r.userName,
                subtitle: r.type.label,
                trailing: astrologerRelativeTime(r.createdAt),
              )),
        const SizedBox(height: 16),
        const AstrologerSectionTitle('New Messages'),
        _recentMessages(context, ref),
      ],
    );
  }

  Widget _recentMessages(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(myUidProvider) ?? '';
    final threads = ref.watch(myChatThreadsProvider).valueOrNull ?? const [];
    if (threads.isEmpty) return _mutedTile('No messages yet');
    return Column(
      children: [
        for (final ChatThread t in threads.take(3))
          _activityTile(
            icon: Icons.chat_bubble_outline,
            title: t.otherName(myUid),
            subtitle: t.lastMessage.isEmpty ? 'Say hello!' : t.lastMessage,
            trailing: t.lastMessageAt != null
                ? astrologerRelativeTime(t.lastMessageAt!)
                : '',
            badge: t.unreadFor(myUid),
            onTap: () => context.push('/chat/${t.id}', extra: {
              'name': t.otherName(myUid),
              'photo': t.otherPhoto(myUid),
            }),
          ),
      ],
    );
  }

  Widget _ratingSummary(AstrologerAccount account) => AstrologerCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(account.rating.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 34, fontWeight: FontWeight.bold)),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < account.rating.round()
                          ? Icons.star
                          : Icons.star_border,
                      color: AppColors.gold,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${account.reviewCount} reviews',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ],
        ),
      );

  Widget _activityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String trailing,
    int badge = 0,
    VoidCallback? onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AstrologerCard(
          onTap: onTap,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (trailing.isNotEmpty)
                    Text(trailing,
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500])),
                  if (badge > 0) ...[
                    const SizedBox(height: 4),
                    CircleAvatar(
                      radius: 9,
                      backgroundColor: AppColors.primary,
                      child: Text('$badge',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );

  Widget _mutedTile(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AstrologerCard(
          child: Row(
            children: [
              Icon(Icons.inbox_outlined, size: 18, color: Colors.grey[400]),
              const SizedBox(width: 10),
              Text(text, style: TextStyle(color: Colors.grey[500])),
            ],
          ),
        ),
      );

  Widget _verificationBanner(AstrologerAccount a) {
    final rejected = a.status == VerificationStatus.rejected;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (rejected ? AppColors.error : AppColors.warning)
            .withOpacity(0.12),
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
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      );
}
