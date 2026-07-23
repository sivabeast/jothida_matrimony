import '../models/user_model.dart';

/// The routing decision the GoRouter `redirect` callback makes, as a pure
/// function of the app's auth state.
///
/// Extracted from `appRouterProvider` so the "where does a signed-in user
/// land?" rules can be unit-tested — in particular the guarantee that a user
/// who has just authenticated on `/login` is always sent somewhere, and never
/// left sitting on the login screen.
///
/// Returns the location to redirect to, or `null` to stay put.
///
/// [userDocLoading] is `true` while `users/{uid}` is still being read. The
/// caller must re-invoke this once it resolves — the router does that from a
/// `currentUserProvider` listener — otherwise the "wait for the user doc"
/// branch below becomes a dead end.
String? resolveAuthRedirect({
  required String location,
  required bool isAuthenticated,
  required bool userDocLoading,
  required UserModel? user,
  bool bypassAuth = false,
  bool familyLoginInProgress = false,
  void Function(String message)? log,
}) {
  final loc = location;
  final onAuthPage =
      loc == '/login' || loc == '/register' || loc == '/forgot-password';
  final onSplash = loc == '/';

  // ── Demo mode (kBypassAuth): everything reachable, Home shows the
  // profile-completion card instead of force-redirecting. ──
  if (bypassAuth) return null;

  log?.call('redirect: loc=$loc, isAuthenticated=$isAuthenticated');
  if (!isAuthenticated) {
    // Single common login — unauthenticated users always land on /login.
    return (onAuthPage || onSplash) ? null : '/login';
  }

  // Authenticated → route by account type / onboarding status.
  if (userDocLoading) return null; // wait for the user doc to load
  log?.call('redirect check: loc=$loc, uid=${user?.uid}, role=${user?.role}, '
      'isAdmin=${user?.isAdmin}, '
      'isProfileComplete=${user?.isProfileComplete}');

  // ── Employee (team member) account ───────────────────────────────────────
  // An `astrologer`-role account is an admin-provisioned EMPLOYEE. It lives
  // ONLY in the Employee Portal (dashboard + request detail) and is locked out
  // of the whole matrimony experience for strict isolation.
  final onAstrologerPortal = loc == '/astrologer-dashboard' ||
      loc == '/astrologer-notifications' ||
      loc.startsWith('/astrologer-request');
  if (user != null && user.isAstrologer) {
    if (!onAstrologerPortal) {
      log?.call('employee account → /astrologer-dashboard');
      return '/astrologer-dashboard';
    }
    return null;
  }

  // The Employee Portal routes are off-limits to everyone else.
  if (onAstrologerPortal) {
    log?.call('⛔ non-employee blocked from "$loc" → /home');
    return '/home';
  }

  // ── Family user (invited Wedding Workspace member) ───────────────────────
  // A 'family' account has NO matrimony profile and must never reach the
  // matchmaking experience: it lives ONLY in the Wedding Workspace (plus the
  // public Muhurtham Calendar). Placed before the profile-completion check
  // because family users intentionally never complete onboarding.
  if (user != null && user.isFamily) {
    final allowed = loc == '/wedding-workspace' || loc == '/muhurtham-calendar';
    if (!allowed) {
      log?.call('family account → /wedding-workspace');
      return '/wedding-workspace';
    }
    return null;
  }

  // While the Login screen's "Family Member Login" flow is verifying an
  // invitation, hold the just-authenticated account on /login instead of
  // racing it into matrimony onboarding (its role may be about to become
  // 'family').
  if (onAuthPage && familyLoginInProgress) {
    log?.call('family login in progress — holding on /login');
    return null;
  }

  // ── Admin route protection ───────────────────────────────────────────────
  // Only 'admin' / 'super_admin' accounts may reach any /admin route.
  final onAdmin = loc == '/admin' || loc.startsWith('/admin/');
  if (onAdmin && !(user?.isAdmin ?? false)) {
    log?.call('⛔ non-admin blocked from "$loc" → /home');
    return '/home';
  }

  if (onAuthPage) {
    // Only a *pure* admin account auto-lands on the dashboard. A super_admin is
    // a normal user with extra powers, so they land on Home and open the
    // dashboard via the header Admin icon.
    if (user?.role == 'admin') return '/admin';
    // A pure admin account is exempt from onboarding; a super_admin is a NORMAL
    // matrimony user and onboards exactly like everyone else.
    if (user != null && !user.isProfileComplete && user.role != 'admin') {
      log?.call('profile incomplete → /profile/create');
      return '/profile/create';
    }
    // Nothing else keeps an authenticated account on the login screen.
    return '/home';
  }

  // Authenticated user with an incomplete profile must finish onboarding before
  // reaching any other authenticated screen (Home, chats, etc.).
  final onProfileCreate = loc == '/profile/create';
  if (user != null &&
      !onAdmin && // admins may still open /admin with an incomplete profile
      !user.isProfileComplete &&
      !onProfileCreate &&
      !onSplash) {
    log?.call('profile incomplete, blocking $loc → /profile/create');
    return '/profile/create';
  }

  // A user who has already completed their profile shouldn't be sent back
  // through onboarding.
  if (user != null && user.isProfileComplete && onProfileCreate) {
    log?.call('profile already complete → /home');
    return '/home';
  }

  return null;
}
