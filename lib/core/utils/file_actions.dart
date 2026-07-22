import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:printing/printing.dart';
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

/// Downloads a remote file's raw bytes (throws on a non-200 response).
Future<Uint8List> fetchRemoteBytes(String url) async {
  final res =
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) {
    throw Exception('Download failed (HTTP ${res.statusCode})');
  }
  return res.bodyBytes;
}

/// Opens [url] in the IN-APP PDF viewer — no external PDF app required, so
/// "Could not open this file" can never happen for viewing.
void openPdfInApp(BuildContext context, String url, {String title = 'PDF'}) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => RemotePdfViewerScreen(url: url, title: title),
  ));
}

/// Downloads a PDF and hands it to the system save/share sheet — the reliable
/// "Download" path on every Android version (user picks Files / Drive / etc.).
/// Returns true on success.
Future<bool> downloadRemotePdf(
  BuildContext context,
  String url, {
  String? fileName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await fetchRemoteBytes(url);
    final name = fileName ??
        'jothida_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await Printing.sharePdf(
        bytes: bytes, filename: name.endsWith('.pdf') ? name : '$name.pdf');
    return true;
  } catch (e) {
    debugPrint('downloadRemotePdf failed: $e');
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not download this file.')));
    return false;
  }
}

/// Downloads every image in [urls] and opens ONE share/save sheet with all of
/// them. Returns true when at least one image was downloaded.
Future<bool> downloadRemoteImages(
    BuildContext context, List<String> urls) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = await getTemporaryDirectory();
    final files = <XFile>[];
    for (var i = 0; i < urls.length; i++) {
      final bytes = await fetchRemoteBytes(urls[i]);
      final file = File(
          '${dir.path}/${_safeName(urls[i], pdf: false, index: i)}');
      await file.writeAsBytes(bytes);
      files.add(XFile(file.path));
    }
    if (files.isEmpty) return false;
    await Share.shareXFiles(files);
    return true;
  } catch (e) {
    debugPrint('downloadRemoteImages failed: $e');
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not download the images.')));
    return false;
  }
}

/// Shares locally generated PDF [bytes] through the system save/share sheet.
Future<void> sharePdfBytes(Uint8List bytes, {required String fileName}) =>
    Printing.sharePdf(
        bytes: bytes,
        filename: fileName.endsWith('.pdf') ? fileName : '$fileName.pdf');

/// Full-screen IN-APP viewer for a remote PDF. Renders the document with the
/// `printing` package's [PdfPreview] (rasterised natively), so no external
/// viewer app is needed. Includes built-in share/print actions.
class RemotePdfViewerScreen extends StatelessWidget {
  final String url;
  final String title;
  const RemotePdfViewerScreen(
      {super.key, required this.url, this.title = 'PDF'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Uint8List>(
        future: fetchRemoteBytes(url),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined,
                        size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('Could not load this PDF. Please try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[700])),
                  ],
                ),
              ),
            );
          }
          final bytes = snap.data!;
          return PdfPreview(
            build: (_) => bytes,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: true,
            allowSharing: true,
            pdfFileName:
                'jothida_${DateTime.now().millisecondsSinceEpoch}.pdf',
            loadingWidget: const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          );
        },
      ),
    );
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

/// Full-screen, zoomable preview of a LOCAL image file — used to check a
/// horoscope image that has been picked but not uploaded yet.
void showLocalImagePreview(BuildContext context, File file) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(file.path.split(Platform.pathSeparator).last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
      ),
      body: PhotoView(
        imageProvider: FileImage(file),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 64),
        ),
      ),
    ),
  ));
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
