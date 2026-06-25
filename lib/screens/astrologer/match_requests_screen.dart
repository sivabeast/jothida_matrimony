import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/match_analysis_provider.dart';

/// Dedicated Match Analysis Requests module for the astrologer.
///
/// Lists the porutham bookings addressed to this astrologer in
/// Pending / Accepted / Completed tabs. Tapping a request opens the workspace,
/// where the astrologer can review the full groom & bride profiles (with
/// horoscope images & PDFs), Accept / Reject, and submit the analysis.
class MatchRequestsScreen extends ConsumerWidget {
  /// Optional initial tab (0 = Pending, 1 = Accepted, 2 = Completed).
  final int initialTab;
  const MatchRequestsScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(astrologerMatchRequestsProvider);
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Match Analysis Requests'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Accepted'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: async.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (_, __) => _error(ref),
          data: (all) {
            // Pending tab also shows rejected outcomes (status chip clarifies).
            final pending = all
                .where((r) =>
                    r.status == AstrologerRequestStatus.pending ||
                    r.status == AstrologerRequestStatus.rejected)
                .toList();
            final accepted = all
                .where((r) => r.status == AstrologerRequestStatus.accepted)
                .toList();
            final completed = all
                .where((r) => r.status == AstrologerRequestStatus.completed)
                .toList();
            return TabBarView(
              children: [
                _list(pending, 'No pending requests'),
                _list(accepted, 'No accepted requests'),
                _list(completed, 'No completed analysis'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(List<AstrologerRequestModel> items, String emptyMsg) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined,
                  size: 56, color: AppColors.primary.withOpacity(0.35)),
              const SizedBox(height: 12),
              Text(emptyMsg,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ],
          ),
        ),
      );
    }
    final sorted = [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _RequestCard(request: sorted[i]),
    );
  }

  Widget _error(WidgetRef ref) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 12),
            const Text('Could not load requests'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(astrologerMatchRequestsProvider),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
}

Color matchStatusColor(AstrologerRequestStatus s) {
  switch (s) {
    case AstrologerRequestStatus.pending:
      return AppColors.warning;
    case AstrologerRequestStatus.accepted:
      return AppColors.info;
    case AstrologerRequestStatus.completed:
      return AppColors.success;
    case AstrologerRequestStatus.rejected:
      return AppColors.error;
  }
}

class _RequestCard extends StatelessWidget {
  final AstrologerRequestModel request;
  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final color = matchStatusColor(r.status);
    final cta = r.status == AstrologerRequestStatus.pending
        ? 'Review & Respond'
        : r.status == AstrologerRequestStatus.accepted
            ? 'Open Status'
            : 'View Analysis';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/match-workspace/${r.id}', extra: r),
      child: Container(
        padding: const EdgeInsets.all(14),
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
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: r.userPhotoUrl.isNotEmpty
                      ? NetworkImage(r.userPhotoUrl)
                      : null,
                  child: r.userPhotoUrl.isEmpty
                      ? Text(r.userName.isNotEmpty ? r.userName[0] : '?',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.userName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(DateFormat('d MMM yyyy, h:mm a').format(r.createdAt),
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(r.status.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.favorite, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${r.groomName ?? 'Groom'}  ×  ${r.brideName ?? 'Bride'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                  if (r.amount > 0)
                    Text('₹${r.amount}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                ],
              ),
            ),
            if (r.message.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(r.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(cta,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const Icon(Icons.arrow_forward_ios,
                    size: 13, color: AppColors.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
