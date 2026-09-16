import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';

/// The confirmation shown after a horoscope report is PAID FOR and the request
/// has been created (spec §20).
///
/// It states BOTH facts, because they are two different things and the member
/// has no other way to tell them apart:
///
///   1. **Payment Successful** — Google Play charged them; and
///   2. **Horoscope Request Submitted · Status: Pending** — a request now
///      exists for the astrology team, and it has not been worked on yet.
///
/// It is only ever opened once the request has actually been WRITTEN, so it can
/// never claim a submission that did not happen. A purchase whose request could
/// not be saved keeps its Play token and says so instead — see the callers.
///
/// Shared by both places that sell a report — the profile-based Horoscope
/// Compatibility Report and the standalone New Horoscope Report request — so
/// the same payment tells the member the same thing whichever door they came
/// through.
class HoroscopePaymentSuccessDialog extends StatelessWidget {
  /// The request id worth carrying away. Omitted (empty) when the flow has no
  /// member-facing reference to quote.
  final String requestId;

  /// Extra guidance for a GUEST, who has no Reports page to track this on.
  final bool isGuest;

  const HoroscopePaymentSuccessDialog({
    super.key,
    this.requestId = '',
    this.isGuest = false,
  });

  /// Opens the dialog and returns once the member dismisses it. Not
  /// barrier-dismissible: this is the only confirmation of a payment, so it is
  /// closed deliberately rather than by a stray tap.
  static Future<void> show(
    BuildContext context, {
    String requestId = '',
    bool isGuest = false,
  }) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => HoroscopePaymentSuccessDialog(
          requestId: requestId,
          isGuest: isGuest,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The same success mark the Interest Sent confirmation uses, so
            // "it worked" reads identically wherever it happens.
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withValues(alpha: 0.12),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.check_rounded,
                  size: 46, color: AppColors.success),
            ),
            const SizedBox(height: 18),
            Text(l10n.paymentSuccessfulTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    height: 1.3,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(l10n.paymentSuccessfulBody,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, height: 1.5, color: Colors.grey[700])),
            const SizedBox(height: 16),
            // The SECOND fact: the request exists, and where it stands.
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(l10n.horoscopeRequestSubmitted,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success)),
                  const SizedBox(height: 4),
                  Text(l10n.horoscopeRequestStatusLine,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey[700])),
                ],
              ),
            ),
            if (requestId.isNotEmpty) ...[
              const SizedBox(height: 12),
              // The one thing worth carrying away from this screen.
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(l10n.requestIdLabel,
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                    const SizedBox(height: 3),
                    SelectableText(requestId,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ],
                ),
              ),
            ],
            if (isGuest) ...[
              const SizedBox(height: 14),
              Text(l10n.guestRequestTrackHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/login');
                  },
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(l10n.loginToContinue),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(l10n.done,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
