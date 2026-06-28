import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/astrology_service_config.dart';
import '../../../providers/astrology_config_provider.dart';
import '../../../widgets/common/network_photo.dart';

/// The Home "Astrology" bottom-nav tab — a professional Astrology Service page.
///
/// Everything shown here is loaded LIVE from the admin-managed
/// `astrology_service/config` ([astrologyServiceConfigProvider]) — astrologer
/// photo, name, address, description, services offered and professional
/// details. There is no hardcoded astrology data. A prominent "Book Your
/// Appointment" CTA opens the in-person appointment booking flow.
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
        // Defaults keep the page fully functional even before any admin edit.
        error: (_, __) => _Body(cfg: AstrologyServiceConfig.defaults),
        data: (cfg) => _Body(cfg: cfg),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final AstrologyServiceConfig cfg;
  const _Body({required this.cfg});

  String get _name =>
      cfg.expertName.trim().isEmpty ? 'Our Astrology Expert' : cfg.expertName.trim();

  Future<void> _call(BuildContext context) async {
    final number = cfg.contactPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await launchUrl(Uri(scheme: 'tel', path: number))) {
        messenger.showSnackBar(
            SnackBar(content: Text('Call us at ${cfg.contactPhone}')));
      }
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text('Call us at ${cfg.contactPhone}')));
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
              _heroCard(context),
              const SizedBox(height: 14),
              if (cfg.officeAddress.trim().isNotEmpty) ...[
                _locationCard(),
                const SizedBox(height: 14),
              ],
              _aboutCard(),
              const SizedBox(height: 14),
              _servicesCard(),
              const SizedBox(height: 14),
              _professionalCard(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
        _bottomCta(context),
      ],
    );
  }

  // ── Hero header ─────────────────────────────────────────────────────────
  Widget _heroCard(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            // Photo with a gold ring.
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.gold),
              child: ClipOval(
                child: NetworkPhoto(
                  url: cfg.expertPhotoUrl,
                  width: 96,
                  height: 96,
                  showLoadingSpinner: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
              ),
            ),
            if (cfg.expertSpecialization.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                cfg.expertSpecialization,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.gold, fontSize: 13),
              ),
            ],
            if (cfg.expertExperience.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium,
                        size: 16, color: AppColors.gold),
                    const SizedBox(width: 6),
                    Text(
                      cfg.expertExperience,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _locationCard() => _card(
        icon: Icons.location_on_outlined,
        title: 'Address / Location',
        child: Text(
          cfg.officeAddress,
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
      );

  Widget _aboutCard() {
    final about = [
      if (cfg.expertIntro.trim().isNotEmpty) cfg.expertIntro.trim(),
      if (cfg.serviceIntro.trim().isNotEmpty) cfg.serviceIntro.trim(),
    ].join('\n\n');
    return _card(
      icon: Icons.info_outline,
      title: 'About',
      child: Text(
        about.isEmpty ? 'A trusted astrology service.' : about,
        style: const TextStyle(fontSize: 13.5, height: 1.5),
      ),
    );
  }

  Widget _servicesCard() => _card(
        icon: Icons.auto_awesome_outlined,
        title: 'Services Offered',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cfg.services.isEmpty)
              const Text('Services will be listed soon.',
                  style: TextStyle(fontSize: 13.5, color: Colors.grey))
            else
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
                            style: const TextStyle(
                                fontSize: 13.5, height: 1.4)),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );

  Widget _professionalCard(BuildContext context) => _card(
        icon: Icons.badge_outlined,
        title: 'Professional Details',
        child: Column(
          children: [
            if (cfg.expertExperience.trim().isNotEmpty)
              _infoRow(Icons.workspace_premium_outlined, 'Experience',
                  cfg.expertExperience),
            if (cfg.expertSpecialization.trim().isNotEmpty)
              _infoRow(Icons.star_outline, 'Specialization',
                  cfg.expertSpecialization),
            if (cfg.contactPhone.trim().isNotEmpty)
              _infoRow(Icons.call_outlined, 'Contact', cfg.contactPhone),
            if (cfg.deliveryTime.trim().isNotEmpty)
              _infoRow(Icons.schedule_outlined, 'Report delivery',
                  cfg.deliveryTime),
            if (cfg.contactPhone.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _call(context),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ],
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
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared card shell ─────────────────────────────────────────────────────
  Widget _card({
    required IconData icon,
    required String title,
    required Widget child,
  }) =>
      Container(
        width: double.infinity,
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
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ],
            ),
            const Divider(height: 18),
            child,
          ],
        ),
      );
}
