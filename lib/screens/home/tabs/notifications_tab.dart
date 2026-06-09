import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/notification_model.dart';
import '../../../providers/notification_provider.dart';

class NotificationsTab extends ConsumerWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsProvider);
    return notifsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (notifs) {
        if (notifs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none, size: 72, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text('No notifications', style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView.separated(
          itemCount: notifs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final n = notifs[i];
            return ListTile(
              tileColor: n.isRead ? null : AppColors.primary.withOpacity(0.04),
              leading: CircleAvatar(
                backgroundColor: _typeColor(n.type).withOpacity(0.15),
                child: Icon(_typeIcon(n.type), color: _typeColor(n.type), size: 22),
              ),
              title: Text(n.title,
                  style: TextStyle(
                      fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold)),
              subtitle: Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text(
                _timeAgo(n.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              onTap: () {
                if (!n.isRead) {
                  ref.read(notificationNotifierProvider.notifier).markRead(n.id);
                }
              },
            );
          },
        );
      },
    );
  }

  Color _typeColor(String type) {
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

  IconData _typeIcon(String type) {
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
