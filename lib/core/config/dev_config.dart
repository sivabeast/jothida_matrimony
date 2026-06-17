/// Temporary development configuration.
///
/// TODO(auth): Remove this file (and all references to `kBypassAuth`) once real
/// authentication — Firebase Auth, Google Sign-In, phone OTP, validation — is
/// wired up for production. This flag exists ONLY to allow frontend/UI testing
/// without a working auth backend.
///
/// When `kBypassAuth` is true:
///   * "Continue with Google" navigates straight to the Home screen.
///   * The router's auth guard is disabled so every screen is reachable.
///
/// Set this to `false` (or delete it) to restore real authentication behavior.
const bool kBypassAuth = false;

/// Temporary subscription TEST MODE.
///
/// While `true`, selecting any subscription plan (user OR astrologer) activates
/// it **immediately with no payment** — the subscription record, user/astrologer
/// status, premium access and expiry are all written exactly as a real purchase
/// would, only the Razorpay/Play-Billing step is bypassed. The UI shows a
/// "🧪 TEST MODE" badge and an "Activate Plan" button instead of "Pay Now".
///
/// Set this to `false` to restore the production flow:
///   Select Plan → Payment Gateway → Payment Success → Activate Subscription.
///
/// All subscription logic, premium-access checks, expiry calculations and plan
/// validation stay intact in both modes — only the payment step is skipped.
const bool kSubscriptionTestMode = true;
