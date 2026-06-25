import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/dev_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../providers/astrologer_session_provider.dart';
import '../../../providers/service_providers.dart';
import 'astrologer_common.dart';

/// Incoming consultation / inquiry / matching requests, newest first.
/// Accept / Reject move a request through its lifecycle (and therefore into the
/// Appointments tab). View Details shows the full request.
class AstrologerRequestsTab extends ConsumerWidget {
  const AstrologerRequestsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(astrologerRequestsProvider);

    return requestsAsync.when(
      loading: () => const AstrologerLoading(),
      error: (_, __) => AstrologerErrorState(
        onRetry: () => ref.invalidate(astrologerRequestsProvider),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return const AstrologerEmptyState(
            icon: Icons.inbox_outlined,
            message: 'No consultation requests available',
            hint: 'New requests from users will appear here.',
          );
        }
        final sorted = [...requests]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _RequestCard(request: sorted[i]),
        );
      },
    );
  }
}

Color statusColor(AstrologerRequestStatus s) {
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

class _RequestCard extends ConsumerWidget {
  final AstrologerRequestModel request;
  const _RequestCard({required this.request});

  Future<void> _setStatus(
      BuildContext context, WidgetRef ref, AstrologerRequestStatus status) async {
    try {
      if (kBypassAuth) {
        ref
            .read(demoAstrologerRequestsProvider.notifier)
            .setStatus(request.id, status);
      } else {
        await ref
            .read(astrologerServiceProvider)
            .updateRequestStatus(request.id, status);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update — please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = statusColor(request.status);
    return AstrologerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: request.userPhotoUrl.isNotEmpty
                    ? NetworkImage(request.userPhotoUrl)
                    : null,
                child: request.userPhotoUrl.isEmpty
                    ? Text(
                        request.userName.isNotEmpty ? request.userName[0] : '?',
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
                    Text(request.userName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_outlined,
                            size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(request.type.label,
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.grey[700])),
                        ),
                      ],
                    ),
                    if (request.userLocation.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(request.userLocation,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.schedule,
                            size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(astrologerDateTime(request.createdAt),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              ),
              _statusChip(request.status, color),
            ],
          ),
          if (request.message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(request.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey[800])),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (request.amount > 0)
                Text('₹${request.amount}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showDetails(context),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Details'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary),
              ),
              if (request.status == AstrologerRequestStatus.pending) ...[
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => _setStatus(
                      context, ref, AstrologerRequestStatus.rejected),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () => _setStatus(
                      context, ref, AstrologerRequestStatus.accepted),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Accept'),
                ),
              ] else if (request.status ==
                  AstrologerRequestStatus.accepted) ...[
                const SizedBox(width: 4),
                if (request.isMatchAnalysis)
                  ElevatedButton.icon(
                    onPressed: () =>
                        context.push('/match-workspace/${request.id}', extra: request),
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('Open Workspace'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: () => _setStatus(
                        context, ref, AstrologerRequestStatus.completed),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Mark Completed'),
                  ),
              ] else if (request.status ==
                      AstrologerRequestStatus.completed &&
                  request.isMatchAnalysis) ...[
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/match-workspace/${request.id}', extra: request),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View Analysis'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(AstrologerRequestStatus s, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(s.label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: request.userPhotoUrl.isNotEmpty
                      ? NetworkImage(request.userPhotoUrl)
                      : null,
                  child: request.userPhotoUrl.isEmpty
                      ? Text(
                          request.userName.isNotEmpty
                              ? request.userName[0]
                              : '?',
                          style: const TextStyle(color: AppColors.primary))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(request.userName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                _statusChip(request.status, statusColor(request.status)),
              ],
            ),
            const SizedBox(height: 18),
            _detailRow('Service', request.type.label),
            if (request.userLocation.isNotEmpty)
              _detailRow('Location', request.userLocation),
            _detailRow('Requested', astrologerDateTime(request.createdAt)),
            if (request.respondedAt != null)
              _detailRow('Responded', astrologerDateTime(request.respondedAt!)),
            if (request.amount > 0) _detailRow('Fee', '₹${request.amount}'),
            if (request.message.isNotEmpty) _detailRow('Message', request.message),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 96,
                child: Text(label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );
}
