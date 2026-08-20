import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';
import '../../widgets/common/skeletons.dart';

/// Admin → Activity Log. Live view of the immutable `admin_logs` audit trail:
/// who did what, to whom, when. Newest first.
class AdminActivityLogScreen extends ConsumerWidget {
  const AdminActivityLogScreen({super.key});

  static (IconData, Color) _visual(String action) => switch (action) {
        'profile_approved' => (Icons.verified_user, AppColors.success),
        'profile_rejected' => (Icons.cancel_outlined, AppColors.error),
        'user_suspended' => (Icons.block, AppColors.warning),
        'user_activated' => (Icons.lock_open, AppColors.success),
        'user_deleted' => (Icons.delete_forever, AppColors.error),
        'profile_created' => (Icons.person_add_alt_1, AppColors.info),
        'credentials_shared' => (Icons.key, AppColors.gold),
        'announcement_sent' => (Icons.campaign, AppColors.primary),
        'password_reset' => (Icons.lock_reset, AppColors.warning),
        _ => (Icons.history, AppColors.textSecondary),
      };

  static String _label(String action) => switch (action) {
        'profile_approved' => 'Profile Verified',
        'profile_rejected' => 'Profile Rejected',
        'user_suspended' => 'User Suspended',
        'user_activated' => 'User Activated',
        'user_deleted' => 'User Deleted',
        'profile_created' => 'Profile Created',
        'credentials_shared' => 'Credentials Shared',
        'announcement_sent' => 'Announcement Sent',
        'password_reset' => 'Password Reset',
        _ => action.isEmpty ? 'Action' : action,
      };

  String _fmt(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day} ${months[d.month - 1]} ${d.year} · '
        '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(adminLogsProvider);
    final logs = logsAsync.valueOrNull ?? const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Activity Log'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: logsAsync.isLoading && logs.isEmpty
          ? const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SkeletonList(items: 8, showAvatar: true),
            )
          : logsAsync.hasError && logs.isEmpty
              ? ErrorStateView(
                  message: 'Unable to load the activity log. Please try again.',
                  onRetry: () => ref.invalidate(adminLogsProvider),
                )
              : logs.isEmpty
                  ? const EmptyState(
                      icon: Icons.history,
                      message: 'No admin activity recorded yet',
                      subtitle:
                          'Verifications, rejections and other admin actions '
                          'will be logged here automatically.',
                    )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final log = logs[i];
                    final action = (log['action'] ?? '').toString();
                    final details = (log['details'] ?? '').toString();
                    final targetUid = (log['targetUid'] ?? '').toString();
                    final (icon, color) = _visual(action);
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Icon(icon, color: color, size: 19),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_label(action),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                if (targetUid.isNotEmpty)
                                  Text('User: $targetUid',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey[600])),
                                if (details.isNotEmpty)
                                  Text(details,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700])),
                                const SizedBox(height: 3),
                                Text(_fmt(log['createdAt']),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500])),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
