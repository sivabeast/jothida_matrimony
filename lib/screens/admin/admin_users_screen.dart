import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/data_states.dart';

/// Admin → User Management. Loads every user from Firestore and shows
/// Name, Email, Gender, Status and Registration Date with graceful
/// loading / empty / error states.
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(allUsersProvider);

    return usersAsync.when(
      loading: () => const LoadingState(message: 'Loading users...'),
      error: (e, st) {
        debugPrint('[AdminUsers] ❌ load failed: $e');
        return ErrorStateView(
          message: 'Unable to load users. Please try again.',
          onRetry: () => ref.invalidate(allUsersProvider),
        );
      },
      data: (users) {
        debugPrint('[AdminUsers] loaded ${users.length} users');
        if (users.isEmpty) {
          return const EmptyState(
              icon: Icons.people_outline, message: 'No users found');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _UserTile(user: users[i]),
        );
      },
    );
  }
}

class _UserTile extends ConsumerWidget {
  final UserModel user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email ?? user.uid);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: _roleColor(user.role).withOpacity(0.15),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: _roleColor(user.role), fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    _statusChip(),
                  ],
                ),
                const SizedBox(height: 4),
                _line(Icons.email_outlined, user.email ?? '—'),
                _line(Icons.wc_outlined,
                    (user.gender?.trim().isNotEmpty ?? false) ? user.gender! : '—'),
                _line(Icons.event_outlined, 'Joined ${_fmtDate(user.createdAt)}'),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (action) async {
              if (action == 'block') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(user.isBlocked ? 'Unblock User' : 'Block User'),
                    content: Text(user.isBlocked
                        ? 'Allow this user to access the app again?'
                        : 'Are you sure you want to block this user?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white),
                        child: Text(user.isBlocked ? 'Unblock' : 'Block'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref
                      .read(adminActionsProvider.notifier)
                      .blockUser(user.uid);
                  ref.invalidate(allUsersProvider);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'block',
                  child: Text(user.isBlocked ? 'Unblock User' : 'Block User')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip() {
    final blocked = user.isBlocked;
    final label = blocked ? 'BLOCKED' : user.role.toUpperCase();
    final color = blocked ? AppColors.error : _roleColor(user.role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9.5, fontWeight: FontWeight.bold)),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          children: [
            Icon(icon, size: 13, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ),
          ],
        ),
      );

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
      case 'super_admin':
        return AppColors.primary;
      case 'astrologer':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}
