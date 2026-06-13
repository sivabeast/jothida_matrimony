import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/chat_model.dart';
import '../../../providers/chat_provider.dart';
import 'astrologer_common.dart';

/// The astrologer's conversations. Reuses the shared, Firestore-backed chat
/// providers (the same ones the user side uses) filtered to threads that
/// include the signed-in astrologer — no user chat code is modified.
class AstrologerMessagesTab extends ConsumerWidget {
  const AstrologerMessagesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(myChatThreadsProvider);
    final myUid = ref.watch(myUidProvider) ?? '';

    return threadsAsync.when(
      loading: () => const AstrologerLoading(),
      error: (_, __) => AstrologerErrorState(
        onRetry: () => ref.invalidate(myChatThreadsProvider),
      ),
      data: (threads) {
        if (threads.isEmpty) {
          return const AstrologerEmptyState(
            icon: Icons.chat_bubble_outline,
            message: 'No messages yet',
            hint: 'Conversations with users will appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: threads.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _ThreadTile(thread: threads[i], myUid: myUid),
        );
      },
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

    return AstrologerCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/chat/${thread.id}', extra: {
        'name': name,
        'photo': photo,
      }),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.primary.withOpacity(0.1),
          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
          child: photo.isEmpty
              ? Text(name.isNotEmpty ? name[0] : '?',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold))
              : null,
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
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
              Text(astrologerRelativeTime(thread.lastMessageAt!),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            if (unread > 0) ...[
              const SizedBox(height: 6),
              CircleAvatar(
                radius: 10,
                backgroundColor: AppColors.primary,
                child: Text('$unread',
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
