import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/interest_request_model.dart';
import '../../../models/profile_model.dart';
import '../../../providers/demo_data_provider.dart';
import '../../../providers/requests_provider.dart';

/// Requests screen — messaging-style list of incoming and outgoing interest
/// requests. Incoming pending requests can be Accepted/Rejected; accepted
/// requests (matches) unlock "View Compatibility".
class InterestsTab extends ConsumerStatefulWidget {
  const InterestsTab({super.key});

  @override
  ConsumerState<InterestsTab> createState() => _InterestsTabState();
}

class _InterestsTabState extends ConsumerState<InterestsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(incomingRequestsProvider);
    final outgoing = ref.watch(outgoingRequestsProvider);

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: 'Received (${incoming.length})'),
            Tab(text: 'Sent (${outgoing.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RequestList(requests: incoming),
              _RequestList(requests: outgoing),
            ],
          ),
        ),
      ],
    );
  }
}

class _RequestList extends ConsumerWidget {
  final List<InterestRequest> requests;
  const _RequestList({required this.requests});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text('No requests yet', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _RequestCard(request: requests[i]),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final InterestRequest request;
  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.read(demoProfilesProvider.notifier).byId(request.profileId);
    final name = profile?.name ?? 'Unknown';
    final age = profile?.age;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: (profile?.photos.isNotEmpty ?? false)
                    ? NetworkImage(profile!.photos.first)
                    : null,
                child: (profile?.photos.isEmpty ?? true)
                    ? const Icon(Icons.person, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(age != null ? '$name, $age' : name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          request.isIncoming
                              ? Icons.call_received
                              : Icons.call_made,
                          size: 13,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(_timeAgo(request.timestamp),
                            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              ),
              _statusBadge(request.status),
            ],
          ),
          const SizedBox(height: 10),
          _actions(context, ref, profile),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref, ProfileModel? profile) {
    // Incoming + pending → Accept / Reject
    if (request.isIncoming && request.status == RequestStatus.pending) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () =>
                  ref.read(requestsProvider.notifier).reject(request.id),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                ref.read(requestsProvider.notifier).accept(request.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          "It's a match with ${profile?.name ?? 'this profile'}! 🎉")),
                );
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success, foregroundColor: Colors.white),
              child: const Text('Accept'),
            ),
          ),
        ],
      );
    }
    // Accepted (either direction) → unlock compatibility
    if (request.isAccepted) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => context.push('/match/${request.profileId}'),
          icon: const Icon(Icons.favorite, size: 18),
          label: const Text('View Compatibility'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(42),
          ),
        ),
      );
    }
    // Outgoing pending or rejected → status note only
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        request.status == RequestStatus.rejected
            ? 'This request was declined.'
            : 'Waiting for a response…',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
    );
  }

  Widget _statusBadge(RequestStatus status) {
    final color = status == RequestStatus.accepted
        ? AppColors.success
        : status == RequestStatus.rejected
            ? AppColors.error
            : AppColors.warning;
    final label = status == RequestStatus.accepted
        ? 'Accepted'
        : status == RequestStatus.rejected
            ? 'Declined'
            : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
