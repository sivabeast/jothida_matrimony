import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/match_analysis_provider.dart';

/// The lightweight INTERNAL Astrology Dashboard.
///
/// This is NOT the old per-astrologer dashboard (earnings, availability,
/// consultations, reviews…). There is one internal astrology service owned by
/// the app owner, reachable only by [AdminConfig.internalAstrologyEmail] (and,
/// for oversight, the super-admin). It does ONE job: triage the Match Analysis
/// requests users send, then open each request's workspace to view the user /
/// partner details, horoscope files, chat with the user and submit the report.
///
/// Tapping a request opens [MatchWorkspaceScreen] (`/match-workspace/:id`),
/// which already renders Request Details · User Details · Partner Details ·
/// Horoscope Files · Compare Horoscopes · Chat/Analysis · Report editor.
class AstrologyDashboardScreen extends ConsumerStatefulWidget {
  const AstrologyDashboardScreen({super.key});

  @override
  ConsumerState<AstrologyDashboardScreen> createState() =>
      _AstrologyDashboardScreenState();
}

class _AstrologyDashboardScreenState
    extends ConsumerState<AstrologyDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Sign out of the Astrology Dashboard?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authNotifierProvider.notifier).signOut();
    router.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(internalAstrologyRequestsProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Astrology Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(internalAstrologyRequestsProvider),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          tabs: const [
            Tab(text: 'New'),
            Tab(text: 'In Progress'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _error(),
        data: (all) {
          final newReqs = all
              .where((r) =>
                  r.status == AstrologerRequestStatus.pending ||
                  (r.status == AstrologerRequestStatus.accepted &&
                      !r.inProgress))
              .toList();
          final inProgress = all
              .where((r) =>
                  r.status == AstrologerRequestStatus.accepted && r.inProgress)
              .toList();
          final done = all
              .where((r) =>
                  r.status == AstrologerRequestStatus.completed ||
                  r.status == AstrologerRequestStatus.rejected)
              .toList();
          return TabBarView(
            controller: _tab,
            children: [
              _RequestList(
                  requests: newReqs,
                  emptyIcon: Icons.inbox_outlined,
                  emptyText: 'No new match-analysis requests.'),
              _RequestList(
                  requests: inProgress,
                  emptyIcon: Icons.hourglass_empty,
                  emptyText: 'Nothing in progress right now.'),
              _RequestList(
                  requests: done,
                  emptyIcon: Icons.verified_outlined,
                  emptyText: 'No completed analyses yet.'),
            ],
          );
        },
      ),
    );
  }

  Widget _error() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: AppColors.error),
              const SizedBox(height: 12),
              const Text('Could not load requests'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.invalidate(internalAstrologyRequestsProvider),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
}

class _RequestList extends StatelessWidget {
  final List<AstrologerRequestModel> requests;
  final IconData emptyIcon;
  final String emptyText;
  const _RequestList({
    required this.requests,
    required this.emptyIcon,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon, size: 60, color: AppColors.primary.withOpacity(0.3)),
              const SizedBox(height: 12),
              Text(emptyText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _RequestCard(request: requests[i]),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final AstrologerRequestModel request;
  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final date = DateFormat('d MMM yyyy · h:mm a').format(r.createdAt);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () =>
          context.push('/match-workspace/${r.id}', extra: r),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: r.userPhotoUrl.isNotEmpty
                      ? NetworkImage(r.userPhotoUrl)
                      : null,
                  child: r.userPhotoUrl.isEmpty
                      ? const Icon(Icons.person, color: AppColors.primary)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.userName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(date,
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey[600])),
                    ],
                  ),
                ),
                _statusChip(r),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.favorite,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${r.groomName ?? 'Groom'}  ⚭  ${r.brideName ?? 'Bride'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (r.message.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('“${r.message.trim()}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[700])),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.chevron_right, size: 18, color: Colors.grey[500]),
                const SizedBox(width: 2),
                Text(
                  r.status == AstrologerRequestStatus.pending
                      ? 'Open to review & Start'
                      : 'Open workspace',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(AstrologerRequestModel r) {
    final (label, color) = switch (r.status) {
      AstrologerRequestStatus.pending => ('New', AppColors.warning),
      AstrologerRequestStatus.accepted =>
        r.inProgress ? ('In Progress', AppColors.info) : ('Accepted', AppColors.info),
      AstrologerRequestStatus.completed => ('Completed', AppColors.success),
      AstrologerRequestStatus.rejected => ('Rejected', AppColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
