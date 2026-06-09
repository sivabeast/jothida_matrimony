import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(allUsersProvider);

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (users) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: users.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _UserTile(user: users[i]),
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  final UserModel user;

  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        backgroundColor: _roleColor(user.role).withOpacity(0.15),
        child: Text(
          (user.displayName ?? user.email ?? '?')[0].toUpperCase(),
          style: TextStyle(color: _roleColor(user.role), fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(user.displayName ?? user.email ?? user.uid),
      subtitle: Text('${user.phone ?? 'No phone'} • ${user.role}'),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          if (action == 'block') {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Block User'),
                content: const Text('Are you sure you want to block this user?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Block', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await ref.read(adminActionsProvider.notifier).blockUser(user.uid);
            }
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'view', child: Text('View Profile')),
          const PopupMenuItem(value: 'block', child: Text('Block User')),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return AppColors.primary;
      case 'astrologer':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }
}
