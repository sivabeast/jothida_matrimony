import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/notification_model.dart';
import '../../../providers/notification_provider.dart';
import 'astrologer_common.dart';

/// The astrologer's notifications — certificate approvals/rejections,
/// subscription expiry/renewal, admin announcements and platform updates.
/// Reads the astrologer's own notification stream (their uid).
class AstrologerNotificationsTab extends ConsumerWidget {
  const AstrologerNotificationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);

    return async.when(
      loading: () => const AstrologerLoading(),
      error: (_, __) => AstrologerErrorState(
        onRetry: () => ref.invalidate(notificationsProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const AstrologerEmptyState(
            icon: Icons.notifications_none,
            message: 'No notifications yet',
            hint: 'Certificate, subscription and platform updates appear here.',
          );
        }
        final sorted = [...items]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _NotificationCard(notification: sorted[i]),
        );
      },
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  final NotificationModel notification;
  const _NotificationCard({required this.notification});

  _Visual _visualFor() {
    final s = '${notification.type} ${notification.title}'.toLowerCase();
    if (s.contains('reject')) {
      return const _Visual(Icons.cancel_outlined, AppColors.error);
    }
    if (s.contains('certificate') ||
        s.contains('approv') ||
        s.contains('verif')) {
      return const _Visual(Icons.verified_outlined, AppColors.success);
    }
    if (s.contains('subscription') ||
        s.contains('expir') ||
        s.contains('renew') ||
        s.contains('plan')) {
      return const _Visual(Icons.workspace_premium_outlined, AppColors.gold);
    }
    if (s.contains('announce') || s.contains('update')) {
      return const _Visual(Icons.campaign_outlined, AppColors.info);
    }
    return const _Visual(Icons.notifications_none, AppColors.primary);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = _visualFor();
    return AstrologerCard(
      onTap: notification.isRead
          ? null
          : () => ref
              .read(notificationNotifierProvider.notifier)
              .markRead(notification.id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: v.color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(v.icon, size: 20, color: v.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title.isEmpty
                            ? 'Notification'
                            : notification.title,
                        style: TextStyle(
                            fontWeight: notification.isRead
                                ? FontWeight.w500
                                : FontWeight.bold,
                            fontSize: 14),
                      ),
                    ),
                    if (!notification.isRead)
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                      ),
                  ],
                ),
                if (notification.body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(notification.body,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
                const SizedBox(height: 5),
                Text(astrologerRelativeTime(notification.createdAt),
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + colour pairing for a notification type.
class _Visual {
  final IconData icon;
  final Color color;
  const _Visual(this.icon, this.color);
}
