import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/chat_model.dart';
import '../../providers/chat_provider.dart';

/// All conversations of the signed-in user, updated in realtime.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(myChatThreadsProvider);
    final myUid = ref.watch(myUidProvider) ?? '';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: threadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load chats: $e')),
        data: (threads) {
          if (threads.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  const Text('No conversations yet'),
                  const SizedBox(height: 4),
                  Text('Start a chat from any profile card',
                      style:
                          TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: threads.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ThreadTile(thread: threads[i], myUid: myUid),
          );
        },
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final ChatThread thread;
  final String myUid;
  const _ThreadTile({required this.thread, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final name = thread.otherName(myUid);
    final photo = thread.otherPhoto(myUid);
    final unread = thread.unreadFor(myUid);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: () => context.push('/chat/${thread.id}', extra: {
          'name': name,
          'photo': photo,
        }),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.primary.withOpacity(0.1),
          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
          child: photo.isEmpty
              ? Text(name.isNotEmpty ? name[0] : '?',
                  style: const TextStyle(color: AppColors.primary))
              : null,
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          thread.lastMessage.isEmpty ? 'Say hello!' : thread.lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (thread.lastMessageAt != null)
              Text(_when(thread.lastMessageAt!),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            if (unread > 0) ...[
              const SizedBox(height: 4),
              CircleAvatar(
                radius: 10,
                backgroundColor: AppColors.primary,
                child: Text('$unread',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _when(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${t.day}/${t.month}';
  }
}
