import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/porutham_match.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/astrology_service_config.dart';
import '../../models/compatibility_report_model.dart';
import '../../models/profile_model.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/billing/play_billing_service.dart';
import '../../widgets/common/network_photo.dart';
import '../report/compatibility_report_screen.dart';

/// The **ONE** Horoscope Compatibility Report page (`/horoscope-report/:uid`).
///
/// Every entry point for an existing matrimony profile lands here — the
/// profile page's CTA, the Accepted list's CTA, a member's horoscope page —
/// and the whole flow is exactly:
///
///   Profile → Horoscope Compatibility Report → ₹200 payment → Request created
///
/// There is deliberately NO intermediate informational screen. The separate
/// "Horoscope Match Result" page was merged into this one, so the free
/// porutham result, "What the report includes" and "Service Details" each
/// appear ONCE, on this page, above the single pay CTA.
///
/// This is a fully ONLINE report service — never an appointment. Payment goes
/// through Google Play Billing (one-time product `horoscope_report`); the
/// report request is created ONLY after a verified purchase, so a cancelled or
/// failed payment leaves nothing behind.
class HoroscopeReportServiceScreen extends ConsumerStatefulWidget {
  /// The other member's USER id (UID) whose horoscope is compared with ours.
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
  static const int _fee = AppConstants.horoscopeAnalysisFee; // ₹200

  bool _busy = false;

  /// Play's localized price for `horoscope_report` (e.g. "₹200.00"), loaded
  /// from the store when this screen opens. Null while the product is still
  /// resolving, on an emulator without Play, or if the product is not ACTIVE
  /// in Play Console.
  String? _storePrice;

  /// What the pay button and the Service Details row display. Prefers the real
  /// store price so changing the price in Play Console does NOT require an app
  /// update — without this the button could promise ₹200 while Play charged
  /// something else.
  String get _priceText => _storePrice ?? '₹$_fee';

  @override
  void initState() {
    super.initState();
    _loadStorePrice();
  }

