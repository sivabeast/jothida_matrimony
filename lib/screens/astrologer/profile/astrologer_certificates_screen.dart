import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_certificate.dart';
import '../../../providers/astrologer_session_provider.dart';
import 'astrologer_profile_common.dart';

const _allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

/// Certificate management — upload, preview, download, replace and remove.
/// Files are stored with a `verified` flag so the Admin module can review and
/// verify them. Supported: PDF, JPG, JPEG, PNG.
class AstrologerCertificatesScreen extends ConsumerStatefulWidget {
  const AstrologerCertificatesScreen({super.key});

  @override
  ConsumerState<AstrologerCertificatesScreen> createState() =>
      _CertificatesState();
}

class _CertificatesState extends ConsumerState<AstrologerCertificatesScreen> {
  bool _busy = false;

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickAndUpload({String? replaceId}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    final path = res?.files.single.path;
    if (path == null) return;
    final ext = path.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      _snack('Unsupported file. Use PDF, JPG, JPEG or PNG.');
      return;
    }
    final name = await _askName(res!.files.single.name);
    if (name == null) return;

    setState(() => _busy = true);
    try {
      final notifier = ref.read(myAstrologerAccountProvider.notifier);
      if (replaceId != null) await notifier.removeCertificate(replaceId);
      await notifier.addCertificate(File(path), name: name, fileType: ext);
      if (mounted) {
        _snack(replaceId != null ? 'Certificate replaced' : 'Certificate uploaded');
      }
    } catch (_) {
      if (mounted) _snack('Upload failed — please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName(String defaultName) {
    final base = defaultName.contains('.')
        ? defaultName.substring(0, defaultName.lastIndexOf('.'))
        : defaultName;
    final ctl = TextEditingController(text: base);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Certificate Name'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'e.g. Jyotish Acharya Certificate'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            child: const Text('Upload'),
          ),
        ],
      ),
    ).then((v) => (v == null || v.isEmpty) ? null : v);
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) {
      _snack('No file attached to this certificate.');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Could not open the file.');
    }
  }

  Future<void> _remove(AstrologerCertificate c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Certificate'),
        content: Text('Remove “${c.name}”?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(myAstrologerAccountProvider.notifier).removeCertificate(c.id);
      if (mounted) _snack('Certificate removed');
    } catch (_) {
      if (mounted) _snack('Could not remove — please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final certificates =
        ref.watch(myAstrologerAccountProvider)?.certificates ?? const [];

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: astrologerSectionAppBar('Certificates'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _pickAndUpload(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: _busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file),
        label: Text(_busy ? 'Uploading…' : 'Upload'),
      ),
      body: certificates.isEmpty
          ? _empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: certificates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _certCard(certificates[i]),
            ),
    );
  }

  Widget _empty() => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.workspace_premium_outlined,
              size: 72, color: Colors.grey[400]),
          const SizedBox(height: 14),
          Center(
            child: Text('No certificates uploaded',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
                'Upload your qualification certificates (PDF/JPG/PNG) for admin verification.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ),
        ],
      );

  Widget _certCard(AstrologerCertificate c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(c.isPdf ? Icons.picture_as_pdf : Icons.image,
                    color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        'Uploaded ${c.uploadedAt.day}/${c.uploadedAt.month}/${c.uploadedAt.year}'
                        '  ·  ${c.fileType.toUpperCase()}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              _statusBadge(c.status),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              _action(Icons.visibility_outlined, 'Preview',
                  () => _open(c.url)),
              _action(Icons.download_outlined, 'Download',
                  () => _open(c.url)),
              _action(Icons.swap_horiz, 'Replace',
                  () => _pickAndUpload(replaceId: c.id)),
              _action(Icons.delete_outline, 'Remove', () => _remove(c),
                  color: AppColors.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    String label;
    Color color;
    switch (status) {
      case 'approved':
        label = 'Approved';
        color = AppColors.success;
        break;
      case 'rejected':
        label = 'Rejected';
        color = AppColors.error;
        break;
      default:
        label = 'Pending';
        color = AppColors.warning;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {Color color = AppColors.textSecondary}) =>
      Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}
