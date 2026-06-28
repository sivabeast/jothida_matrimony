import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/chat_model.dart';
import '../../providers/chat_provider.dart';

/// All conversations of the signed-in user, updated in realtime. The standalone
/// route (`/chats`) wraps [ChatListView] in a Scaffold; the Chats bottom-nav tab
/// embeds [ChatListView] directly (the Home shell already provides the AppBar).
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: const ChatListView(),
    );
  }
}

/// The conversations list body (no Scaffold) — every accepted conversation with
/// photo, name, last message and time. Shared by the route and the Chats tab.
class ChatListView extends ConsumerWidget {
  const ChatListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(myChatThreadsProvider);
    final myUid = ref.watch(myUidProvider) ?? '';

    return Container(
      color: AppColors.scaffoldBg,
      child: threadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Never surface the raw Firebase error (e.g. a missing-index
        // failed-precondition) to users — log it and show a friendly state
        // with a retry instead.
        error: (e, _) {
          debugPrint('[ChatListScreen] threads error: $e');
          return _ChatsPlaceholder(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn\'t load your chats',
            subtitle: 'Please check your connection and try again.',
            onRetry: () => ref.invalidate(myChatThreadsProvider),
          );
        },
        data: (allThreads) {
          // Hide threads with no messages yet — e.g. a match-analysis booking's
          // thread that was pre-created so the astrologer can post the
          // acceptance message into it. Such a thread stays hidden until that
          // first message arrives (so a still-Pending booking never surfaces a
          // chat here).
          final threads = allThreads
              .where((t) => t.lastMessage.trim().isNotEmpty)
              .toList();
          if (threads.isEmpty) {
            return const _ChatsPlaceholder(
              icon: Icons.chat_bubble_outline,
              title: 'No conversations yet',
              subtitle: 'Send or receive an interest to start chatting.',
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

/// Friendly, reusable placeholder for the Chats list — used for both the empty
/// state and any load error, so a raw Firestore error is never shown to users.
class _ChatsPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  const _ChatsPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
