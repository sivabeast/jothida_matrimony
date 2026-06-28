import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/astrology_service_config.dart';
import '../../../providers/astrology_config_provider.dart';
import '../../../widgets/common/network_photo.dart';

/// The Home "Astrology" bottom-nav tab — the official Astrology Service page.
///
/// EVERYTHING here is loaded LIVE from the admin-managed `astrology_service/config`
/// ([astrologyServiceConfigProvider]): the hero photo, name, address, about,
/// experience, specialization, services, certificates, awards, news & media and
/// contact details. Nothing is hardcoded. A large "Book Your Appointment" CTA
/// opens the in-person appointment booking flow.
class AstrologyServicePage extends ConsumerWidget {
  const AstrologyServicePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(astrologyServiceConfigProvider);
    return Container(
      color: AppColors.scaffoldBg,
      child: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const _Body(cfg: AstrologyServiceConfig.defaults),
        data: (cfg) => _Body(cfg: cfg),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final AstrologyServiceConfig cfg;
  const _Body({required this.cfg});

  String get _name => cfg.expertName.trim().isEmpty
      ? 'Our Astrology Expert'
      : cfg.expertName.trim();

  Future<void> _launch(BuildContext context, Uri uri, String fallback) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(SnackBar(content: Text(fallback)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(fallback)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            children: [
              _hero(),
              const SizedBox(height: 14),
              _nameAddress(),
              const SizedBox(height: 16),
              ..._sections(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
        _bottomCta(context),
      ],
    );
  }

  // ── Hero: full astrologer photo filling the card ───────────────────────────
  Widget _hero() => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetworkPhoto(
                url: cfg.expertPhotoUrl,
                fit: BoxFit.cover,
                fallbackIcon: Icons.person,
                fallbackIconSize: 96,
                showLoadingSpinner: true,
              ),
              // Subtle bottom gradient so the rounded card always feels premium
              // even with a bright photo (no text over it — name sits below).
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 90,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _nameAddress() => Column(
        children: [
          Text(
            _name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          if (cfg.officeAddress.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    cfg.officeAddress,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ],
        ],
      );

  // ── Sections (each only when it has content) ───────────────────────────────
  List<Widget> _sections(BuildContext context) {
    final out = <Widget>[];

    if (cfg.expertIntro.trim().isNotEmpty || cfg.serviceIntro.trim().isNotEmpty) {
      final about = [
        if (cfg.expertIntro.trim().isNotEmpty) cfg.expertIntro.trim(),
        if (cfg.serviceIntro.trim().isNotEmpty) cfg.serviceIntro.trim(),
      ].join('\n\n');
      out.add(_section('About', Icons.info_outline,
          Text(about, style: const TextStyle(fontSize: 13.5, height: 1.5))));
    }

    if (cfg.expertExperience.trim().isNotEmpty) {
      out.add(_section('Experience', Icons.workspace_premium_outlined,
          Text(cfg.expertExperience,
              style: const TextStyle(fontSize: 13.5, height: 1.5))));
    }

    if (cfg.expertSpecialization.trim().isNotEmpty) {
      out.add(_section('Specialization', Icons.star_outline,
          Text(cfg.expertSpecialization,
              style: const TextStyle(fontSize: 13.5, height: 1.5))));
    }

    if (cfg.services.isNotEmpty) {
      out.add(_section(
        'Services',
        Icons.auto_awesome_outlined,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in cfg.services)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 18, color: AppColors.success),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(s,
                            style:
                                const TextStyle(fontSize: 13.5, height: 1.4))),
                  ],
                ),
              ),
          ],
        ),
      ));
    }

    if (cfg.certificates.isNotEmpty) {
      out.add(_section(
        'Certificates',
        Icons.verified_outlined,
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cfg.certificates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) =>
                _CertificateCard(cert: cfg.certificates[i], onOpen: _launch),
          ),
        ),
      ));
    }

    if (cfg.awards.isNotEmpty) {
      out.add(_section(
        'Awards & Medals',
        Icons.emoji_events_outlined,
        Column(children: [for (final a in cfg.awards) _AwardTile(award: a)]),
      ));
    }

    if (cfg.news.isNotEmpty) {
      out.add(_section(
        'News & Media',
        Icons.newspaper_outlined,
        Column(children: [for (final n in cfg.news) _NewsTile(news: n)]),
      ));
    }

    final contacts = _contactRows(context);
    if (contacts.isNotEmpty) {
      out.add(_section('Contact Details', Icons.contact_phone_outlined,
          Column(children: contacts)));
    }

    return out;
  }

  List<Widget> _contactRows(BuildContext context) {
    final rows = <Widget>[];
    final phone = cfg.officeContactNumber.trim();
    final whatsapp = cfg.whatsappNumber.trim();
    final email = cfg.email.trim();
    final address = cfg.officeAddress.trim();
    final location = cfg.mapLocation.trim();

    String digits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

    if (phone.isNotEmpty) {
      rows.add(_contactRow(Icons.call_outlined, 'Phone', phone,
          () => _launch(context, Uri(scheme: 'tel', path: digits(phone)),
              'Call $phone')));
    }
    if (whatsapp.isNotEmpty) {
      final wa = digits(whatsapp).replaceAll('+', '');
      rows.add(_contactRow(Icons.chat_outlined, 'WhatsApp', whatsapp,
          () => _launch(context, Uri.parse('https://wa.me/$wa'),
              'WhatsApp: $whatsapp')));
    }
    if (email.isNotEmpty) {
      rows.add(_contactRow(Icons.email_outlined, 'Email', email,
          () => _launch(context, Uri(scheme: 'mailto', path: email),
              'Email: $email')));
    }
    if (address.isNotEmpty) {
      rows.add(_contactRow(Icons.location_on_outlined, 'Office', address, null));
    }
    if (location.isNotEmpty) {
      final uri = location.startsWith('http')
          ? Uri.parse(location)
          : Uri.parse(
              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(location)}');
      rows.add(_contactRow(Icons.map_outlined, 'Location', location,
          () => _launch(context, uri, location)));
    }
    return rows;
  }

  Widget _contactRow(
          IconData icon, String label, String value, VoidCallback? onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                    const SizedBox(height: 1),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ],
          ),
        ),
      );

  // ── Sticky CTA ──────────────────────────────────────────────────────────
  Widget _bottomCta(BuildContext context) {
    final open = cfg.bookingEnabled;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
                open ? () => context.push('/astrology-appointment') : null,
            icon: Icon(open ? Icons.event_available : Icons.event_busy,
                size: 20),
            label: Text(
              open ? 'Book Your Appointment' : 'Booking Currently Closed',
              style:
                  const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              minimumSize: const Size.fromHeight(54),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared section card shell ─────────────────────────────────────────────
  Widget _section(String title, IconData icon, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ]),
            const Divider(height: 18),
            child,
          ],
        ),
      );
}

