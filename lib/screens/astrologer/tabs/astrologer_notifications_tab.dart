import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/announcement_model.dart';
import '../../../models/notification_model.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/notification_provider.dart';
import 'astrologer_common.dart';

/// The astrologer's notifications — admin announcements plus their own
/// certificate approvals/rejections, subscription and platform updates.
class AstrologerNotificationsTab extends ConsumerStatefulWidget {
  const AstrologerNotificationsTab({super.key});

  @override
  ConsumerState<AstrologerNotificationsTab> createState() =>
      _AstrologerNotificationsTabState();
}

class _AstrologerNotificationsTabState
    extends ConsumerState<AstrologerNotificationsTab> {
  // NOTE: announcements are no longer bulk-marked "seen" when the list opens —
  // each one is marked read individually when tapped (see _AnnouncementCard).

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    final announcements = ref.watch(announcementsProvider).valueOrNull ??
        const <AnnouncementModel>[];
    final notifs = async.valueOrNull ?? const <NotificationModel>[];

    if (async.isLoading && announcements.isEmpty && notifs.isEmpty) {
      return const AstrologerLoading();
    }
    if (announcements.isEmpty && notifs.isEmpty) {
      return const AstrologerEmptyState(
        icon: Icons.notifications_none,
        message: 'No notifications yet',
        hint: 'Announcements, certificate and subscription updates appear here.',
      );
    }

    // Merge admin announcements + the astrologer's own notifications.
    final rows = <_Row>[
      ...announcements.map((a) => _Row(a.createdAt, _AnnouncementCard(a))),
      ...notifs.map(
          (n) => _Row(n.createdAt, _NotificationCard(notification: n))),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => rows[i].child,
    );
  }
}

class _Row {
  final DateTime date;
  final Widget child;
  const _Row(this.date, this.child);
}

/// Admin announcement card — tapping it marks the announcement read.
class _AnnouncementCard extends ConsumerWidget {
  final AnnouncementModel announcement;
  const _AnnouncementCard(this.announcement);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readIds = ref.watch(announcementsReadProvider);
    final lastSeen = ref.watch(announcementsLastSeenProvider);
    final unread = isAnnouncementUnread(announcement, readIds, lastSeen);

    return AstrologerCard(
      onTap: () =>
          ref.read(announcementsReadProvider.notifier).markRead(announcement.id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.campaign, size: 20, color: AppColors.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(announcement.title,
                          style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 14)),
                    ),
                    if (unread)
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                            color: AppColors.gold, shape: BoxShape.circle),
                      ),
                  ],
                ),
                if (announcement.message.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(announcement.message,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
                const SizedBox(height: 5),
                Text(astrologerRelativeTime(announcement.createdAt),
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
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
    final route = notification.data?['route']?.toString();
    return AstrologerCard(
      onTap: () {
        if (!notification.isRead) {
          ref
              .read(notificationNotifierProvider.notifier)
              .markRead(notification.id);
        }
        // Tapping opens the corresponding booking/request (spec §8).
        if (route != null && route.isNotEmpty) context.push(route);
      },
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
