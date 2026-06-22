import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';

/// Helpers for previewing / downloading / sharing remotely-hosted files
/// (Cloudinary URLs for horoscope images, horoscope PDFs and astrologer
/// analysis attachments). Shared by the match-analysis workspace, the user's
/// analysis page and the horoscope upload manager.

bool isPdfUrl(String url) => url.toLowerCase().contains('.pdf') ||
    url.toLowerCase().contains('/raw/upload');

String _safeName(String url, {required bool pdf, int index = 0}) {
  // Cloudinary `raw` (PDF) URLs often have no extension, which stops the OS
  // picking a viewer — so always give a sensible name + extension.
  final ext = pdf ? 'pdf' : (url.toLowerCase().contains('.png') ? 'png' : 'jpg');
  return 'jothida_${DateTime.now().millisecondsSinceEpoch}_$index.$ext';
}

Future<File?> _download(String url, String fileName) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  final res = await http.get(Uri.parse(url));
  if (res.statusCode != 200) {
    throw Exception('Download failed (HTTP ${res.statusCode})');
  }
  await file.writeAsBytes(res.bodyBytes);
  return file;
}

/// Downloads [url] to a temp file and opens it with the OS default viewer
/// (gallery / PDF reader). Shows a SnackBar on failure. Returns true on success.
Future<bool> openRemoteFile(
  BuildContext context,
  String url, {
  bool? pdf,
  int index = 0,
}) async {
  final isPdf = pdf ?? isPdfUrl(url);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await _download(url, _safeName(url, pdf: isPdf, index: index));
    if (file == null) return false;
    final result = await OpenFile.open(file.path);
    if (result.type != ResultType.done) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not open file: ${result.message}')));
      return false;
    }
    return true;
  } catch (e) {
    debugPrint('openRemoteFile failed: $e');
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not open this file.')));
    return false;
  }
}

/// Downloads [url] and opens the system share sheet (Save / WhatsApp / etc.).
Future<void> shareRemoteFile(
  BuildContext context,
  String url, {
  bool? pdf,
  int index = 0,
}) async {
  final isPdf = pdf ?? isPdfUrl(url);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await _download(url, _safeName(url, pdf: isPdf, index: index));
    if (file == null) return;
    await Share.shareXFiles([XFile(file.path)]);
  } catch (e) {
    debugPrint('shareRemoteFile failed: $e');
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not share this file.')));
  }
}

/// Opens a full-screen, swipeable, zoomable viewer for [imageUrls].
void showImageGallery(
  BuildContext context,
  List<String> imageUrls, {
  int initialIndex = 0,
}) {
  if (imageUrls.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ImageGalleryScreen(
      imageUrls: imageUrls,
      initialIndex: initialIndex,
    ),
  ));
}

class _ImageGalleryScreen extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  const _ImageGalleryScreen({required this.imageUrls, required this.initialIndex});

  @override
  State<_ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<_ImageGalleryScreen> {
  late int _index = widget.initialIndex;
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.imageUrls.length}',
            style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_outlined),
            onPressed: () =>
                shareRemoteFile(context, widget.imageUrls[_index], pdf: false),
          ),
        ],
      ),
      body: PhotoViewGallery.builder(
        pageController: _controller,
        itemCount: widget.imageUrls.length,
        onPageChanged: (i) => setState(() => _index = i),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (_, __) => const Center(
            child: CircularProgressIndicator(color: Colors.white)),
        builder: (_, i) => PhotoViewGalleryPageOptions(
          imageProvider: NetworkImage(widget.imageUrls[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 4,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}

/// A tappable tile for a single remote PDF: opens it on tap, with a download
/// (share) action. Used wherever a list of horoscope / analysis PDFs is shown.
class RemotePdfTile extends StatelessWidget {
  final String url;
  final String label;
  final int index;
  const RemotePdfTile({
    super.key,
    required this.url,
    required this.label,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined,
            color: AppColors.primary),
        title: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: const Text('Tap to open', style: TextStyle(fontSize: 11)),
        trailing: IconButton(
          tooltip: 'Download',
          icon: const Icon(Icons.download_outlined, color: AppColors.primary),
          onPressed: () => shareRemoteFile(context, url, pdf: true, index: index),
        ),
        onTap: () => openRemoteFile(context, url, pdf: true, index: index),
      ),
    );
  }
}
