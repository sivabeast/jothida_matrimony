import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/config/dev_config.dart';
import '../core/navigation/root_navigator.dart';
import '../providers/auth_provider.dart';
import '../providers/service_providers.dart';
import '../models/astrologer_request_model.dart';
import '../screens/astrology/horoscope_report_service_screen.dart';
import '../screens/astrology/appointment_booking_screen.dart';
import '../screens/astrology/astrology_appointment_screen.dart';
import '../screens/astrology/appointment_confirmation_screen.dart';
import '../screens/astrology/my_appointments_screen.dart';
import '../screens/astrologer/match_workspace_screen.dart';
// Employee Portal (admin-provisioned horoscope-analysis staff; they sign in
// through the SAME common login as everyone else — there is no separate
// employee/astrologer login).
import '../screens/astrologer/portal/astrologer_shell.dart';
import '../screens/astrologer/portal/astrologer_notifications_page.dart';
import '../screens/astrologer/portal/astrologer_request_detail_page.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/my_profile_screen.dart';
import '../screens/profile/profile_creation_screen.dart';
import '../screens/profile/profile_success_screen.dart';
import '../screens/profile/profile_view_screen.dart';
import '../screens/match/match_details_screen.dart';
import '../screens/privacy/privacy_settings_screen.dart';
import '../screens/settings/language_screen.dart';
import '../screens/admin/admin_shell.dart';
import '../screens/admin/astrology_service_settings_screen.dart';
import '../screens/admin/admin_dashboard.dart';
import '../screens/admin/admin_users_page.dart';
import '../screens/admin/admin_edit_user_screen.dart';
import '../screens/admin/astrologer_accounts_screen.dart';
import '../screens/admin/astrologer_details_screen.dart';
import '../screens/admin/user_details_screen.dart';
import '../screens/admin/admin_astrologer_profile_screen.dart';
import '../screens/admin/admin_settlements_screen.dart';
import '../screens/admin/admin_horoscope_requests_screen.dart';
import '../screens/admin/admin_appointments_screen.dart';
import '../screens/admin/astrologer_verification_screen.dart';
import '../screens/admin/admin_management_screens.dart';
import '../screens/admin/admin_reports_page.dart';
import '../screens/admin/employee_commission_screen.dart';
import '../screens/admin/account_admin_screens.dart';
import '../screens/admin/announcement_management_screen.dart';
import '../screens/admin/app_update_settings_screen.dart';
import '../screens/admin/banner_management_screen.dart';
import '../screens/horoscope/horoscope_details_screen.dart';
import '../screens/horoscope/horoscope_files_screen.dart';
import '../screens/horoscope/horoscope_matching_screen.dart';
import '../screens/horoscope/member_horoscope_screen.dart';
import '../screens/horoscope/horoscope_match_screen.dart';
import '../screens/profile/personal_details_screen.dart';
import '../screens/profile/complete_profile_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/profile_section_edit_screens.dart';
import '../screens/profile/photos_edit_screen.dart';
import '../screens/family/family_tree_screen.dart';
import '../screens/interests/interests_center_screen.dart';
import '../screens/preferences/partner_preferences_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/support/help_support_screen.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_conditions_screen.dart';
import '../screens/report/report_profile_screen.dart';
import '../screens/muhurtham/muhurtham_calendar_screen.dart';
import '../screens/wedding/wedding_workspace_screen.dart';
import '../providers/wedding_provider.dart';
import '../core/theme/app_colors.dart';