  /// Best-effort: an unreachable store (emulator without Play, no network)
  /// must never surface an error here — the button simply keeps showing the
  /// built-in ₹200 until Play answers.
  Future<void> _loadStorePrice() async {
    try {
      final billing = ref.read(playBillingServiceProvider);
      await billing.init();
      if (!mounted) return;
      setState(() =>
          _storePrice = billing.priceLabel(BillingProducts.horoscopeReport));
    } catch (_) {
      // Keep the fallback price.
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  /// Resolve both profiles, launch the Google Play Billing purchase sheet for
  /// the one-time `horoscope_report` product, and — ONLY on a successful,
  /// verified purchase — create + auto-assign the analysis (saving the purchase
  /// token to Firestore) and unlock it on the Reports tab. A cancelled or failed
  /// purchase leaves the report locked and charges nothing.
  Future<void> _payAndRequest() async {
    if (_busy) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final me = ref.read(myProfileProvider).valueOrNull;
      final partner =
          await ref.read(profileByUserIdProvider(widget.otherUserId).future);
      if (me == null || partner == null) {
        _snack(l10n.couldNotLoadBothProfiles);
        if (mounted) setState(() => _busy = false);
        return;
      }
      // ONE request per partner profile (spec §12) — re-checked here, right
      // before the store sheet opens, so a stale button can never charge for
      // a duplicate. The completed/pending UI states replace the pay bar too.
      final existing =
          ref.read(compatRequestForPairProvider(partner.id)).valueOrNull;
      if (existing != null) {
        _snack(l10n.compatAlreadyRequestedNote);
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
        await ref
            .read(matchAnalysisControllerProvider.notifier)
            .requestAndAssignAnalysis(
              groom: groom,
              bride: bride,
              amount: chargedAmount,
              paymentId: result.purchaseToken.isNotEmpty
                  ? result.purchaseToken
                  : 'play_billing',
            );
        if (!mounted) return;
        _snack(l10n.paymentSuccessReportAssigned);
        ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
        context.go('/home');
        return;
      }

      // Not purchased → nothing is created; explain and reset the button.
      switch (result.outcome) {
        case BillingOutcome.canceled:
          _snack(l10n.paymentCancelledNotCharged);
          break;
        case BillingOutcome.unavailable:
          _snack(result.message ?? l10n.billingUnavailable);
          break;
        default:
          _snack(result.message ?? l10n.paymentCouldNotComplete);
      }
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _snack(context.l10n.couldNotStartPayment);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(astrologyServiceConfigProvider);
    // ONE request per partner profile (spec §12): resolve the partner's
    // profile id, then look up any existing request for the pair. While
    // either lookup is loading the pay button stays disabled — the sheet must
    // never open before the duplicate check has an answer.
    final partnerAsync = ref.watch(profileByUserIdProvider(widget.otherUserId));
    final partner = partnerAsync.valueOrNull;
    final existingAsync = partner == null
        ? const AsyncValue<AstrologerRequestModel?>.loading()
        : ref.watch(compatRequestForPairProvider(partner.id));
    final gateLoading = partnerAsync.isLoading || existingAsync.isLoading;
    final existing = existingAsync.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.horoscopeCompatibilityReport),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: cfgAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) =>
            _body(AstrologyServiceConfig.defaults, partner, existing),
        data: (cfg) => _body(cfg, partner, existing),
      ),
      bottomNavigationBar: existing == null
          ? _payBar(enabled: !gateLoading)
          : _existingBar(existing),
    );
  }

  Widget _body(AstrologyServiceConfig cfg, ProfileModel? partner,
      AstrologerRequestModel? existing) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    // ALWAYS computed live from the two real profiles — never a cached count
    // from another pairing. Null when either side lacks star/rasi data.
    final result =
        (me == null || partner == null) ? null : computePorutham(me, partner);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (existing != null) ...[
          _alreadyRequestedCard(existing),
          const SizedBox(height: 14),
        ],
        if (partner != null) ...[
          _partnerCard(partner),
          const SizedBox(height: 14),
        ],
        // ── The FREE basic result (merged in from the old separate page) ──
        if (result == null)
          _noticeCard(context.l10n.notEnoughHoroscopeForPair)
        else ...[
          _countCard(result, partner?.name ?? ''),
          const SizedBox(height: 14),
          _poruthamGroup(context.l10n.matchingPoruthams,
              result.matching, true),
          if (result.matching.isNotEmpty && result.nonMatching.isNotEmpty)
            const SizedBox(height: 12),
          _poruthamGroup(context.l10n.notMatchingPoruthams,
              result.nonMatching, false),
        ],
        const SizedBox(height: 14),
        // ── What the report adds — shown ONCE, on this page only ──
        _includesCard(cfg),
        const SizedBox(height: 14),
        _metaCard(),
        const SizedBox(height: 18),
        Text(context.l10n.meetOurAstrologyExpert,
            style: const TextStyle(
                fontSize: 16,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _expertCard(cfg),
        const SizedBox(height: 12),
        Text(context.l10n.basicResultDisclaimer,
            style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Who the report is for — photo, name, age and location, so the member can
  /// see at a glance that they are paying for the right pairing.
  Widget _partnerCard(ProfileModel p) {
    final location = [p.city, p.state]
        .where((s) => s.trim().isNotEmpty)
        .map(context.localizeValue)
        .join(', ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: NetworkPhoto(
                  url: p.profilePhotoUrl ?? '', fallbackIconSize: 28),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.reportForPair(p.name),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11.5)),
                const SizedBox(height: 4),
                Text(p.age > 0 ? '${p.name}, ${p.age}' : p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The free basic result: how many poruthams matched and how many did not.
  /// Numbers ONLY — no percentage, no score, no Excellent/Good/Average label.
  Widget _countCard(PoruthamMatchResult r, String otherName) {
    final l10n = context.l10n;
    final notMatched = r.totalCount - r.matchedCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.freeBasicResultTitle,
                    style: const TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const Divider(height: 18),
          if (otherName.trim().isNotEmpty)
            Text(l10n.horoscopeMatchWith(otherName),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          const SizedBox(height: 8),
          // Total poruthams evaluated — read from the result, never hardcoded.
          Text('${r.totalCount} ${l10n.poruthamsWord}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _countTile(Icons.check_circle, r.matchedCount,
                    l10n.matchedWord, AppColors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _countTile(Icons.error_outline, notMatched,
                    l10n.notMatchedWord, AppColors.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _countTile(IconData icon, int count, String label, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text('$count',
                style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _poruthamGroup(
      String title, List<PoruthamResult> items, bool matched) {
    if (items.isEmpty) return const SizedBox.shrink();
    final color = matched ? AppColors.success : AppColors.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(matched ? Icons.check_circle : Icons.error_outline,
                  color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$title (${items.length})',
                    style: TextStyle(
                        fontSize: 15,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ],
          ),
          const Divider(height: 16),
          for (final p in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(matched ? Icons.check : Icons.close,
                      color: color, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(context.localizeValue(p.name),
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w500)),
                  ),
                  Text(context.localizeValue(p.note),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _noticeCard(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome_outlined,
                size: 20, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, height: 1.45)),
            ),
          ],
        ),
      );

  /// "One report per profile" banner shown once a request for this pair exists.
  Widget _alreadyRequestedCard(AstrologerRequestModel existing) {
    final completed = existing.status == AstrologerRequestStatus.completed;
    final color = completed ? AppColors.success : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(completed ? Icons.task_alt : Icons.hourglass_top,
              size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              completed
                  ? context.l10n.reportReadyMsg
                  : context.l10n.compatAlreadyRequestedNote,
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky Pay bar (the ONE primary action) ───────────────────────────────
  Widget _payBar({required bool enabled}) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -2)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_busy || !enabled) ? null : _payAndRequest,
              icon: (_busy || !enabled)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 20),
              label: Text(
                _busy
                    ? context.l10n.processingPayment
                    : context.l10n.payAndRequestReport(_priceText),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      );

  /// Replaces the pay bar once a request for this pair exists: completed →
  /// "View Horoscope Report"; otherwise a status chip that jumps to Reports.
  Widget _existingBar(AstrologerRequestModel existing) {
    final completed = existing.status == AstrologerRequestStatus.completed;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openExisting(existing),
            icon: Icon(
                completed ? Icons.visibility_outlined : Icons.pending_actions,
                size: 20),
            label: Text(
              completed
                  ? context.l10n.viewHoroscopeReport
                  : context.l10n.reportUnderAnalysisTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  completed ? AppColors.success : AppColors.warning,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }

  /// Completed + structured → the read-only A4 report; anything else → the
  /// Reports tab, where the request's live status card lives.
  void _openExisting(AstrologerRequestModel existing) {
    final compat = CompatibilityReport.tryFrom(existing.compatReport);
    if (existing.status == AstrologerRequestStatus.completed &&
        compat != null &&
        compat.isSubmitted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CompatibilityReportScreen(
            requestId: existing.id, request: existing),
      ));
      return;
    }
    ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
    context.go('/home');
  }

  Widget _includesCard(AstrologyServiceConfig cfg) => _card(
        title: context.l10n.whatTheReportIncludes,
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
                      child: Text(context.localizeValue(item),
                          style: const TextStyle(fontSize: 13.5, height: 1.4)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(context.l10n.onlineServiceNote,
                style: TextStyle(
                    fontSize: 12, height: 1.45, color: Colors.grey[600])),
          ],
        ),
      );

  Widget _metaCard() {
    final l10n = context.l10n;
    return _card(
      title: l10n.serviceDetails,
      icon: Icons.info_outline,
      child: Column(
        children: [
          _metaRow(Icons.cloud_done_outlined, l10n.serviceTypeLabel,
              l10n.onlineReportNoVisit),
          const Divider(height: 18),
          _metaRow(Icons.schedule_outlined, l10n.estimatedDelivery,
              l10n.deliveryWithinTwoDays),
          const Divider(height: 18),
          _metaRow(Icons.payments_outlined, l10n.serviceCharge, _priceText),
        ],
      ),
    );
  }

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
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
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
                  _expertLine(
                      Icons.workspace_premium_outlined, cfg.expertExperience),
                  const SizedBox(height: 2),
                  _expertLine(
                      Icons.auto_awesome_outlined, cfg.expertSpecialization),
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
          child: Text(context.localizeValue(text),
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
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                ),
              ],
            ),
            const Divider(height: 18),
            child,
          ],
        ),
      );
}
