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

/// Temporary PAYMENT TEST MODE for the one-time Horoscope Request fee — the
/// only payment in the app (there is no membership or subscription system).
///
/// While `true`, a Horoscope Request is marked paid IMMEDIATELY with a demo
/// payment id: the request, its assignment and its report pipeline all run
/// exactly as a real purchase would, only the Google Play Billing step is
/// bypassed.
///
/// Set this to `false` to restore the production flow:
///   Request → Google Play Billing → Payment Success → Request confirmed.
const bool kPaymentTestMode = true;
