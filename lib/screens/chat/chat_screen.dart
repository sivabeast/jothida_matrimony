import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/chat_model.dart';
import '../../providers/astrologer_provider.dart';
import '../../providers/chat_provider.dart';

/// One conversation: realtime message stream + composer.
class ChatScreen extends ConsumerStatefulWidget {
  final String threadId;

  /// Optional `{name, photo}` of the other participant (passed when opening
  /// from a profile card so the header renders instantly).
  final Map<String, dynamic>? extra;

  const ChatScreen({super.key, required this.threadId, this.extra});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(chatControllerProvider).markRead(widget.threadId));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final sent = await _sendText(text);
    if (sent) _controller.clear();
  }

  /// Sends [text] as a normal chat message. Used both by the composer's Send
  /// button and the user's quick-reply buttons (which send instantly, with no
  /// confirmation dialog). Returns true on success.
  Future<bool> _sendText(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _sending) return false;
    setState(() => _sending = true);
    try {
      await ref.read(chatControllerProvider).sendMessage(widget.threadId, msg);
      return true;
    } catch (e) {
      debugPrint('[ChatScreen] send failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message couldn\'t be sent. Please try again.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _quickReplyChip(String text) => OutlinedButton(
        onPressed: _sending ? null : () => _sendText(text),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          backgroundColor: AppColors.primary.withOpacity(0.04),
          side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(text),
      );

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(myUidProvider) ?? '';
    final threadAsync = ref.watch(chatThreadProvider(widget.threadId));
    final messagesAsync = ref.watch(chatMessagesProvider(widget.threadId));

    final thread = threadAsync.valueOrNull;
    final name =
        thread?.otherName(myUid) ?? widget.extra?['name'] as String? ?? 'Chat';
    final photo =
        thread?.otherPhoto(myUid) ?? widget.extra?['photo'] as String? ?? '';

    // The user's two quick-reply buttons appear ONLY when the other participant
    // is an astrologer. That single condition also guarantees the ASTROLOGER
    // never sees them (their counterpart is a user, not an astrologer) and that
    // ordinary user↔user matrimony chats don't show them either. The `extra`
    // flag (set when opening from the booking card) shows them instantly; the
    // provider lookup also covers entry from the Chats list.
    final otherUid = thread?.otherId(myUid) ?? '';
    final showUserQuickReplies = widget.extra?['isAstrologer'] == true ||
        (otherUid.isNotEmpty &&
            ref.watch(astrologerByIdProvider(otherUid)) != null);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: Colors.white24,
              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
              child: photo.isEmpty
                  ? Text(name.isNotEmpty ? name[0] : '?',
                      style: const TextStyle(color: Colors.white))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) {
                debugPrint('[ChatScreen] messages error: $e');
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Messages couldn\'t be loaded right now.\nPlease try again in a moment.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                );
              },
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text('Say hello to $name 👋',
                        style: TextStyle(color: Colors.grey[500])),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  itemCount: messages.length,
                  itemBuilder: (_, i) =>
                      _Bubble(message: messages[i], isMine: messages[i].senderId == myUid),
                );
              },
            ),
          ),
          // ── User quick-reply buttons (astrologer chats only) ──
          // Tapping one sends it INSTANTLY as a normal message (no dialog); the
          // user can still type custom messages below.
          if (showUserQuickReplies)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _quickReplyChip(kQuickAskReportEta),
                    const SizedBox(width: 8),
                    _quickReplyChip(kQuickAskBookingStatus),
                  ],
                ),
              ),
            ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        filled: true,
                        fillColor: AppColors.scaffoldBg,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send,
                              color: Colors.white, size: 20),
                      onPressed: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  const _Bubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMine ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text,
              style: TextStyle(
                  color: isMine ? Colors.white : AppColors.textPrimary,
                  fontSize: 14.5,
                  height: 1.3),
            ),
            const SizedBox(height: 2),
            Text(
              '${message.sentAt.hour.toString().padLeft(2, '0')}:${message.sentAt.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 10,
                  color: isMine ? Colors.white70 : Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
