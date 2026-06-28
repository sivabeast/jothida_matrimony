import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrology_service_config.dart';
import '../../providers/astrology_config_provider.dart';

/// Horoscope Compatibility Report — service details page (spec §4–§6).
///
/// Opened from an accepted match's "📄 Get Horoscope Compatibility Report"
/// button. Presents the service as a professional horoscope compatibility
/// analysis (NO mention of any internal tools/software): introduction, what the
/// report includes, estimated delivery time and the service charge, plus a
/// "Meet Our Astrology Expert" card with Contact Expert (phone dialer) and Book
/// Your Appointment (in-person office visit). No chat button here.
class HoroscopeReportServiceScreen extends ConsumerWidget {
  /// The accepted-match user id whose horoscope is compared with the user's.
  final String otherUserId;
  const HoroscopeReportServiceScreen({super.key, required this.otherUserId});

  Future<void> _contactExpert(
      BuildContext context, AstrologyServiceConfig cfg) async {
    final number = cfg.contactPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: number);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await launchUrl(uri)) {
        messenger.showSnackBar(SnackBar(
            content: Text('Call our expert at ${cfg.contactPhone}')));
      }
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text('Call our expert at ${cfg.contactPhone}')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(astrologyServiceConfigProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Compatibility Report'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) =>
            _body(context, ref, AstrologyServiceConfig.defaults),
        data: (cfg) => _body(context, ref, cfg),
      ),
    );
  }

  Widget _body(
      BuildContext context, WidgetRef ref, AstrologyServiceConfig cfg) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _introCard(cfg),
        const SizedBox(height: 14),
        _includesCard(cfg),
        const SizedBox(height: 14),
        _metaCard(cfg),
        const SizedBox(height: 18),
        const Text('Meet Our Astrology Expert',
            style: TextStyle(
                fontSize: 16,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _expertCard(context, cfg),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _introCard(AstrologyServiceConfig cfg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.description_outlined, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text('Professional Compatibility Analysis',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Text(cfg.serviceIntro,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13.5, height: 1.5)),
          ],
        ),
      );

  Widget _includesCard(AstrologyServiceConfig cfg) => _card(
        title: 'What the report includes',
        icon: Icons.checklist_rtl_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in cfg.reportIncludes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 18, color: AppColors.success),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item,
                          style: const TextStyle(fontSize: 13.5, height: 1.4)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _metaCard(AstrologyServiceConfig cfg) => _card(
        title: 'Service Details',
        icon: Icons.info_outline,
        child: Column(
          children: [
            _metaRow(Icons.schedule_outlined, 'Estimated delivery',
                cfg.deliveryTime),
            const Divider(height: 18),
            _metaRow(Icons.payments_outlined, 'Service charge',
                '₹${cfg.serviceCharge}'),
          ],
        ),
      );

  Widget _metaRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
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
            // Value wraps instead of overflowing (long delivery text fixed §3).
            Expanded(
              flex: 5,
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _expertCard(BuildContext context, AstrologyServiceConfig cfg) =>
      Container(
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
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: cfg.expertPhotoUrl.isNotEmpty
                      ? NetworkImage(cfg.expertPhotoUrl)
                      : null,
                  child: cfg.expertPhotoUrl.isEmpty
                      ? const Icon(Icons.person,
                          color: AppColors.primary, size: 34)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cfg.expertName,
                          style: const TextStyle(
                              fontSize: 16.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      _expertLine(
                          Icons.workspace_premium_outlined,
                          cfg.expertExperience),
                      const SizedBox(height: 2),
                      _expertLine(
                          Icons.auto_awesome_outlined,
                          cfg.expertSpecialization),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(cfg.expertIntro,
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: Colors.grey[800])),
            const SizedBox(height: 16),
            // 📞 Contact Expert — phone dialer (no chat here, per spec §5).
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _contactExpert(context, cfg),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: const Text('Contact Expert'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // 📅 Book Your Appointment — in-person office visit.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    context.push('/book-appointment/$otherUserId'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Column(
                  children: const [
                    Text('📅  Book Your Appointment',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('Visit our office on your selected date and time.',
                        style: TextStyle(fontSize: 11.5, color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _expertLine(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
        ),
      ],
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
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
