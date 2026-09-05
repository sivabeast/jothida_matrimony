import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import 'play_billing_service.dart';

/// The ONE ₹199 horoscope-report purchase, shared by every screen that sells
/// one.
///
/// Two places take this money — the profile-based Horoscope Compatibility
/// Report (`HoroscopeReportServiceScreen`) and the standalone New Horoscope
/// Report request (`RequestExternalReportScreen`) — and they must behave
/// identically: the same Play product, the same verification, the same amount
/// recorded, the same words when it fails. That was previously copied into both
/// screens, which is exactly how two payment flows drift apart. It lives here
/// now, and both callers do nothing but `await buyHoroscopeReport(...)`.
///
/// Nothing about the money is decided here: Play Console owns the price, the
/// `verifyPlayPurchase` Cloud Function owns the verdict. This only sequences
/// them and reports what happened.

/// The result of one attempt to buy a horoscope report.
class HoroscopeReportPayment {
  final BillingResult result;

  /// What Play ACTUALLY charged, in rupees — read back from the store rather
  /// than assumed, so admin revenue stays correct when the Console price
  /// changes without an app update. Falls back to [AppConstants.horoscopeAnalysisFee].
  final int chargedAmount;

  const HoroscopeReportPayment(this.result, this.chargedAmount);

  bool get isPaid => result.isPurchased;

  /// The Play purchase token to persist with the request. Never empty for a
  /// paid result — a purchase Play could not name still gets a marker, because
  /// an empty payment id on a paid request reads as "unpaid" everywhere else.
  String get purchaseToken => result.purchaseToken.isNotEmpty
      ? result.purchaseToken
      : (isPaid ? 'play_billing' : '');

  /// `'server'` when Play itself confirmed the token, `'client'` when only the
  /// local check ran. Recorded on the request so the two can be reconciled.
  String get verifiedBy =>
      result.verification == BillingVerification.server ? 'server' : 'client';

  String get orderId => result.orderId;

  /// Why the purchase did not complete, in the member's language.
  ///
  /// Always the LOCALIZED sentence, never [BillingResult.message]: that field
  /// carries developer text — 'Product "horoscope_report" is unavailable.
  /// Ensure it is created and ACTIVE in Play Console', a raw plugin exception —
  /// which is English, unactionable, and the wrong thing to put in front of
  /// somebody in Tamil who has just tried to pay us. It is logged instead, so
  /// it is still there when someone goes looking.
  ///
  /// Cancelling is deliberately not phrased as an error: nothing was charged
  /// and nothing was lost.
  String failureMessage(AppLocalizations l10n) {
    final detail = result.message;
    if (detail != null && detail.isNotEmpty) {
      debugPrint('[Billing] horoscope report not purchased '
          '(${result.outcome.name}): $detail');
    }
    return switch (result.outcome) {
      BillingOutcome.canceled => l10n.paymentCancelledNotCharged,
      BillingOutcome.unavailable => l10n.billingUnavailable,
      _ => l10n.paymentCouldNotComplete,
    };
  }
}

/// Opens the Google Play purchase sheet for the one-time `horoscope_report`
/// product and returns once Play reports a terminal outcome.
///
/// **Throwing is not an outcome.** A store that cannot be reached at all comes
/// back as [BillingOutcome.unavailable], so every caller has exactly one shape
/// to handle and none of them has to guess what an exception meant. That
/// includes failing to BUILD the service — hence the factory: a device with no
/// Play Billing at all cannot even construct it, and an exception escaping a
/// pay button leaves it spinning forever with nothing on screen to explain why.
Future<HoroscopeReportPayment> buyHoroscopeReport(
    PlayBillingService Function() billingFactory) async {
  try {
    final billing = billingFactory();
    final result = await billing.buyConsumable(BillingProducts.horoscopeReport);
    final raw = billing.rawPrice(BillingProducts.horoscopeReport);
    final charged = (raw != null && raw > 0)
        ? raw.round()
        : AppConstants.horoscopeAnalysisFee;
    return HoroscopeReportPayment(result, charged);
  } catch (e) {
    return HoroscopeReportPayment(
      BillingResult(BillingOutcome.unavailable,
          productId: BillingProducts.horoscopeReport, message: '$e'),
      AppConstants.horoscopeAnalysisFee,
    );
  }
}

/// Play's own localized price for the horoscope report (e.g. "₹199.00"), or
/// null while the store is still answering / unreachable.
///
/// Best-effort by design: an emulator without Play, a device with no network
/// or a product that is not ACTIVE in Play Console must never surface an error
/// here — the caller keeps showing the built-in ₹199 until Play answers.
///
/// The service arrives as a FACTORY rather than an instance so that even
/// building it counts as "the store did not answer". Callers run this from
/// `initState`, where an exception has no user-facing home to go to and would
/// surface as an unhandled async error over a price label.
Future<String?> loadHoroscopeReportPrice(
    PlayBillingService Function() billing) async {
  try {
    final service = billing();
    await service.init();
    return service.priceLabel(BillingProducts.horoscopeReport);
  } catch (_) {
    return null;
  }
}
