import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../models/announcement_model.dart';
import '../../../models/notification_model.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/navigation_provider.dart';
import '../../../providers/notification_provider.dart';

/// Notification page — admin announcements (platform-wide) plus the user's own
/// notifications (interests, approvals…), merged newest-first.
///
/// Read/unread contract (per the notification-flow spec):
///  • every NEW notification arrives Unread and drives the bell badge;
///  • OPENING this page automatically marks EVERYTHING read — the badge
///    disappears and the unread count drops to zero; nothing stays unread
///    after the user has seen the list. The rows still highlight briefly on
///    entry (they're marked read as the page settles).
class NotificationsTab extends ConsumerStatefulWidget {
  const NotificationsTab({super.key});

  @override
  ConsumerState<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends ConsumerState<NotificationsTab> {
  /// Guards for the once-per-open bulk mark-read. SPLIT per source: the two
  /// Firestore streams resolve in nondeterministic order, and a single latch
  /// could fire while the announcements list was still empty — permanently
  /// skipping the announcement badge clear for this open.
  bool _markedNotifsRead = false;
  bool _markedAnnouncementsRead = false;

  void _markAllReadOnce(List<AnnouncementModel> announcements) {
    // Per-user notifications → Firestore batch (badge clears via stream).
    if (!_markedNotifsRead &&
        ref.read(notificationsProvider).hasValue) {
      _markedNotifsRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(notificationNotifierProvider.notifier).markAllRead();
        }
      });
    }
    // Announcements → local read-ids set, only once their stream has loaded.
    if (!_markedAnnouncementsRead &&
        ref.read(announcementsProvider).hasValue) {
      _markedAnnouncementsRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(announcementsReadProvider.notifier)
              .markAllRead(announcements.map((a) => a.id));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // USER-audience announcements only — employee broadcasts never appear here.
    final announcements = ref.watch(userAnnouncementsProvider);
    final notifsAsync = ref.watch(notificationsProvider);
    final notifs = notifsAsync.valueOrNull ?? const <NotificationModel>[];

    if (notifsAsync.isLoading && announcements.isEmpty && notifs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Everything on screen counts as seen — mark it all read once per open.
    _markAllReadOnce(announcements);

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

/// Direct deep-link for a tapped notification — the SAME contract as a push
/// notification tap (there is NO intermediate details page): the stored
/// `data.route` wins, with a type-based fallback for legacy documents that
/// were written without one.
void _openNotificationTarget(
    BuildContext context, WidgetRef ref, NotificationModel n) {
  var route = n.route;
  if (route.isEmpty) {
    route = switch (n.type) {
      'interest_received' => '/interests?tab=received',
      'interest_accepted' => '/interests?tab=accepted',
      'interest_rejected' => '/interests?tab=rejected',
      'porutham_ready' => '/reports',
      'chat_message' => n.targetId.isNotEmpty ? '/chat/${n.targetId}' : '/chats',
      'new_match' =>
        n.targetId.isNotEmpty ? '/profile/${n.targetId}' : '/home',
      'announcement' =>
        n.targetId.isNotEmpty ? '/announcement/${n.targetId}' : '',
      'appointment' => '/my-appointments',
      'report_assigned' => '/astrologer-dashboard',
      // The member's profile went live — Home is where they see themselves
      // back in the flow. (Free-text admin notices have no destination.)
      'profile_approval' => '/home',
      _ => '',
    };
  }
  if (route.isEmpty) return;
  // Reports links (incl. legacy '/my-analysis') open the bottom-nav Reports
  // tab — the standalone "My Reports" page no longer exists.
  if (isReportsRoute(route)) {
    goToReportsTab(context, ref);
    return;
  }
  context.push(route);
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
        // Opening the announcement marks it read — the Announcement screen is
        // the direct destination (no details page).
        ref.read(announcementsReadProvider.notifier).markRead(a.id);
        context.push('/announcement/${a.id}');
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
      case 'chat_message':
        return Colors.teal;
      case 'new_match':
        return Colors.purple;
      case 'announcement':
        return AppColors.gold;
      case 'app_update':
        return Colors.indigo;
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
      case 'chat_message':
        return Icons.chat_bubble_outline;
      case 'new_match':
        return Icons.person_add_alt_1;
      case 'announcement':
        return Icons.campaign;
      case 'app_update':
        return Icons.system_update;
      default:
        return Icons.notifications;
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
        // Opening the notification marks it read once and for all, then
        // navigates DIRECTLY to its target (same contract as a push tap).
        if (unread) {
          ref.read(notificationNotifierProvider.notifier).markRead(n.id);
        }
        _openNotificationTarget(context, ref, n);
      },
    );
  }
}