// ── Certificate card (image thumb or PDF tile) ────────────────────────────────

class _CertificateCard extends StatelessWidget {
  final AstrologyCertificate cert;
  final Future<void> Function(BuildContext, Uri, String) onOpen;
  const _CertificateCard({required this.cert, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: cert.url.isEmpty
          ? null
          : () => onOpen(context, Uri.parse(cert.url), cert.title),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: cert.isPdf
                  ? Container(
                      width: 110,
                      height: 100,
                      color: AppColors.primary.withOpacity(0.08),
                      alignment: Alignment.center,
                      child: const Icon(Icons.picture_as_pdf,
                          color: AppColors.error, size: 40),
                    )
                  : NetworkPhoto(
                      url: cert.url,
                      width: 110,
                      height: 100,
                      fallbackIcon: Icons.verified),
            ),
            const SizedBox(height: 4),
            Text(cert.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

// ── Award tile ────────────────────────────────────────────────────────────────

class _AwardTile extends StatelessWidget {
  final AstrologyAward award;
  const _AwardTile({required this.award});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: NetworkPhoto(
                url: award.imageUrl,
                width: 56,
                height: 56,
                fallbackIcon: Icons.emoji_events),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(award.title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    if (award.year.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(award.year,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.goldDark)),
                      ),
                  ],
                ),
                if (award.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(award.description,
                      style: TextStyle(
                          fontSize: 12.5, height: 1.4, color: Colors.grey[700])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── News tile ─────────────────────────────────────────────────────────────────

class _NewsTile extends StatelessWidget {
  final AstrologyNews news;
  const _NewsTile({required this.news});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (news.imageUrl.trim().isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: NetworkPhoto(
                url: news.imageUrl,
                width: double.infinity,
                height: 150,
                fallbackIcon: Icons.newspaper,
              ),
            ),
          if (news.imageUrl.trim().isNotEmpty) const SizedBox(height: 8),
          Text(news.headline,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          if (news.source.trim().isNotEmpty || news.date.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              [news.source, news.date].where((s) => s.trim().isNotEmpty).join(' · '),
              style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600),
            ),
          ],
          if (news.description.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(news.description,
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: Colors.grey[800])),
          ],
          const Divider(height: 18),
        ],
      ),
    );
  }
}
