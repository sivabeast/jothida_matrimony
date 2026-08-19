import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/porutham_match.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/compatibility_report_model.dart';
import '../../models/profile_model.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../report/compatibility_report_screen.dart';

/// The ONE canonical **Horoscope Match Result** page (`/horoscope-match/:uid`).
///
/// Every horoscope entry point lands here — "View Profile → Horoscope" and
/// "Interests → Accepted → Get Horoscope Compatibility Report" alike — so there
/// is a single result UI, never two.
///
/// It shows the FREE basic result first, computed live by [computePorutham]
/// from both members' star/rasi data:
///   • the porutham counts (total / matched / not matched) — numbers only,
///     never a percentage, grade or "Excellent / Good / Average Match" label;
///   • the matched poruthams and the ones that need attention;
///   • what the paid astrologer-prepared report adds (Service Details);
///   • and only THEN the paid "Get Horoscope Compatibility Report" CTA.
///
/// The other member's raw horoscope fields are never displayed — only derived
/// compatibility, so privacy is preserved.
class HoroscopeMatchScreen extends ConsumerWidget {
  final String userId; // UID of the member being compared with
  const HoroscopeMatchScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meAsync = ref.watch(myProfileProvider);
    final otherAsync = ref.watch(profileByUserIdProvider(userId));

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Horoscope Match'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Builder(builder: (_) {
        if (meAsync.isLoading || otherAsync.isLoading) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final me = meAsync.valueOrNull;
        final other = otherAsync.valueOrNull;
        if (me == null) {
          return const _Message(
            icon: Icons.person_off_outlined,
            text: 'Complete your own horoscope to see a match result.',
          );
        }
        if (other == null) {
          return const _Message(
            icon: Icons.auto_awesome_outlined,
            text: 'Match result is unavailable for this member.',
          );
        }
        // ALWAYS computed live from the two real profiles — no sample values,
        // no cached counts from another pairing.
        final result = computePorutham(me, other);
        return _ResultView(result: result, other: other);
      }),
    );
  }
}

class _ResultView extends ConsumerWidget {
  /// Null when either side lacks the star/rasi data needed to compute the
  /// poruthams — the basic result is then unavailable, but the paid report
  /// (which an astrologer prepares by hand) still is.
  final PoruthamMatchResult? result;
  final ProfileModel other;
  const _ResultView({required this.result, required this.other});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = result;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (r == null)
          const _NoticeCard(
            icon: Icons.auto_awesome_outlined,
            text: 'Not enough horoscope data to calculate the poruthams for '
                'this pair. You can still request a detailed report — our '
                'astrology expert works from both horoscopes directly.',
          )
        else ...[
          _CountCard(result: r, otherName: other.name),
          const SizedBox(height: 16),
          if (r.matching.isNotEmpty)
            _PoruthamGroup(
              title: 'Matching Poruthams',
              items: r.matching,
              matched: true,
            ),
          if (r.matching.isNotEmpty && r.nonMatching.isNotEmpty)
            const SizedBox(height: 12),
          if (r.nonMatching.isNotEmpty)
            _PoruthamGroup(
              title: 'Not Matching / Needs Attention',
              items: r.nonMatching,
              matched: false,
            ),
        ],
        const SizedBox(height: 16),
        const _ServiceDetailsCard(),
        const SizedBox(height: 14),
        _ReportCta(other: other),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'This basic result is an automated calculation from both members '
            'birth-star details. For a final decision, please consult a '
            'qualified astrologer.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

/// The basic result: how many of the poruthams matched and how many did not.
/// Numbers ONLY — no percentage, no score, no Excellent/Good/Average label.
class _CountCard extends StatelessWidget {
  final PoruthamMatchResult result;
  final String otherName;
  const _CountCard({required this.result, required this.otherName});

