import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';

/// Family Group Chat — ONE group thread for the whole workspace (bride,
/// groom and both families). Supports text (incl. emoji from the keyboard),
/// images and files.
class WeddingChatPage extends StatelessWidget {
  const WeddingChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Family Chat',
      builder: (_, __, wedding, identity) =>
          _ChatBody(wedding: wedding, identity: identity),
    );
  }
}

class _ChatBody extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const _ChatBody({required this.wedding, required this.identity});

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(weddingChatProvider(widget.wedding.id));
    final messages = messagesAsync.valueOrNull ?? const <WeddingChatMessage>[];

    return Column(
      children: [
        Expanded(
          child: messagesAsync.isLoading && messages.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : messages.isEmpty
                  ? _empty()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        // reverse:true → index 0 is the NEWEST message.
                        final msg = messages[messages.length - 1 - i];
                        final prev = messages.length - 2 - i >= 0
                            ? messages[messages.length - 2 - i]
                            : null;
                        return _bubble(
                            msg, prev?.senderKey != msg.senderKey);
                      },
                    ),
        ),
        _composer(),
      ],
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 64, color: Colors.grey[350]),
            const SizedBox(height: 14),
            const Text('Family Chat',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'One group chat for the couple and both families — share '
              'messages, photos and files while planning the wedding.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  // ── Message bubble ────────────────────────────────────────────────────────

  Widget _bubble(WeddingChatMessage msg, bool showSender) {
    final mine = msg.senderKey == widget.identity.key;
    final time =
        '${msg.sentAt.hour > 12 ? msg.sentAt.hour - 12 : (msg.sentAt.hour == 0 ? 12 : msg.sentAt.hour)}'
        ':${msg.sentAt.minute.toString().padLeft(2, '0')} '
        '${msg.sentAt.hour >= 12 ? 'PM' : 'AM'}';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
            bottom: 8,
            left: mine ? 48 : 0,
            right: mine ? 0 : 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 3),
            bottomRight: Radius.circular(mine ? 3 : 14),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine && showSender)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(msg.senderName,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.goldDark)),
              ),
            _content(msg, mine),
            const SizedBox(height: 2),
            Text(time,
                style: TextStyle(
                    fontSize: 9.5,
                    color: mine ? Colors.white70 : Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _content(WeddingChatMessage msg, bool mine) {
    switch (msg.type) {
      case 'image':
        return GestureDetector(
          onTap: () => showImageGallery(context, [msg.url]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              msg.url,
              width: 190,
              height: 190,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 190,
                height: 100,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image_outlined,
                    color: Colors.grey),
              ),
            ),
          ),
        );
      case 'file':
        return InkWell(
          onTap: () => openRemoteFile(context, msg.url, pdf: true),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_outlined,
                  size: 22, color: mine ? Colors.white : AppColors.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  msg.fileName.isEmpty ? 'Attachment' : msg.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                      decorationColor:
                          mine ? Colors.white70 : AppColors.primary,
                      color: mine ? Colors.white : AppColors.primary),
                ),
              ),
            ],
          ),
        );
      default:
        return Text(msg.text,
            style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: mine ? Colors.white : Colors.black87));
    }
  }

  // ── Composer ──────────────────────────────────────────────────────────────

  Widget _composer() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        color: Colors.white,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Attach',
              icon: const Icon(Icons.add_circle_outline,
                  color: AppColors.primary, size: 26),
              onPressed: _sending ? null : _showAttachSheet,
            ),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message the families…',
                  hintStyle:
                      TextStyle(color: Colors.grey[500], fontSize: 13.5),
                  filled: true,
                  fillColor: AppColors.scaffoldBg,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sending ? null : _sendText,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send,
                          size: 20, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    await ref
        .read(weddingControllerProvider.notifier)
        .sendChatText(widget.wedding.id, text, widget.identity);
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Photo from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _sendAttachment(image: true, camera: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _sendAttachment(image: true, camera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined,
                  color: AppColors.primary),
              title: const Text('File (PDF / Document)'),
              onTap: () {
                Navigator.pop(ctx);
                _sendAttachment(image: false, camera: false);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _sendAttachment(
      {required bool image, required bool camera}) async {
    File? file;
    String fileName = '';
    if (image) {
      final x = await ImagePicker().pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 80);
      if (x != null) {
        file = File(x.path);
        fileName = x.name;
      }
    } else {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'],
      );
      final picked = res?.files.single;
      if (picked?.path != null) {
        file = File(picked!.path!);
        fileName = picked.name;
      }
    }
    if (file == null || !mounted) return;

    setState(() => _sending = true);
    try {
      await ref.read(weddingControllerProvider.notifier).sendChatAttachment(
            widget.wedding.id,
            file: file,
            isImage: image,
            fileName: fileName,
            me: widget.identity,
          );
      if (ref.read(weddingControllerProvider).hasError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not send the attachment — try again.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
