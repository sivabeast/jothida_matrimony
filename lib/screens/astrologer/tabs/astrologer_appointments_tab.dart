import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../providers/astrologer_session_provider.dart';
import 'astrologer_common.dart';

/// Appointments grouped into Upcoming / Completed / Cancelled. Derived from the
/// real consultation lifecycle (accepted → upcoming, completed → completed,
/// rejected → cancelled) — see [AppointmentBucket].
class AstrologerAppointmentsTab extends ConsumerWidget {
  const AstrologerAppointmentsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(astrologerRequestsProvider);

    return requestsAsync.when(
      loading: () => const AstrologerLoading(),
      error: (_, __) => AstrologerErrorState(
        onRetry: () => ref.invalidate(astrologerRequestsProvider),
      ),
      data: (requests) {
        List<AstrologerRequestModel> bucket(AppointmentBucket b) {
          final list = [
            for (final r in requests)
              if (r.appointmentBucket == b) r,
          ]..sort((a, b) => (b.respondedAt ?? b.createdAt)
              .compareTo(a.respondedAt ?? a.createdAt));
          return list;
        }

        final upcoming = bucket(AppointmentBucket.upcoming);
        final completed = bucket(AppointmentBucket.completed);
        final cancelled = bucket(AppointmentBucket.cancelled);

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Material(
                color: Colors.white,
                child: TabBar(
                  labelColor: AppColors.primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppColors.primary,
                  tabs: [
                    Tab(text: 'Upcoming (${upcoming.length})'),
                    Tab(text: 'Completed (${completed.length})'),
                    Tab(text: 'Cancelled (${cancelled.length})'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _list(upcoming, AppointmentBucket.upcoming),
                    _list(completed, AppointmentBucket.completed),
                    _list(cancelled, AppointmentBucket.cancelled),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _list(List<AstrologerRequestModel> items, AppointmentBucket bucket) {
    if (items.isEmpty) {
      return AstrologerEmptyState(
        icon: Icons.event_busy_outlined,
        message: 'No ${bucket.name} appointments',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _AppointmentCard(request: items[i], bucket: bucket),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final AstrologerRequestModel request;
  final AppointmentBucket bucket;
  const _AppointmentCard({required this.request, required this.bucket});

  Color get _color {
    switch (bucket) {
      case AppointmentBucket.upcoming:
        return AppColors.info;
      case AppointmentBucket.completed:
        return AppColors.success;
      case AppointmentBucket.cancelled:
        return AppColors.error;
    }
  }

  String get _statusLabel {
    switch (bucket) {
      case AppointmentBucket.upcoming:
        return 'Upcoming';
      case AppointmentBucket.completed:
        return 'Completed';
      case AppointmentBucket.cancelled:
        return 'Cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final when = request.respondedAt ?? request.createdAt;
    return AstrologerCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            backgroundImage: request.userPhotoUrl.isNotEmpty
                ? NetworkImage(request.userPhotoUrl)
                : null,
            child: request.userPhotoUrl.isEmpty
                ? Text(request.userName.isNotEmpty ? request.userName[0] : '?',
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.bold))
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
                Text(request.type.label,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 12.5, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(astrologerDateTime(when),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_statusLabel,
                style: TextStyle(
                    fontSize: 11,
                    color: _color,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