  @override
  Widget build(BuildContext context) {
    final matched = result.matchedCount;
    final notMatched = result.totalCount - result.matchedCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text('Horoscope match with $otherName',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          // Total poruthams evaluated — read from the result, never hardcoded.
          Text('${result.totalCount} Poruthams',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CountTile(
                  icon: Icons.check_circle,
                  count: matched,
                  label: 'Matched',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CountTile(
                  icon: Icons.error_outline,
                  count: notMatched,
                  label: 'Not Matched',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;
  const _CountTile(
      {required this.icon, required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 6),
          Text('$count',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PoruthamGroup extends StatelessWidget {
  final String title;
  final List<PoruthamResult> items;
  final bool matched;
  const _PoruthamGroup(
      {required this.title, required this.items, required this.matched});

  @override
  Widget build(BuildContext context) {
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
                    child: Text(p.name,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w500)),
                  ),
                  Text(p.note,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Explains what the PAID astrologer-prepared report adds on top of the free
/// basic result above. The "Report Includes" list, delivery time and charge all
/// come from the admin-managed `astrology_service/config` — never hardcoded.
class _ServiceDetailsCard extends ConsumerWidget {
  const _ServiceDetailsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(astrologyServiceConfigValueProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Service Details',
                  style: TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ],
          ),
          const Divider(height: 18),
          _label('Service Type'),
          const SizedBox(height: 6),
          _bullet('Online Horoscope Compatibility Report'),
          _bullet('No physical appointment or office visit required'),
          const SizedBox(height: 14),
          _label('Report Includes'),
          const SizedBox(height: 6),
          for (final item in cfg.reportIncludes) _bullet(item),
          const SizedBox(height: 14),
          _label('Delivery'),
          const SizedBox(height: 6),
          _bullet('Prepared personally by our astrology expert'),
          _bullet('Delivered online to your Reports section'),
          _bullet(cfg.deliveryTime),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.payments_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.l10n.serviceCharge,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              ),
              Text('₹${cfg.serviceCharge}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primary));

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child:
                  Icon(Icons.check_circle, size: 16, color: AppColors.success),
            ),
            const SizedBox(width: 8),
            Expanded(
              child:
                  Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
          ],
        ),
      );
}

/// The paid CTA, shown BELOW the free basic result. Honours the one-request-
/// per-partner rule: no request yet → "Get Horoscope Compatibility Report"
/// (which opens the payment flow); pending → a status chip that jumps to
/// Reports; completed → "View Horoscope Report".
class _ReportCta extends ConsumerWidget {
  final ProfileModel other;
  const _ReportCta({required this.other});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final reqAsync = ref.watch(compatRequestForPairProvider(other.id));
    // Withhold the CTA until the answer is known — a member who already paid
    // must never see the paid button flash first.
    if (reqAsync.isLoading && !reqAsync.hasValue) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
    }
    final req = reqAsync.valueOrNull;

    if (req == null) {
      final cfg = ref.watch(astrologyServiceConfigValueProvider);
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              // Payment happens on the service screen — never before the user
              // has seen the basic result above.
              onPressed: () =>
                  context.push('/horoscope-report/${other.userId}'),
              icon: const Icon(Icons.description_outlined),
              label: Text(l10n.getHoroscopeCompatibilityReport,
                  textAlign: TextAlign.center),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
              '₹${cfg.serviceCharge} · detailed report by our astrology expert',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      );
    }

    if (req.status == AstrologerRequestStatus.completed) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _openExisting(context, ref, req),
          icon: const Icon(Icons.visibility_outlined),
          label: Text(l10n.viewHoroscopeReport),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
          context.go('/home');
        },
        icon: const Icon(Icons.hourglass_top),
        label: Text(l10n.reportUnderAnalysisTitle),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.warning,
          side: BorderSide(color: AppColors.warning.withValues(alpha: 0.6)),
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  /// Completed + structured → the read-only A4 report; anything else → the
  /// Reports tab, where the request's live status card lives.
  void _openExisting(
      BuildContext context, WidgetRef ref, AstrologerRequestModel req) {
    final compat = CompatibilityReport.tryFrom(req.compatReport);
    if (compat != null && compat.isSubmitted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            CompatibilityReportScreen(requestId: req.id, request: req),
      ));
      return;
    }
    ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
    context.go('/home');
  }
}

/// An informational card used when the basic result cannot be computed.
class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _NoticeCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Icon(icon, size: 20, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(text, style: const TextStyle(fontSize: 13, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 64, color: AppColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
