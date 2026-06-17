import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/astrologer_model.dart';
import '../../models/astrologer_review_model.dart';
import '../../providers/astrologer_provider.dart';
import '../../providers/astrologer_review_provider.dart';

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
                  _section('⭐ Ratings & Reviews',
                      _ratingsAndReviews(context, ref, a)),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ratings & reviews ──────────────────────────────────────────────────────
  Widget _ratingsAndReviews(BuildContext context, WidgetRef ref, Astrologer a) {
    final canRate = ref.watch(canRateAstrologerProvider);
    final myReview = ref.watch(myAstrologerReviewProvider(a.id)).valueOrNull;
    final reviewsAsync = ref.watch(astrologerReviewsProvider(a.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Rate / Edit action — premium users only; hidden for everyone else.
        if (canRate)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openRatingForm(context, ref, a, myReview),
              icon: Icon(myReview == null ? Icons.star_outline : Icons.edit,
                  size: 18),
              label: Text(
                  myReview == null ? 'Rate Astrologer' : 'Edit Your Rating'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Complete your profile to rate astrologers.',
                      style: TextStyle(
                          color: Colors.grey[800], fontSize: 12.5)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        // Reviews list.
        reviewsAsync.when(
          loading: () => const Center(
              child: Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )),
          error: (_, __) => Text('Could not load reviews.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          data: (reviews) {
            if (reviews.isEmpty) {
              return Text('No reviews yet. Be the first to rate.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13));
            }
            return Column(
              children: reviews.map(_reviewCard).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _reviewCard(AstrologerReviewModel r) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    r.userName.isNotEmpty ? r.userName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                        color: AppColors.primary, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                _starRow(r.rating, size: 14),
              ],
            ),
            if (r.review.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(r.review,
                  style: TextStyle(fontSize: 13, color: Colors.grey[800])),
            ],
            const SizedBox(height: 6),
            Text(_fmtDate(r.updatedAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      );

  static Widget _starRow(int rating, {double size = 16}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Icon(i < rating ? Icons.star : Icons.star_border,
              size: size, color: AppColors.gold),
        ),
      );

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (d.millisecondsSinceEpoch == 0) return '';
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  void _openRatingForm(BuildContext context, WidgetRef ref, Astrologer a,
      AstrologerReviewModel? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RatingFormSheet(astrologer: a, existing: existing),
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
              // ⭐ 4.8 (126 Reviews)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: AppColors.gold, size: 18),
                  const SizedBox(width: 4),
                  Text(a.rating.toStringAsFixed(1),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text(
                      '(${a.reviewCount} ${a.reviewCount == 1 ? 'Review' : 'Reviews'})',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ],
              ),
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

/// Bottom-sheet form to create or edit a rating (1–5 stars) + optional review.
class _RatingFormSheet extends ConsumerStatefulWidget {
  final Astrologer astrologer;
  final AstrologerReviewModel? existing;
  const _RatingFormSheet({required this.astrologer, this.existing});

  @override
  ConsumerState<_RatingFormSheet> createState() => _RatingFormSheetState();
}

class _RatingFormSheetState extends ConsumerState<_RatingFormSheet> {
  late int _rating = widget.existing?.rating ?? 0;
  late final TextEditingController _review =
      TextEditingController(text: widget.existing?.review ?? '');
  bool _submitting = false;

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a star rating')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(astrologerReviewControllerProvider.notifier).submit(
            astrologerId: widget.astrologer.id,
            rating: _rating,
            review: _review.text,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.existing == null
              ? 'Thank you! Your rating has been submitted.'
              : 'Your rating has been updated.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not submit your rating. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.existing == null
                  ? 'Rate ${widget.astrologer.name}'
                  : 'Edit your rating',
              style: const TextStyle(
                  fontSize: 18,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Star selector.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    iconSize: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _rating = star),
                    icon: Icon(
                      star <= _rating ? Icons.star : Icons.star_border,
                      color: AppColors.gold,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Review (optional)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _review,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Share your experience…',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Submit Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
