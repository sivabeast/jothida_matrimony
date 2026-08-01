import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrology_service_config.dart';
import '../../models/profile_model.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/billing/play_billing_service.dart';

/// Online **Horoscope Analysis** — service details page (spec §1).
///
/// This is a fully ONLINE report service — NOT an appointment. Opened from an
/// accepted match's "Get Horoscope Analysis" button. It explains the report,
/// shows the charge, and the user pays via Google Play Billing (one-time
/// product `horoscope_report`) to create an analysis
/// request that is auto-assigned to an astrologer. There is intentionally no
/// "Contact Expert", "Book Appointment" or any office-visit content here.
class HoroscopeReportServiceScreen extends ConsumerStatefulWidget {
  /// The accepted-match user id whose horoscope is compared with the user's.
  final String otherUserId;
  const HoroscopeReportServiceScreen({super.key, required this.otherUserId});

  @override
  ConsumerState<HoroscopeReportServiceScreen> createState() =>
      _HoroscopeReportServiceScreenState();
}

class _HoroscopeReportServiceScreenState
    extends ConsumerState<HoroscopeReportServiceScreen> {
  /// Fallback price, shown only until Play's own price arrives (or if the store
  /// is unreachable). Play Console is the source of truth — see [_priceText].
  static const int _fee = AppConstants.horoscopeAnalysisFee; // ₹199

  bool _busy = false;

  /// Play's localized price for `horoscope_report` (e.g. "₹199.00"), loaded
  /// from the store when this screen opens. Null while the product is still
  /// resolving, on an emulator without Play, or if the product is not ACTIVE
  /// in Play Console.
  String? _storePrice;

  /// What the pay button and the Service Details row display. Prefers the real
  /// store price so changing the price in Play Console does NOT require an app
  /// update — without this the button could promise ₹199 while Play charged
  /// something else.
  String get _priceText => _storePrice ?? '₹$_fee';

  @override
  void initState() {
    super.initState();
    _loadStorePrice();
  }

  Future<void> _loadStorePrice() async {
    final billing = ref.read(playBillingServiceProvider);
    await billing.init();
    if (!mounted) return;
    setState(() =>
        _storePrice = billing.priceLabel(BillingProducts.horoscopeReport));
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Resolve both profiles, launch the Google Play Billing purchase sheet for
  /// the one-time `horoscope_report` product, and — ONLY on a successful,
  /// verified purchase — create + auto-assign the analysis (saving the purchase
  /// token to Firestore) and unlock it on the Reports tab. A cancelled or failed
  /// purchase leaves the report locked and charges nothing.
  Future<void> _payAndRequest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final me = ref.read(myProfileProvider).valueOrNull;
      final partner =
          await ref.read(profileByUserIdProvider(widget.otherUserId).future);
      if (me == null || partner == null) {
        _snack('Could not load both profiles. Please try again.');
        if (mounted) setState(() => _busy = false);
        return;
      }
      // Groom = male, Bride = female (fallback: me = A, partner = B).
      ProfileModel groom = me, bride = partner;
      if (me.gender == 'Female' || partner.gender == 'Male') {
        groom = partner;
        bride = me;
      }

      // Google Play Billing purchase sheet (one-time consumable product).
      final result = await ref
          .read(playBillingServiceProvider)
          .buyConsumable(BillingProducts.horoscopeReport);
      if (!mounted) return;

      if (result.isPurchased) {
        // Record what Play ACTUALLY charged rather than the hardcoded constant,
        // so admin revenue stays correct if the Console price is ever changed.
        final raw = ref
            .read(playBillingServiceProvider)
            .rawPrice(BillingProducts.horoscopeReport);
        final chargedAmount = (raw != null && raw > 0) ? raw.round() : _fee;

        // Verified purchase → save the purchase + auto-assign the analysis, then
        // unlock via the Reports tab.
        await ref.read(matchAnalysisControllerProvider.notifier)
            .requestAndAssignAnalysis(
              groom: groom,
              bride: bride,
              amount: chargedAmount,
              paymentId: result.purchaseToken.isNotEmpty
                  ? result.purchaseToken
                  : 'play_billing',
            );
        if (!mounted) return;
        _snack('Payment successful. Your analysis has been assigned to an '
            'astrologer — track it on the Reports tab.');
        ref.read(homeTabIndexProvider.notifier).state = 3; // Reports tab
        context.go('/home');
        return;
      }

      // Not purchased → the report stays locked; explain and reset the button.
      switch (result.outcome) {
        case BillingOutcome.canceled:
          _snack('Payment cancelled — you have not been charged.');
          break;
        case BillingOutcome.unavailable:
          _snack(result.message ??
              'Google Play Billing is unavailable on this device.');
          break;
        default:
          _snack(result.message ??
              'Payment could not be completed. You have not been charged.');
      }
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _snack('Could not start the payment. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(astrologyServiceConfigProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Analysis'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => _body(AstrologyServiceConfig.defaults),
        data: (cfg) => _body(cfg),
      ),
      bottomNavigationBar: _payBar(),
    );
  }

  Widget _body(AstrologyServiceConfig cfg) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _introCard(cfg),
        const SizedBox(height: 14),
        _includesCard(cfg),
        const SizedBox(height: 14),
        _metaCard(),
        const SizedBox(height: 18),
        const Text('Meet Our Astrology Expert',
            style: TextStyle(
                fontSize: 16, fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _expertCard(cfg),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Sticky Pay bar ─────────────────────────────────────────────────────────
  Widget _payBar() => Container(
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
              onPressed: _busy ? null : _payAndRequest,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 20),
              label: Text(
                _busy
                    ? 'Processing…'
                    : 'Pay $_priceText · Request Horoscope Analysis',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      );

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
                Expanded(
                  child: Text('Online Horoscope Compatibility Report',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(cfg.serviceIntro,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 8),
            const Text(
              'A fully online service — your report is delivered to your Reports '
              'page. No appointment or office visit needed.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
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

  Widget _metaCard() => _card(
        title: 'Service Details',
        icon: Icons.info_outline,
        child: Column(
          children: [
            _metaRow(Icons.cloud_done_outlined, 'Service type',
                'Online report (no visit)'),
            const Divider(height: 18),
            _metaRow(Icons.schedule_outlined, 'Estimated delivery',
                'Within 2 working days after payment'),
            const Divider(height: 18),
            _metaRow(Icons.payments_outlined, 'Service charge', _priceText),
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

  Widget _expertCard(AstrologyServiceConfig cfg) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: cfg.expertPhotoUrl.isNotEmpty
                  ? NetworkImage(cfg.expertPhotoUrl)
                  : null,
              child: cfg.expertPhotoUrl.isEmpty
                  ? const Icon(Icons.person, color: AppColors.primary, size: 32)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cfg.expertName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  _expertLine(Icons.workspace_premium_outlined,
                      cfg.expertExperience),
                  const SizedBox(height: 2),
                  _expertLine(Icons.auto_awesome_outlined,
                      cfg.expertSpecialization),
                ],
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
