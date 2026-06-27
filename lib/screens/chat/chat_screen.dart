import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
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

  /// Image extensions we treat as inline-previewable images.
  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};

  /// Opens the attachment chooser (Camera / Gallery / PDF / Files).
  void _showAttachmentSheet() {
    if (_sending) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            _attachTile(ctx, Icons.photo_camera_outlined, 'Camera',
                const Color(0xFF2F80ED), _pickCamera),
            _attachTile(ctx, Icons.photo_library_outlined, 'Gallery / Photos',
                AppColors.success, _pickGallery),
            _attachTile(ctx, Icons.picture_as_pdf_outlined, 'PDF Document',
                AppColors.error, _pickPdf),
            _attachTile(ctx, Icons.attach_file_outlined, 'Files / Documents',
                AppColors.primary, _pickFile),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _attachTile(BuildContext sheetCtx, IconData icon, String label,
          Color color, Future<void> Function() onTap) =>
      ListTile(
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        onTap: () {
          Navigator.pop(sheetCtx);
          onTap();
        },
      );

  Future<void> _pickCamera() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 72);
      if (x != null) await _sendAttachment(File(x.path), ChatMessageType.image);
    } catch (e) {
      _attachError(e);
    }
  }

  Future<void> _pickGallery() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 72);
      if (x != null) await _sendAttachment(File(x.path), ChatMessageType.image);
    } catch (e) {
      _attachError(e);
    }
  }

  Future<void> _pickPdf() async {
    try {
      final res = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['pdf']);
      final path = res?.files.single.path;
      if (path != null) await _sendAttachment(File(path), ChatMessageType.pdf);
    } catch (e) {
      _attachError(e);
    }
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = res?.files.single.path;
      if (path == null) return;
      await _sendAttachment(File(path), _typeForPath(path));
    } catch (e) {
      _attachError(e);
    }
  }

  /// Maps an arbitrary picked file to the right message type by extension.
  ChatMessageType _typeForPath(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    if (_imageExts.contains(ext)) return ChatMessageType.image;
    if (ext == 'pdf') return ChatMessageType.pdf;
    return ChatMessageType.file;
  }

  /// Uploads [file] and sends it as an attachment, showing the composer's
  /// in-progress state and a graceful error on failure.
  Future<void> _sendAttachment(File file, ChatMessageType type) async {
    if (_sending) return;
    setState(() => _sending = true);
    final name = file.path.split(RegExp(r'[\\/]')).last;
    try {
      await ref
          .read(chatControllerProvider)
          .sendAttachment(widget.threadId, file, type, fileName: name);
    } catch (e) {
      debugPrint('[ChatScreen] attachment send failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Attachment couldn\'t be sent. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _attachError(Object e) {
    debugPrint('[ChatScreen] pick failed: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not pick that file. Please try again.')));
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
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    // Messages are newest-first; the next index is the
                    // chronologically OLDER message. A date separator is shown
                    // above the oldest message of each day (WhatsApp-style §14).
                    final older =
                        i + 1 < messages.length ? messages[i + 1] : null;
                    final showHeader = older == null ||
                        !_sameDay(older.sentAt, msg.sentAt);
                    return Column(
                      children: [
                        if (showHeader) _DateSeparator(date: msg.sentAt),
                        _Bubble(message: msg, isMine: msg.senderId == myUid),
                      ],
                    );
                  },
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
              padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
              color: Colors.white,
              child: Row(
                children: [
                  // "+" attachment button — Camera / Gallery / PDF / Files.
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    color: AppColors.primary,
                    tooltip: 'Attach',
                    onPressed: _sending ? null : _showAttachmentSheet,
                  ),
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

/// True when [a] and [b] fall on the same calendar day.
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// A centered "Today / Yesterday / 12 Jun 2026" pill between message groups.
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('d MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(_label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
        ),
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
    final isImage = message.isImage && message.attachmentUrl.isNotEmpty;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        // Images get tight padding so the preview is prominent; text / cards
        // keep the roomier bubble padding.
        padding: isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            _content(context),
            SizedBox(height: isImage ? 4 : 2),
            Padding(
              padding: isImage
                  ? const EdgeInsets.only(right: 6, bottom: 2)
                  : EdgeInsets.zero,
              child: Text(
                // 12-hour AM/PM time for every message (spec §14).
                DateFormat('h:mm a').format(message.sentAt),
                style: TextStyle(
                    fontSize: 10,
                    color: isMine && !isImage
                        ? Colors.white70
                        : Colors.grey[500]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (message.type) {
      case ChatMessageType.image:
        return _imageContent(context);
      case ChatMessageType.pdf:
      case ChatMessageType.file:
        return _fileContent(context);
      case ChatMessageType.text:
        return Text(
          message.text,
          style: TextStyle(
              color: isMine ? Colors.white : AppColors.textPrimary,
              fontSize: 14.5,
              height: 1.3),
        );
    }
  }

  Widget _imageContent(BuildContext context) {
    if (message.attachmentUrl.isEmpty) {
      return Text(message.text,
          style: TextStyle(color: isMine ? Colors.white : AppColors.textPrimary));
    }
    return GestureDetector(
      onTap: () => showImageGallery(context, [message.attachmentUrl]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240, minWidth: 140),
          child: Image.network(
            message.attachmentUrl,
            fit: BoxFit.cover,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return Container(
                height: 160,
                width: 200,
                color: Colors.grey[200],
                alignment: Alignment.center,
                child: const CircularProgressIndicator(strokeWidth: 2),
              );
            },
            errorBuilder: (ctx, _, __) => Container(
              height: 120,
              width: 200,
              color: Colors.grey[200],
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined,
                  color: Colors.grey, size: 32),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileContent(BuildContext context) {
    final isPdf = message.type == ChatMessageType.pdf;
    final onTint = isMine ? Colors.white : AppColors.primary;
    final subTint = isMine ? Colors.white70 : Colors.grey[600];
    final name = message.fileName.isNotEmpty
        ? message.fileName
        : (isPdf ? 'Document.pdf' : 'Attachment');
    return GestureDetector(
      onTap: () => openRemoteFile(context, message.attachmentUrl, pdf: isPdf),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isMine ? Colors.white : AppColors.primary)
                  .withOpacity(isMine ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file_outlined,
                color: onTint,
                size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isMine ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5)),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download_outlined, size: 13, color: subTint),
                    const SizedBox(width: 3),
                    Text('Tap to open',
                        style: TextStyle(fontSize: 11.5, color: subTint)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