/// Bridges a [Stream] (here, Firebase's `authStateChanges`) to a
/// [Listenable] that [GoRouter] can use as `refreshListenable`.
///
/// IMPORTANT: Without this, `appRouterProvider` would have to `ref.watch`
/// the auth stream directly, which makes Riverpod return a **brand-new**
/// `GoRouter` instance on every auth change. `MaterialApp.router` then
/// receives a new `routerConfig`, which resets the navigator back to
/// `initialLocation` ('/') — i.e. the splash screen. That was the cause of
/// "stuck on splash after Google Sign-In": the moment Firebase Auth fired
/// its state-change event (right after `signInWithCredential` succeeded),
/// the whole router (and the in-flight LoginScreen) was torn down and
/// rebuilt from scratch before `_routeByRole` could run.
///
/// Using `refreshListenable` instead keeps the SAME GoRouter/navigator
/// alive and just re-evaluates `redirect` for the current location.
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((event) {
      debugPrint('[Router] authStateChanges event: '
          '${event == null ? 'signed out' : 'signed in (${event.uid})'} '
          '— refreshing router');
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // `ref.read` (not `watch`) — we don't want this provider itself to rebuild
  // (and recreate the GoRouter) on auth changes. The refreshListenable below
  // handles re-running `redirect` instead.
  final authRepo = ref.read(authRepositoryProvider);
  final refreshStream = GoRouterRefreshStream(authRepo.authStateChanges);
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onAuthPage = loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot-password';
      final onSplash = loc == '/';

      // ── Demo mode (kBypassAuth): everything reachable, Home shows the
      // profile-completion card instead of force-redirecting. ──
      if (kBypassAuth) return null;

      // ── Real auth path ──
      // IMPORTANT: do NOT use `ref.read(firebaseAuthStreamProvider)` here.
      // `GoRouterRefreshStream` and the StreamProvider both subscribe to the
      // same Firebase authStateChanges stream. When signOut() fires, this
      // redirect runs (via notifyListeners) BEFORE the StreamProvider has
      // processed the null event — so it would still see the old user and
      // incorrectly return null (no redirect). Instead, read currentUser
      // synchronously from Firebase, which is always immediately accurate.
      final isAuthenticated = ref.read(authRepositoryProvider).currentUser != null;
      debugPrint('[Router] redirect: loc=$loc, isAuthenticated=$isAuthenticated');
      if (!isAuthenticated) {
        // Single common login — unauthenticated users always land on /login.
        return (onAuthPage || onSplash) ? null : '/login';
      }

      // Authenticated → route by account type / onboarding status.
      final userAsync = ref.read(currentUserProvider);
      if (userAsync.isLoading) return null; // wait for the user doc to load
      final user = userAsync.valueOrNull;
      debugPrint('[Router] redirect check: loc=$loc, uid=${user?.uid}, '
          'role=${user?.role}, isAdmin=${user?.isAdmin}, '
          'isProfileComplete=${user?.isProfileComplete}');

      // ── Employee (team member) account ───────────────────────────────────
      // An `astrologer`-role account is an admin-provisioned EMPLOYEE. It lives
      // ONLY in the Employee Portal (dashboard + request detail) and is locked
      // out of the whole matrimony experience for strict isolation.
      if (user != null && user.isAstrologer) {
        final allowed = loc == '/astrologer-dashboard' ||
            loc == '/astrologer-notifications' ||
            loc.startsWith('/astrologer-request');
        if (!allowed) {
          debugPrint('[Router] employee account → /astrologer-dashboard');
          return '/astrologer-dashboard';
        }
        return null;
      }

      // The Employee Portal routes are off-limits to everyone else.
      final onAstrologerPortal = loc == '/astrologer-dashboard' ||
          loc == '/astrologer-notifications' ||
          loc.startsWith('/astrologer-request');
      if (onAstrologerPortal && !(user?.isAstrologer ?? false)) {
        debugPrint('[Router] ⛔ non-employee blocked from "$loc" → /home');
        return '/home';
      }

      // ── Family user (invited Wedding Workspace member) ───────────────────
      // A 'family' account has NO matrimony profile and must never reach the
      // matchmaking experience: it lives ONLY in the Wedding Workspace (plus
      // the public Muhurtham Calendar). Placed before the profile-completion
      // check because family users intentionally never complete onboarding.
      if (user != null && user.isFamily) {
        final allowed = loc == '/wedding-workspace' ||
            loc == '/muhurtham-calendar';
        if (!allowed) {
          debugPrint('[Router] family account → /wedding-workspace');
          return '/wedding-workspace';
        }
        return null;
      }

      // While the Login screen's "Family Member Login" flow is verifying an
      // invitation, hold the just-authenticated account on /login instead of
      // racing it into matrimony onboarding (its role may be about to become
      // 'family').
      if (onAuthPage && ref.read(familyLoginInProgressProvider)) {
        debugPrint('[Router] family login in progress — holding on /login');
        return null;
      }

      // ── Admin route protection ───────────────────────────────────────────
      // Only 'admin' / 'super_admin' accounts may reach any /admin route.
      final onAdmin = loc == '/admin' || loc.startsWith('/admin/');
      if (onAdmin && !(user?.isAdmin ?? false)) {
        debugPrint('[Router] ⛔ non-admin blocked from "$loc" → /home');
        return '/home';
      }

      if (onAuthPage) {
        // Only a *pure* admin account auto-lands on the dashboard. A
        // super_admin is a normal user with extra powers, so they land on Home
        // and open the dashboard via the header Admin icon.
        if (user?.role == 'admin') return '/admin';
        // A pure admin account is exempt from onboarding; a super_admin is a
        // NORMAL matrimony user and onboards exactly like everyone else.
        if (user != null &&
            !user.isProfileComplete &&
            user.role != 'admin') {
          debugPrint('[Router] redirect: profile incomplete → /profile/create');
          return '/profile/create';
        }
        return '/home';
      }

      // Authenticated user with an incomplete profile must finish onboarding
      // before reaching any other authenticated screen (Home, chats, etc.).
      final onProfileCreate = loc == '/profile/create';
      if (user != null &&
          !onAdmin && // admins may still open /admin with an incomplete profile
          !user.isProfileComplete &&
          !onProfileCreate &&
          !onSplash) {
        debugPrint('[Router] redirect: profile incomplete, blocking $loc → /profile/create');
        return '/profile/create';
      }

      // A user who has already completed their profile shouldn't be sent
      // back through onboarding.
      if (user != null && user.isProfileComplete && onProfileCreate) {
        debugPrint('[Router] redirect: profile already complete → /home');
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      // ── Employee Portal (admin-provisioned staff; common login only) ─────
      GoRoute(
          path: '/astrologer-dashboard',
          builder: (_, __) => const AstrologerShell()),
      GoRoute(
          path: '/astrologer-notifications',
          builder: (_, __) => const AstrologerNotificationsPage()),
      GoRoute(
        path: '/astrologer-request/:id',
        builder: (_, state) => AstrologerRequestDetailPage(
          requestId: state.pathParameters['id']!,
          initial: state.extra is AstrologerRequestModel
              ? state.extra as AstrologerRequestModel
              : null,
        ),
      ),
      GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) => ChatScreen(
          threadId: state.pathParameters['id']!,
          extra: state.extra as Map<String, dynamic>?,
        ),
      ),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/profile/create', builder: (_, __) => const ProfileCreationScreen()),
      // Step 12 — onboarding success screen (completion % + next actions).
      GoRoute(
          path: '/profile/success',
          builder: (_, __) => const ProfileSuccessScreen()),
      GoRoute(
        path: '/profile/:id',
        builder: (_, state) => ProfileViewScreen(profileId: state.pathParameters['id']!),
      ),
      // Open a profile by the owner's USER id (UID). Used from accepted
      // interests, where senderId / receiverId is the reliable key — never an
      // interest-document id. Distinct path prefix so it can't collide with the
      // '/profile/:id' document-id route above.
      GoRoute(
        path: '/profile-user/:uid',
        builder: (_, state) =>
            ProfileViewScreen(userId: state.pathParameters['uid']!),
      ),
      // My Profile — the member's own profile organised into categories, each
      // with its own Edit action (Menu → "My Profile").
      GoRoute(path: '/my-profile', builder: (_, __) => const MyProfileScreen()),
      // Edit an existing profile (full wizard). 3 path segments so it never
      // collides with the 2-segment '/profile/:id' view route above.
      GoRoute(
        path: '/profile/:id/edit',
        builder: (_, state) =>
            ProfileCreationScreen(editProfileId: state.pathParameters['id']),
      ),
      // Edit ONE profile category (from My Profile) — opens just that step of
      // the wizard; saving updates only that section and returns.
      GoRoute(
        path: '/profile/:id/edit-section/:step',
        builder: (_, state) => ProfileCreationScreen(
          editProfileId: state.pathParameters['id'],
          sectionStep: int.tryParse(state.pathParameters['step'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/match/:id',
        builder: (_, state) =>
            MatchDetailsScreen(profileId: state.pathParameters['id']!),
      ),
      // Report a profile (from the profile view screen).
      GoRoute(
        path: '/report/:id',
        builder: (_, state) =>
            ReportProfileScreen(profileId: state.pathParameters['id']!),
      ),
      // ── Horoscope Compatibility Report (in-person appointment) ───────────
      // Service details page → appointment booking → confirmation. Opened from
      // an accepted match's "Get Horoscope Compatibility Report".
      GoRoute(
        path: '/horoscope-report/:userId',
        builder: (_, state) => HoroscopeReportServiceScreen(
            otherUserId: state.pathParameters['userId']!),
      ),
      GoRoute(
        path: '/book-appointment/:userId',
        builder: (_, state) => AppointmentBookingScreen(
            otherUserId: state.pathParameters['userId']!),
      ),
      // Standalone "Book Your Appointment" from the Astrology page (not tied to
      // a matched partner). Distinct path so the /astrology exact-match
      // redirect guard never catches it.
      GoRoute(
        path: '/astrology-appointment',
        builder: (_, __) => const AstrologyAppointmentScreen(),
      ),
      // The signed-in user's appointment booking history (status + date/time).
      GoRoute(
        path: '/my-appointments',
        builder: (_, __) => const MyAppointmentsScreen(),
      ),
      GoRoute(
        path: '/appointment-confirmation/:id',
        builder: (_, state) => AppointmentConfirmationScreen(
          bookingId: state.pathParameters['id']!,
          extra: state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null,
        ),
      ),
      // ── Match-analysis pipeline ──────────────────────────────────────────
      // (The standalone "My Reports" page was removed — the user's reports live
      // ONLY on the bottom-nav Reports tab now; see goToReportsTab.)
      // The analysis workspace for a request, opened from the Astrology
      // Dashboard. The request id is in the path so the page ALWAYS resolves the
      // live request (the optional `extra` snapshot only speeds up the first
      // paint) — reliable even after a restart or FCM deep link.
      GoRoute(
        path: '/match-workspace/:id',
        builder: (_, state) => MatchWorkspaceScreen(
          requestId: state.pathParameters['id']!,
          initialRequest: state.extra is AstrologerRequestModel
              ? state.extra as AstrologerRequestModel
              : null,
        ),
      ),
      // ── Marriage Muhurtham Calendar (general auspicious dates) ───────────
      GoRoute(
        path: '/muhurtham-calendar',
        builder: (_, __) => const MuhurthamCalendarScreen(),
      ),
      // ── Wedding Workspace (unlocked after mutual "Marriage Fixed") ───────
      // Shared by the couple and their invited family members.
      GoRoute(
        path: '/wedding-workspace',
        builder: (_, __) => const WeddingWorkspaceScreen(),
      ),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacySettingsScreen()),
      GoRoute(path: '/language', builder: (_, __) => const LanguageScreen()),
      // ── Profile section screens ──────────────────────────────────────────
      // Profile Details (PROFILE group) — photo, name & all personal info.
      GoRoute(path: '/personal-details', builder: (_, __) => const PersonalDetailsScreen()),
      // Interests as a standalone page (side menu's Interests Sent / Received).
      // ?tab=sent|received|accepted|rejected selects the opening tab.
      GoRoute(
        path: '/interests',
        builder: (_, state) {
          final tab = state.uri.queryParameters['tab'];
          final idx = switch (tab) {
            'sent' => 1,
            'accepted' => 2,
            'rejected' => 3,
            _ => 0, // received
          };
          return InterestsCenterScreen(initialTab: idx, standalone: true);
        },
      ),
      GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/complete-profile', builder: (_, __) => const CompleteProfileScreen()),
      // ── Section-wise profile editors (opened from the completion card) ────
      GoRoute(path: '/edit/about', builder: (_, __) => const AboutMeEditScreen()),
      GoRoute(
          path: '/edit/education',
          builder: (_, __) => const EducationEditScreen()),
      GoRoute(
          path: '/edit/location',
          builder: (_, __) => const LocationEditScreen()),
      GoRoute(
          path: '/edit/religious',
          builder: (_, __) => const ReligiousEditScreen()),
      GoRoute(
          path: '/edit/family', builder: (_, __) => const FamilyEditScreen()),
      GoRoute(
          path: '/edit/lifestyle',
          builder: (_, __) => const LifestyleEditScreen()),
      GoRoute(
          path: '/edit/photos', builder: (_, __) => const PhotosEditScreen()),
      GoRoute(path: '/horoscope', builder: (_, __) => const HoroscopeDetailsScreen()),
      // Horoscope Matching — accepted matches only, with horoscope compare /
      // compatibility / astrologer-analysis actions (ASTROLOGY menu group).
      GoRoute(
          path: '/horoscope-matching',
          builder: (_, __) => const HoroscopeMatchingScreen()),
      // Horoscope / Jathagam document manager (multiple images + PDFs CRUD).
      GoRoute(
          path: '/horoscope-files',
          builder: (_, __) => const HoroscopeFilesScreen()),
      // Read-only horoscope of an accepted match (kept for other callers).
      GoRoute(
        path: '/horoscope-user/:uid',
        builder: (_, state) =>
            MemberHoroscopeScreen(userId: state.pathParameters['uid']!),
      ),
      // Horoscope Match Result for an accepted match
      // (Interests → Accepted → Horoscope). Shows compatibility only — never the
      // other member's raw horoscope fields.
      GoRoute(
        path: '/horoscope-match/:uid',
        builder: (_, state) =>
            HoroscopeMatchScreen(userId: state.pathParameters['uid']!),
      ),
      // Family Tree — own (/family-tree) and an accepted match's
      // (/family-tree-user/:uid). The matched-user entry button is only shown on
      // a profile whose interest has been accepted.
      GoRoute(
          path: '/family-tree',
          builder: (_, __) => const FamilyTreeScreen()),
      GoRoute(
        path: '/family-tree-user/:uid',
        builder: (_, state) =>
            FamilyTreeScreen(userId: state.pathParameters['uid']!),
      ),
      GoRoute(path: '/partner-preferences', builder: (_, __) => const PartnerPreferencesScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/help', builder: (_, __) => const HelpSupportScreen()),
      GoRoute(path: '/privacy-policy', builder: (_, __) => const PrivacyPolicyScreen()),
      GoRoute(path: '/terms', builder: (_, __) => const TermsConditionsScreen()),
      // Dedicated Astrologer Verification queue (standalone full-screen page,
      // admin-gated by the /admin/ redirect; reached from the Dashboard and the
      // Astrologers list).
      GoRoute(
        path: '/admin/verification',
        builder: (_, __) => const AstrologerVerificationScreen(),
      ),
      // Admin
      ShellRoute(
        builder: (_, __, child) => AdminShell(child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, __) => const AdminDashboard()),
          // Users page → 2 tabs (Users / Astrologers) with plan-wise counts.
          GoRoute(
              path: '/admin/users',
              builder: (_, __) => const AdminUsersPage()),
          // Per-user details (Edit / Delete). Reached by tapping a user card.
          GoRoute(
              path: '/admin/user/:uid',
              builder: (_, state) =>
                  UserDetailsScreen(uid: state.pathParameters['uid'] ?? '')),
          // Full admin editor for a user's profile — details, horoscope,
          // contact, location, photo, Aadhaar verification, preferences.
          GoRoute(
              path: '/admin/user/:uid/edit',
              builder: (_, state) => AdminEditUserScreen(
                  uid: state.pathParameters['uid'] ?? '')),
          // Astrologers page → admin-provisioned account registry (add by
          // Gmail, enable/disable; Google-only login + auto-assignment).
          GoRoute(
              path: '/admin/astrologers',
              builder: (_, __) => const AstrologerAccountsScreen()),
          // Per-astrologer performance + details (View Details). The id is the
          // registry emailKey (URL-encoded when pushed).
          GoRoute(
              path: '/admin/astrologer-account/:id',
              builder: (_, state) => AstrologerDetailsScreen(
                  emailKey: state.pathParameters['id'] ?? '')),
          // Per-astrologer profile (Profile/Documents/Availability/Bookings/
          // Reviews/Payouts).
          GoRoute(
              path: '/admin/astrologer/:id',
              builder: (_, state) => AdminAstrologerProfileScreen(
                  astrologerId: state.pathParameters['id'] ?? '')),
          // Settlements & Payouts (astrologer payouts + refunds).
          GoRoute(
              path: '/admin/settlements',
              builder: (_, __) => const AdminSettlementsScreen()),
          // Horoscope Requests → astrologer match-analysis request queue.
          GoRoute(
              path: '/admin/horoscope-requests',
              builder: (_, __) => const AdminHoroscopeRequestsScreen()),
          // Appointment Management → all in-person astrology appointments.
          GoRoute(
              path: '/admin/appointments',
              builder: (_, __) => const AdminAppointmentsScreen()),
          GoRoute(path: '/admin/banners', builder: (_, __) => const BannerManagementScreen()),
          GoRoute(path: '/admin/notifications', builder: (_, __) => const AnnouncementManagementScreen()),
          GoRoute(path: '/admin/revenue-settings', builder: (_, __) => const RevenueSettingsScreen()),
          GoRoute(
              path: '/admin/astrology-service',
              builder: (_, __) => const AstrologyServiceSettingsScreen()),
          GoRoute(path: '/admin/analytics', builder: (_, __) => const AdminReportsPage()),
          GoRoute(path: '/admin/settings', builder: (_, __) => const AdminSettingsScreen()),
          // Force App Update configuration (version gate + Play Store link).
          GoRoute(
              path: '/admin/app-update',
              builder: (_, __) => const AppUpdateSettingsScreen()),
          GoRoute(path: '/admin/commission', builder: (_, __) => const EmployeeCommissionScreen()),
          GoRoute(path: '/admin/married', builder: (_, __) => const MarriedUsersScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) {
      // Debug log so a failing navigation is easy to spot in the console.
      debugPrint('[Router] ❌ ROUTE NOT FOUND → uri="${state.uri}" '
          'matchedLocation="${state.matchedLocation}" error=${state.error}');
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Page Not Found'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.explore_off_outlined,
                    size: 72, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text('Page Not Found',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('No screen is registered for:\n${state.uri}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Go to Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
});
