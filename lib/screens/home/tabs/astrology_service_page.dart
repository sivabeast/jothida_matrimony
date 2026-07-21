import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/appointment_status.dart';
import '../../../core/utils/file_actions.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/slot_generator.dart';
import '../../../models/astrology_service_config.dart';
import '../../../providers/appointment_provider.dart';
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
              const _AppointmentStatusCard(),
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
      out.add(_section(context.l10n.about, Icons.info_outline,
          Text(about, style: const TextStyle(fontSize: 13.5, height: 1.5))));
    }

    if (cfg.expertExperience.trim().isNotEmpty) {
      out.add(_section(context.l10n.experience, Icons.workspace_premium_outlined,
          Text(cfg.expertExperience,
              style: const TextStyle(fontSize: 13.5, height: 1.5))));
    }

    if (cfg.expertSpecialization.trim().isNotEmpty) {
      out.add(_section(context.l10n.specialization, Icons.star_outline,
          Text(cfg.expertSpecialization,
              style: const TextStyle(fontSize: 13.5, height: 1.5))));
    }

    if (cfg.services.isNotEmpty) {
      out.add(_section(
        context.l10n.servicesLabel,
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

    // Horoscope Analysis (online report) — booked from an accepted match.
    out.add(_section(
      'Horoscope Analysis (Online)',
      Icons.auto_awesome_outlined,
      const Text(
        'Get a detailed online horoscope compatibility report for you and an '
        'accepted match. Open a matched profile and tap "Get Horoscope '
        'Analysis" — your report is delivered to your Reports tab.',
        style: TextStyle(fontSize: 13.5, height: 1.5),
      ),
    ));

    // Ratings — future-ready placeholder (spec §11).
    out.add(_section(
      context.l10n.ratings,
      Icons.star_outline,
      Text(context.l10n.ratingsComingSoon,
          style: TextStyle(fontSize: 13.5, color: Colors.grey[600])),
    ));

    // Certificates — name-only chips in a horizontal scroll (no thumbnails).
    // Tapping a name opens the full certificate: image → in-app image viewer,
    // PDF → in-app PDF viewer.
    if (cfg.certificates.isNotEmpty) {
      out.add(_section(
        context.l10n.certificates,
        Icons.verified_outlined,
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: cfg.certificates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) =>
                _CertificateChip(cert: cfg.certificates[i]),
          ),
        ),
      ));
    }

    if (cfg.awards.isNotEmpty) {
      out.add(_section(
        'Awards & Medals',
        Icons.emoji_events_outlined,
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: cfg.awards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _AwardCard(award: cfg.awards[i]),
          ),
        ),
      ));
    }

    if (cfg.news.isNotEmpty) {
      out.add(_section(
        'News & Media',
        Icons.newspaper_outlined,
        SizedBox(
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: cfg.news.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _NewsCard(news: cfg.news[i]),
          ),
        ),
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
              open
                  ? context.l10n.bookYourAppointment
                  : context.l10n.bookingCurrentlyClosed,
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

// ── Appointment status card (top of the Astrology page) ───────────────────────

/// Shows the signed-in user's LATEST appointment with its live status. Renders
/// nothing when the user has no appointment. Updates in real time as the admin
/// changes the status (Pending → Confirmed → Completed / Cancelled).
class _AppointmentStatusCard extends ConsumerWidget {
  const _AppointmentStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myAppointmentsProvider).valueOrNull ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final appt = list.first;
    final color = appointmentStatusColor(appt.status);
    final date = appt.visitDate == null
        ? '—'
        : DateFormat('d MMMM yyyy').format(appt.visitDate!);
    final time =
        appt.slotStartMinutes == null ? '—' : formatMinutes(appt.slotStartMinutes!);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.08), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.l10n.yourAppointment,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(appointmentStatusIcon(appt.status), size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(appointmentStatusLabel(appt.status),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          _row(Icons.event_outlined, 'Date', date),
          const SizedBox(height: 8),
          _row(Icons.schedule_outlined, 'Time', time),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(appointmentStatusMessage(appt.status),
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: Colors.grey[800])),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push('/my-appointments'),
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: Text(context.l10n.viewMyBookings),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Row(
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          ),
          Expanded(
            flex: 5,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

// ── Full-screen image viewer (tap a certificate/award/news image) ─────────────

void _showFullScreenImage(BuildContext context, String url, String title) {
  if (url.trim().isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ImageViewerScreen(url: url, title: title),
  ));
}

class _ImageViewerScreen extends StatelessWidget {
  final String url;
  final String title;
  const _ImageViewerScreen({required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: NetworkPhoto(
            url: url,
            fit: BoxFit.contain,
            fallbackIcon: Icons.broken_image_outlined,
            showLoadingSpinner: true,
          ),
        ),
      ),
    );
  }
}

// ── Certificate chip — name only, horizontal scroll (spec: no thumbnails) ────
// Tap → open the FULL certificate: image → in-app zoomable viewer, PDF →
// in-app PDF viewer.

class _CertificateChip extends StatelessWidget {
  final AstrologyCertificate cert;
  const _CertificateChip({required this.cert});

  void _open(BuildContext context) {
    if (cert.url.isEmpty) return;
    if (cert.isPdf) {
      openPdfInApp(context, cert.url, title: cert.title);
    } else {
      _showFullScreenImage(context, cert.url, cert.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withOpacity(0.06),
      borderRadius: BorderRadius.circular(23),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(23),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: AppColors.primary.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspace_premium,
                  size: 16, color: AppColors.gold),
              const SizedBox(width: 6),
              Text(
                cert.title.trim().isEmpty ? 'Certificate' : cert.title.trim(),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Award card — horizontal carousel ──────────────────────────────────────────

class _AwardCard extends StatelessWidget {
  final AstrologyAward award;
  const _AwardCard({required this.award});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: award.imageUrl.trim().isEmpty
          ? null
          : () => _showFullScreenImage(context, award.imageUrl, award.title),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                NetworkPhoto(
                    url: award.imageUrl,
                    width: double.infinity,
                    height: 110,
                    fallbackIcon: Icons.emoji_events),
                if (award.year.trim().isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(award.year,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(award.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  if (award.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(award.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: Colors.grey[700])),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── News card — horizontal carousel ───────────────────────────────────────────

class _NewsCard extends StatelessWidget {
  final AstrologyNews news;
  const _NewsCard({required this.news});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: news.imageUrl.trim().isEmpty
          ? null
          : () => _showFullScreenImage(context, news.imageUrl, news.headline),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 230,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetworkPhoto(
                url: news.imageUrl,
                width: double.infinity,
                height: 120,
                fallbackIcon: Icons.newspaper),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(news.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  if (news.source.trim().isNotEmpty ||
                      news.date.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      [news.source, news.date]
                          .where((s) => s.trim().isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (news.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(news.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: Colors.grey[800])),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
