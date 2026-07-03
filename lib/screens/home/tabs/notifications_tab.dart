import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../models/announcement_model.dart';
import '../../../models/notification_model.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../notifications/notification_detail_screen.dart';

/// Notification page — admin announcements (platform-wide) plus the user's own
/// notifications (interests, approvals…), merged newest-first.
///
/// Read/unread contract:
///  • every NEW notification arrives Unread and shows a dot + highlight;
///  • tapping a row marks THAT item read and opens its full details page;
///  • a read item never flips back to Unread. (Nothing is bulk-marked read just
///    because the list was opened — that was the old, buggy behaviour.)
class NotificationsTab extends ConsumerWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

void _openDetails(BuildContext context, NotificationDetailArgs args) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => NotificationDetailScreen(args: args),
  ));
}

/// One row in the merged feed — either an admin announcement or a per-user
/// notification.
class _Item {
  final DateTime date;
  final Widget Function(BuildContext, WidgetRef) build;
  const _Item(this.date, this.build);

  factory _Item.announcement(AnnouncementModel a) =>
      _Item(a.createdAt, (context, ref) => _AnnouncementTile(announcement: a));

  factory _Item.notification(NotificationModel n) =>
      _Item(n.createdAt, (context, ref) => _NotificationTile(notification: n));

  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return fmtDate(dt);
  }

  static String fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// The small "new" dot shown on unread rows.
class _UnreadDot extends StatelessWidget {
  final Color color;
  const _UnreadDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── Admin announcement row ────────────────────────────────────────────────────

class _AnnouncementTile extends ConsumerWidget {
  final AnnouncementModel announcement;
  const _AnnouncementTile({required this.announcement});

  static (IconData, Color) _visual(AnnouncementType t) => switch (t) {
        AnnouncementType.featureUpdate =>
          (Icons.new_releases_outlined, Colors.blue),
        AnnouncementType.offer => (Icons.local_offer_outlined, Colors.orange),
        AnnouncementType.maintenance =>
          (Icons.build_circle_outlined, Colors.brown),
        AnnouncementType.announcement => (Icons.campaign, AppColors.gold),
        _ => (Icons.notifications_none, AppColors.primary),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = announcement;
    final readIds = ref.watch(announcementsReadProvider);
    final lastSeen = ref.watch(announcementsLastSeenProvider);
    final unread = isAnnouncementUnread(a, readIds, lastSeen);
    final (icon, color) = _visual(a.typeEnum);

    return ListTile(
      tileColor: unread ? color.withOpacity(0.06) : null,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(a.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(a.message, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_Item.timeAgo(a.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (unread) ...[
            const SizedBox(height: 5),
            _UnreadDot(color: color),
          ],
        ],
      ),
      onTap: () {
        // Opening the details is what marks it read — permanently.
        ref.read(announcementsReadProvider.notifier).markRead(a.id);
        _openDetails(
          context,
          NotificationDetailArgs(
            title: a.title,
            body: a.message,
            date: a.createdAt,
            typeLabel: a.typeEnum.label,
            icon: icon,
            color: color,
            actionUrl: a.hasAction ? a.actionUrl : null,
            actionLabel: a.effectiveActionLabel,
          ),
        );
      },
    );
  }
}

// ── Per-user notification row ─────────────────────────────────────────────────

class _NotificationTile extends ConsumerWidget {
  final NotificationModel notification;
  const _NotificationTile({required this.notification});

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

  static String _typeLabel(String type) {
    switch (type) {
      case 'interest_received':
        return 'Interest Received';
      case 'interest_accepted':
        return 'Interest Accepted';
      case 'interest_rejected':
        return 'Interest Update';
      case 'porutham_ready':
        return 'Horoscope Match';
      case 'subscription_expiry':
        return 'Subscription';
      case 'profile_approval':
        return 'Profile';
      default:
        return 'Notification';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final color = _typeColor(n.type);
    final unread = !n.isRead;

    return ListTile(
      tileColor: unread ? AppColors.primary.withOpacity(0.04) : null,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(_typeIcon(n.type), color: color, size: 22),
      ),
      title: Text(n.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_Item.timeAgo(n.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (unread) ...[
            const SizedBox(height: 5),
            _UnreadDot(color: AppColors.primary),
          ],
        ],
      ),
      onTap: () {
        // Opening the details marks it read once and for all.
        if (unread) {
          ref.read(notificationNotifierProvider.notifier).markRead(n.id);
        }
        final route = n.data?['route']?.toString();
        _openDetails(
          context,
          NotificationDetailArgs(
            title: n.title,
            body: n.body,
            date: n.createdAt,
            typeLabel: _typeLabel(n.type),
            icon: _typeIcon(n.type),
            color: color,
            actionUrl: (route != null && route.isNotEmpty) ? route : null,
            actionLabel: 'Open',
          ),
        );
      },
    );
  }
}
