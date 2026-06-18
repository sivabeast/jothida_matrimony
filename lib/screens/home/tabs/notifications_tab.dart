import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../models/announcement_model.dart';
import '../../../models/notification_model.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/notification_provider.dart';

/// Notification page — admin announcements (platform-wide) plus the user's own
/// notifications (interests, approvals…), merged newest-first.
class NotificationsTab extends ConsumerStatefulWidget {
  const NotificationsTab({super.key});

  @override
  ConsumerState<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends ConsumerState<NotificationsTab> {
  @override
  void initState() {
    super.initState();
    // Opening the inbox clears the announcement unread badge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(announcementsLastSeenProvider.notifier).markSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final announcements =
        ref.watch(announcementsProvider).valueOrNull ?? const <AnnouncementModel>[];
    final notifsAsync = ref.watch(notificationsProvider);
    final notifs = notifsAsync.valueOrNull ?? const <NotificationModel>[];

    if (notifsAsync.isLoading && announcements.isEmpty && notifs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Unified, date-sorted feed.
    final items = <_Item>[
      ...announcements.map(_Item.announcement),
      ...notifs.map(_Item.notification),
    ]..sort((a, b) => b.date.compareTo(a.date));

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(context.l10n.noNotifications,
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => items[i].build(context, ref),
    );
  }
}

/// One row in the merged feed — either an admin announcement or a per-user
/// notification.
class _Item {
  final DateTime date;
  final Widget Function(BuildContext, WidgetRef) build;
  const _Item(this.date, this.build);

  factory _Item.announcement(AnnouncementModel a) =>
      _Item(a.createdAt, (context, ref) => _announcementTile(a));

  factory _Item.notification(NotificationModel n) =>
      _Item(n.createdAt, (context, ref) => _notificationTile(context, ref, n));

  static Widget _announcementTile(AnnouncementModel a) => ListTile(
        tileColor: AppColors.gold.withOpacity(0.06),
        leading: CircleAvatar(
          backgroundColor: AppColors.gold.withOpacity(0.18),
          child: const Icon(Icons.campaign, color: AppColors.gold, size: 22),
        ),
        title: Text(a.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(a.message),
        isThreeLine: a.message.length > 40,
        trailing: Text(_fmtDate(a.createdAt),
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      );

  static Widget _notificationTile(
          BuildContext context, WidgetRef ref, NotificationModel n) =>
      ListTile(
        tileColor: n.isRead ? null : AppColors.primary.withOpacity(0.04),
        leading: CircleAvatar(
          backgroundColor: _typeColor(n.type).withOpacity(0.15),
          child: Icon(_typeIcon(n.type), color: _typeColor(n.type), size: 22),
        ),
        title: Text(n.title,
            style: TextStyle(
                fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold)),
        subtitle: Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Text(_timeAgo(n.createdAt),
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        onTap: () {
          if (!n.isRead) {
            ref.read(notificationNotifierProvider.notifier).markRead(n.id);
          }
        },
      );

  static Color _typeColor(String type) {
    switch (type) {
      case 'interest_received':
        return Colors.pink;
      case 'interest_accepted':
        return Colors.green;
      case 'porutham_ready':
        return Colors.orange;
      case 'subscription_expiry':
        return Colors.red;
      case 'profile_approval':
        return AppColors.primary;
      default:
        return Colors.blue;
    }
  }

  static IconData _typeIcon(String type) {
    switch (type) {
      case 'interest_received':
        return Icons.favorite;
      case 'interest_accepted':
        return Icons.check_circle;
      case 'interest_rejected':
        return Icons.cancel;
      case 'porutham_ready':
        return Icons.star;
      case 'subscription_expiry':
        return Icons.access_time;
      case 'profile_approval':
        return Icons.verified_user;
      default:
        return Icons.notifications;
    }
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return _fmtDate(dt);
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
