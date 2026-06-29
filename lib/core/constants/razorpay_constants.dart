/// Razorpay configuration.
///
/// ────────────────────────────────────────────────────────────────────────────
/// SECURITY: only the **Key ID** belongs in the mobile app — it is a publishable
/// identifier. The **Key Secret must NEVER be embedded in the client** (anyone
/// can decompile the app and extract it). The secret is a SERVER-side credential
/// used to (a) create Razorpay orders and (b) verify the payment signature after
/// checkout. When you move to LIVE mode, create orders + verify signatures from a
/// trusted backend (e.g. a Cloud Function) using the secret — keep it out of here.
/// ────────────────────────────────────────────────────────────────────────────
class RazorpayConstants {
  RazorpayConstants._();

  /// Flip to `true` for production. Live mode uses [liveKeyId]; everything else
  /// (checkout flow, success/failure handling) stays identical — this is the
  /// only switch needed to move from Test → Live.
  static const bool liveMode = false;

  // ── Test (Razorpay test dashboard) ──────────────────────────────────────────
  static const String testKeyId = 'rzp_test_T6K15IF56NRVRb';

  // ── Live (fill in before going to production) ───────────────────────────────
  static const String liveKeyId = 'rzp_live_XXXXXXXXXXXXXXXXX';

  /// The Key ID the checkout uses, resolved from [liveMode].
  static const String keyId = liveMode ? liveKeyId : testKeyId;

  // NOTE: there is intentionally NO key secret here. See the security banner
  // above — the secret lives ONLY on the server, never in this app.

  static const String currency = 'INR';
  static const String businessName = 'Jothida Matrimony';
  static const String appName = businessName;
  static const String description = 'Subscription Payment';

  // Prefill
  static const String supportEmail = 'support@jothidamatrimony.com';
  static const String supportPhone = '+91 9000000000';

  // Themes
  static const String themeColor = '#800020';
}
