import '../models/user_model.dart';

/// Everywhere a GUEST (anonymous) session is allowed to go.
///
/// Guest Mode is an ALLOW-LIST, deliberately — not a block-list of the
/// personalized screens. Every route that is not named here sends a guest to
/// the Login Required screen, so a personalized feature added later is locked
/// down by default instead of being exposed until someone remembers to block
/// it. These are the screens that show public, non-personal information only.
const Set<String> kGuestAllowedRoutes = {
  '/', // splash
  '/login',
  '/register',
  '/forgot-password',
  '/login-required',
  '/home', // browse + explore (personalized cards gate themselves)
  '/muhurtham-calendar', // public almanac
  // Astrology services are public content a guest may browse (§6). BOOKING an
  // appointment is gated separately — it needs a login (but NOT a matrimony
  // profile, §8) — inside the booking screen itself.
  '/astrology-appointment',
  '/help',
  '/language',
  '/privacy-policy',
  '/terms',
  '/child-safety',
};

/// Routes that a guest may REACH even though the feature behind them is
/// member-only, because the screen wraps itself in a `MemberGate` (see
/// `lib/core/utils/member_access.dart`).
///
/// Bouncing these to /login-required would hide the very thing the spec asks
/// for: the Tamil "create your Matrimony Profile first" message, shown in
/// place of the content, with a one-tap way to fix it. The gate — not the
/// router — decides what the guest actually sees, and it never renders the
/// protected content.
const List<String> kSelfGatedRoutePrefixes = [
  '/profile/', // member profile view (…/edit is a member-only sub-route too)
  '/profile-user/',
  '/chats',
  '/chat/',
  '/interests',
];

/// Onboarding routes a GUEST must not reach: a guest has no account to attach
/// a profile to, and the security rules reject every anonymous write. The
/// gate's guest branch sends them to Login / Register first instead.
const List<String> kGuestBlockedOnboardingRoutes = [
  '/profile/create',
  '/complete-profile',
];

/// True when a guest may open [location].
bool isGuestAllowedRoute(String location) {
  if (kGuestBlockedOnboardingRoutes.contains(location)) return false;
  return kGuestAllowedRoutes.contains(location) ||
      // Admin broadcasts are public read-only content.
      location.startsWith('/announcement/') ||
      kSelfGatedRoutePrefixes.any(location.startsWith);
}

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
/// [isGuest] is `true` for an anonymous (Guest Mode) session. A guest is
/// authenticated as far as Firebase is concerned but has NO `users/{uid}`
/// document and may never reach a personalized screen.
/// [pendingReturnRoute] is where a just-signed-in member should land instead of
/// Home — the location they were blocked from before logging in (spec §15).
String? resolveAuthRedirect({
  required String location,
  required bool isAuthenticated,
  required bool userDocLoading,
  required UserModel? user,
  bool isGuest = false,
  bool bypassAuth = false,
  bool familyLoginInProgress = false,
  String? pendingReturnRoute,
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

  // ── Guest browsing (spec §6) ─────────────────────────────────────────────
  // A fresh install NEVER sees the login page: the splash starts an anonymous
  // Guest session and lands on Home. Two states are treated identically here:
  //
  //   • `isGuest`        — the anonymous session succeeded (the normal path;
  //     the anonymous credential is what lets Home read public content);
  //   • `!isAuthenticated` — anonymous sign-in was unavailable (provider off,
  //     offline, App Check hiccup). The visitor STILL browses Home rather than
  //     being bounced to /login; the public sections simply render their empty
  //     states until they sign in.
  //
  // Everything outside the allow-list routes to /login-required, so a
  // personalized feature added later is locked down by default. Firestore
  // rules enforce the same boundary server-side (an anonymous session cannot
  // write anything), so this redirect is the UX, not the security.
  if (isGuest || !isAuthenticated) {
    if (isGuestAllowedRoute(loc)) return null;
    log?.call('guest blocked from "$loc" → /login-required');
    return '/login-required';
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
  // Account deleted / signed out mid-session is covered above; from here the
  // visitor is a real, documented account.
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
    // A member who was sent to log in from a gated feature goes straight BACK
    // to that feature (spec §15, Case 1); everyone else lands on Home.
    //
    // Profile creation is NEVER forced: signing in (or creating an account)
    // goes to Home, which shows a "Create Profile" call-to-action while the
    // member has no matrimony profile. Only tapping that CTA opens the wizard.
    final back = (pendingReturnRoute ?? '').trim();
    if (back.isNotEmpty && back != '/login' && back != '/login-required') {
      log?.call('authenticated on an auth page → returning to "$back"');
      return back;
    }
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
