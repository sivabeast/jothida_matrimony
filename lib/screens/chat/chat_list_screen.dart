import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/chat_model.dart';
import '../../providers/chat_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/network_photo.dart';
import '../../core/utils/l10n_ext.dart';

/// All conversations of the signed-in user, updated in realtime. Reached from
/// the Home header Chat icon via the `/chats` route, which wraps [ChatListView]
/// in a Scaffold. (Chat is no longer a bottom-nav tab — it moved to the header.)
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.chatsTitle),
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
    // Stamp MY delivery receipt for any newly arrived incoming messages while
    // the Chats list is open (see ChatController.markDelivered).
    ref.listen(myChatThreadsProvider, (_, next) {
      final threads = next.valueOrNull;
      if (threads != null && threads.isNotEmpty) {
        ref.read(chatControllerProvider).markDelivered(threads);
      }
    });

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
        data: (threads) {
          // Every thread this member is a participant of, and nothing else.
          //
          // This list used to be filtered again by "is there an accepted
          // interest with the other party?", derived from the two interest
          // streams. That was the bug behind "we accepted but chat does not
          // work": those streams read `valueOrNull ?? []`, so for the whole
          // time they were still loading — and permanently if either was
          // denied — the set was EMPTY and every conversation vanished from
          // the list, including the one just created by accepting.
          //
          // It was also about to become wrong on purpose: a chat with a PUBLIC
          // profile has no accepted interest at all (spec §4), so it would
          // have been filtered out forever.
          //
          // Participation IS the access rule, and it is enforced where it
          // belongs — a thread only exists because the Firestore rules let
          // somebody create it (accepted connection, or a public profile), and
          // `myChatThreadsProvider` already drops threads whose counterpart
          // deleted their account.
          if (threads.isEmpty) {
            return const _ChatsPlaceholder(
              icon: Icons.chat_bubble_outline,
              title: 'No conversations yet',
              subtitle:
                  'Chat opens once an interest is accepted — or straight away '
                  'with members who share a public profile.',
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

class _ThreadTile extends ConsumerWidget {
  final ChatThread thread;
  final String myUid;
  const _ThreadTile({required this.thread, required this.myUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = thread.otherName(myUid);
    final photo = thread.otherPhoto(myUid);
    final unread = thread.unreadFor(myUid);
    // Verified badge — resolved from the counterpart's (readable, cached)
    // profile. Reads the SAME admin profile-verification status as the tick
    // beside a member's name. No extra network cost when Firestore serves it
    // from local cache.
    final otherId = thread.otherId(myUid);
    final verified = otherId.isEmpty
        ? false
        : (ref
                .watch(profileByUserIdProvider(otherId))
                .valueOrNull
                ?.isProfileVerified ??
            false);

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
          backgroundImage: cachedPhotoProvider(photo),
          child: photo.isEmpty
              ? Text(name.isNotEmpty ? name[0] : '?',
                  style: const TextStyle(color: AppColors.primary))
              : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (verified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, size: 15, color: AppColors.success),
            ],
          ],
        ),
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
                label: Text(context.l10n.tryAgain),
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
