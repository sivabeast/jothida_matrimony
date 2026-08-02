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

  // Authenticated, doc resolved, but there is NO `users/{uid}` document.
  //
  // Two ways to get here, and BOTH must stay put rather than fall through:
  //   • Account deletion — the document is gone and the Auth session is being
  //     torn down. Falling through used to return '/home' from the `onAuthPage`
  //     branch below, which is exactly the reported "Delete Account only takes
  //     me back to Home, still logged in" bug.
  //   • A first-time sign-in whose document read raced ahead of the create.
  //     The sign-in flow invalidates `currentUserProvider` right after the
  //     write, so the correct behaviour is to wait for that, not to bounce.
  if (user == null) {
    log?.call('authenticated but no user document — holding at "$loc"');
    return onAuthPage || onSplash ? null : '/login';
  }
  log?.call('redirect check: loc=$loc, uid=${user.uid}, role=${user.role}, '
      'isAdmin=${user.isAdmin}, '
      'isProfileComplete=${user.isProfileComplete}');

  // ── Employee (team member) account ───────────────────────────────────────
  // An `astrologer`-role account is an admin-provisioned EMPLOYEE. It lives
  // ONLY in the Employee Portal (dashboard + request detail) and is locked out
  // of the whole matrimony experience for strict isolation.
  final onAstrologerPortal = loc == '/astrologer-dashboard' ||
      loc == '/astrologer-notifications' ||
      loc.startsWith('/astrologer-request');
  if (user.isAstrologer) {
    // Announcement pushes to the 'employees' topic deep-link to the shared
    // read-only announcement screen — allowed alongside the portal routes.
    if (!onAstrologerPortal && !loc.startsWith('/announcement/')) {
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
  if (user.isFamily) {
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
  if (onAdmin && !user.isAdmin) {
    log?.call('⛔ non-admin blocked from "$loc" → /home');
    return '/home';
  }

  // ── DEDICATED admin account (§2) ─────────────────────────────────────────
  // A PURE 'admin' role is an admin-only account: it opens the Admin Dashboard
  // and lives there. It must never reach the user Home, the user navigation,
  // profile creation or any other user-side page — so every location outside
  // /admin bounces back to the dashboard. (A super_admin is deliberately NOT
  // caught here: that account is a normal matrimony member with an extra Admin
  // shortcut.)
  if (user.role == 'admin') {
    if (!onAdmin) {
      log?.call('dedicated admin account → /admin (blocked "$loc")');
      return '/admin';
    }
    return null;
  }

  if (onAuthPage) {
    // (A pure admin account already returned above — it can only be on /admin.)
    // EVERY authenticated account lands on Home. Profile creation is NEVER
    // forced: signing in (or creating an account) goes straight to the Home
    // page, which shows a "Create Profile" call-to-action while the member has
    // no matrimony profile. Only tapping that CTA opens the wizard.
    log?.call('authenticated on an auth page → /home');
    return '/home';
  }

  // A user who has already completed their profile shouldn't be sent back
  // through onboarding.
  if (user.isProfileComplete && loc == '/profile/create') {
    log?.call('profile already complete → /home');
    return '/home';
  }

  return null;
}
