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
