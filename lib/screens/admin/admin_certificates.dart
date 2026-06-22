import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_certificate.dart';

/// Admin certificate-review card — lists every uploaded certificate with its
/// name, upload date and verification status, plus in-app **View** (image
/// preview / open PDF) and **Download** (saves the file locally) actions.
/// Shared by the Astrologer Verification page and the admin Astrologer profile.
class CertificatesCard extends StatelessWidget {
  final List<AstrologerCertificate> certificates;
  const CertificatesCard({super.key, required this.certificates});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.workspace_premium_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Certificates',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${certificates.length}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          if (certificates.isEmpty)
            Text('No certificates uploaded.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13))
          else
            for (final c in certificates) _CertTile(cert: c),
        ],
      ),
    );
  }
}

class _CertTile extends StatefulWidget {
  final AstrologerCertificate cert;
  const _CertTile({required this.cert});

  @override
  State<_CertTile> createState() => _CertTileState();
}

class _CertTileState extends State<_CertTile> {
  bool _busy = false;

  void _snack(String m, {bool error = false}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(m),
            backgroundColor: error ? AppColors.error : null));

  @override
  Widget build(BuildContext context) {
    final c = widget.cert;
    final statusColor = c.isApproved
        ? AppColors.success
        : c.isRejected
            ? AppColors.error
            : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(c.isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
                  color: AppColors.primary, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13.5)),
                    Text('Uploaded ${_fmtDate(c.uploadedAt)}',
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(c.status.toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _view,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 8)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _download,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _view() async {
    final c = widget.cert;
    if (c.url.isEmpty) {
      _snack('No file attached to this certificate.', error: true);
      return;
    }
    if (!c.isPdf) {
      showDialog(
          context: context,
          builder: (_) => _ImagePreviewDialog(url: c.url, name: c.name));
      return;
    }
    await _fetchAndOpen(temp: true); // PDF → open in the device viewer
  }

  Future<void> _download() async {
    if (widget.cert.url.isEmpty) {
      _snack('No file attached to this certificate.', error: true);
      return;
    }
    await _fetchAndOpen(temp: false);
  }

  Future<void> _fetchAndOpen({required bool temp}) async {
    final c = widget.cert;
    setState(() => _busy = true);
    try {
      final res = await http.get(Uri.parse(c.url));
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
      Directory dir;
      if (temp) {
        dir = await getTemporaryDirectory();
      } else {
        try {
          dir = (await getDownloadsDirectory()) ??
              await getApplicationDocumentsDirectory();
        } catch (_) {
          dir = await getApplicationDocumentsDirectory();
        }
      }
      final ext = c.fileType.isNotEmpty ? c.fileType : (c.isPdf ? 'pdf' : 'jpg');
      final base = c.name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final fname = base.toLowerCase().endsWith('.$ext') ? base : '$base.$ext';
      final file = File('${dir.path}/$fname');
      await file.writeAsBytes(res.bodyBytes);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!temp) _snack('Saved to ${file.path}');
      await OpenFile.open(file.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Could not open the certificate. Please try again.', error: true);
    }
  }
}

/// Zoomable in-app preview for image certificates.
class _ImagePreviewDialog extends StatelessWidget {
  final String url;
  final String name;
  const _ImagePreviewDialog({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Icon(Icons.broken_image,
                            color: Colors.white54, size: 64),
                      )),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 12,
            right: 12,
            child: Text(name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
}
