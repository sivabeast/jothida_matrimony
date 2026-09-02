/// The **₹199 price block** and the **free sample teaser** that precede every
/// horoscope compatibility payment (spec §2/§3).
///
/// They live here, together, because both entry points to the paid report — the
/// existing-profile flow (`/horoscope-report/:uid`) and the manual two-chart
/// request — must show the SAME price, the SAME "one request, one fee"
/// promise and the SAME sample. A member who is quoted ₹199 on one screen and
/// something else on the other has been misled, and the surest way to prevent
/// that is to have one widget say it.
///
/// Everything is intrinsically sized: no fixed heights, every label wraps.
/// Tamil renders about 40% taller than English here and must not be clipped
/// (spec §5A/§11).
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';

/// "Amount payable ₹199", plus the rule that makes the number believable: the
/// fee is for ONE COMPLETE report covering BOTH people — never per person and
/// never per profile (spec §2).
class HoroscopeFeeCard extends StatelessWidget {
  /// Play's own localized price when the store has answered (e.g. "₹199.00"),
  /// otherwise the app's built-in "₹199". Passed in rather than read here so
  /// this stays a pure widget.
  final String priceText;

  /// Hides the "one request = one fee" explainer where the surrounding screen
  /// has already made that point.
  final bool showFeeRule;

  const HoroscopeFeeCard({
    super.key,
    required this.priceText,
    this.showFeeRule = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.workspace_premium_outlined,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.horoscopeCompatibilityReport,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 12),
          // Wrap, not Row: in Tamil "செலுத்த வேண்டிய தொகை" plus the price is
          // wider than a phone, so the amount drops to its own line instead of
          // overflowing.
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.amountPayable,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600)),
              Text(priceText,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          if (showFeeRule) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.oneRequestOneFeeNote,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            height: 1.5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The free-sample teaser: what a finished report looks like, before any money
/// is asked for (spec §3B).
class HoroscopeSamplePreviewCard extends StatelessWidget {
  final VoidCallback onView;

  const HoroscopeSamplePreviewCard({super.key, required this.onView});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_stories_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.notSureWhatYouGet,
                  style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 5),
          Text(l10n.sampleReportTeaser,
              style: TextStyle(
                  fontSize: 12, height: 1.5, color: Colors.grey[700])),
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onView,
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: Text(l10n.viewSampleReport,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 13, height: 1.25, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                // Intrinsic vertical padding instead of a fixed height, so a
                // two-line Tamil label still fits.
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
