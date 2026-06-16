import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/astrologer_model.dart';
import '../../providers/astrologer_provider.dart';

/// Full astrologer profile (read-only, contact-only).
///
/// Identity, services offered, uploaded certificates (view-only) and direct
/// contact (Call / WhatsApp). There is no pricing, booking or payment — users
/// reach an astrologer directly.
class AstrologerProfileScreen extends ConsumerWidget {
  final String astrologerId;
  const AstrologerProfileScreen({super.key, required this.astrologerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(astrologerByIdProvider(astrologerId));
    if (a == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Astrologer not found')),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(background: _header(a)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statsRow(a),
                  if (a.about.trim().isNotEmpty)
                    _section('📝 About',
                        Text(a.about, style: const TextStyle(height: 1.4))),
                  if (a.languages.isNotEmpty)
                    _section('🌐 Languages', _chips(a.languages)),
                  if (a.serviceNames.isNotEmpty)
                    _section('🔮 Services Offered', _servicesOffered(a)),
                  if (a.certificateDocs.isNotEmpty)
                    _section('📜 Certificates', _certificates(context, a)),
                  _section('📞 Contact Details', _contactDetails(context, a)),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _header(Astrologer a) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.white,
                backgroundImage:
                    a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
                onBackgroundImageError: (_, __) {},
                child: a.photoUrl.isEmpty
                    ? const Icon(Icons.person,
                        size: 46, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(height: 10),
              Text(a.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (a.verified)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Verified Astrologer',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              if (a.location.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on,
                        size: 15, color: Colors.white70),
                    const SizedBox(width: 3),
                    Text(a.location,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  // ── Rating · Experience stats ──────────────────────────────────────────────
  Widget _statsRow(Astrologer a) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat(a.rating.toStringAsFixed(1), 'Rating', Icons.star,
                AppColors.gold),
            _stat('${a.reviewCount}', 'Reviews', Icons.reviews_outlined,
                AppColors.primary),
            _stat('${a.experienceYears} yrs', 'Experience',
                Icons.work_history_outlined, AppColors.info),
          ],
        ),
      );

  Widget _stat(String value, String label, IconData icon, Color color) =>
      Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      );

  // ── Services Offered (names only — no pricing) ─────────────────────────────
  Widget _servicesOffered(Astrologer a) => Column(
        children: a.serviceNames
            .map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ))
            .toList(),
      );

  // ── Certificates (view-only) ───────────────────────────────────────────────
  Widget _certificates(BuildContext context, Astrologer a) => Column(
        children: a.certificateDocs
            .map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: ListTile(
                    leading: Icon(c.isPdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                        color: AppColors.primary),
                    title: Text(c.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('View only',
                        style: TextStyle(fontSize: 11)),
                    trailing: const Icon(Icons.visibility_outlined,
                        color: AppColors.primary),
                    onTap: () => _viewCertificate(context, c),
                  ),
                ))
            .toList(),
      );

  void _viewCertificate(BuildContext context, AstrologerCertificate c) {
    showDialog(
      context: context,
      builder: (_) => _CertificateViewer(certificate: c),
    );
  }

  // ── Contact Details (direct contact — no booking) ──────────────────────────
  Widget _contactDetails(BuildContext context, Astrologer a) {
    final hasPhone = normalizeIndianPhone(a.phone).isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _contactLine(Icons.person_outline, 'Name',
              a.name.trim().isNotEmpty ? a.name : 'Not Available'),
          const SizedBox(height: 12),
          _contactLine(Icons.call_outlined, 'Phone',
              hasPhone ? formatIndianPhoneDisplay(a.phone) : 'Not Available'),
          const SizedBox(height: 12),
          _contactLine(Icons.chat_outlined, 'WhatsApp',
              hasPhone ? formatIndianPhoneDisplay(a.phone) : 'Not Available'),
          if (hasPhone) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _launch(phoneCallUri(a.phone)),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _launch(whatsappUri(a.phone)),
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactLine(IconData icon, String label, String value) => Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );

  Future<void> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Shared ─────────────────────────────────────────────────────────────────
  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _chips(List<String> items) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: items
            .map((e) => Chip(
                  label: Text(e),
                  backgroundColor: AppColors.primary.withOpacity(0.08),
                  side: BorderSide.none,
                ))
            .toList(),
      );
}

/// Read-only certificate viewer. Images are shown zoomable via [PhotoView];
/// there is intentionally NO download or share action. PDFs can't be rendered
/// in-app (no bundled PDF engine) and are never opened externally — that would
/// allow downloading — so they show a clear view-only notice instead.
class _CertificateViewer extends StatelessWidget {
  final AstrologerCertificate certificate;
  const _CertificateViewer({required this.certificate});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            certificate.name.isEmpty ? 'Certificate' : certificate.name,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        body: certificate.isPdf ? _pdfNotice() : _imageView(),
      ),
    );
  }

  Widget _imageView() => PhotoView(
        imageProvider: NetworkImage(certificate.url),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        loadingBuilder: (_, __) => const Center(
            child: CircularProgressIndicator(color: Colors.white)),
        errorBuilder: (_, __, ___) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 64),
              SizedBox(height: 12),
              Text('Could not load this certificate.',
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );

  Widget _pdfNotice() => const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf_outlined,
                  color: Colors.white54, size: 72),
              SizedBox(height: 16),
              Text('PDF certificate',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                'This certificate is a PDF and is available for verification '
                'in view-only mode. It cannot be downloaded or shared.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
}
