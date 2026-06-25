import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/config/dev_config.dart';
import '../providers/auth_provider.dart';
import '../providers/astrologer_session_provider.dart';
import '../providers/service_providers.dart';
import '../models/astrologer_request_model.dart';
import '../screens/astrologer/astrologer_dashboard_screen.dart';
import '../screens/astrologer/astrologer_login_screen.dart';
import '../screens/astrologer/astrologer_register_screen.dart';
import '../screens/astrologer/book_match_analysis_screen.dart';
import '../screens/astrologer/consultation_booking_screen.dart';
import '../screens/astrologer/my_consultations_screen.dart';
import '../screens/astrologer/astrologer_consultations_screen.dart';
import '../screens/astrologer/astrologer_earnings_screen.dart';
import '../screens/astrologer/profile/astrologer_bank_details_screen.dart';
import '../screens/astrologer/match_requests_screen.dart';
import '../screens/astrologer/match_workspace_screen.dart';
import '../screens/astrologer/my_match_analysis_screen.dart';
import '../screens/auth/account_type_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_creation_screen.dart';
import '../screens/profile/profile_success_screen.dart';
import '../screens/profile/profile_view_screen.dart';
import '../screens/match/match_details_screen.dart';
import '../screens/astrologer/astrologer_profile_screen.dart';
import '../screens/privacy/privacy_settings_screen.dart';
import '../screens/settings/language_screen.dart';
import '../screens/subscription/subscription_screen.dart';
import '../screens/admin/admin_shell.dart';
import '../screens/admin/admin_dashboard.dart';
import '../screens/admin/admin_users_page.dart';
import '../screens/admin/admin_astrologer_verification.dart';
import '../screens/admin/admin_horoscope_requests_screen.dart';
import '../screens/admin/admin_expired_bookings_screen.dart';
import '../screens/admin/astrologer_verification_screen.dart';
import '../screens/admin/admin_reports_screen.dart';
import '../screens/admin/admin_management_screens.dart';
import '../screens/admin/admin_reports_page.dart';
import '../screens/admin/account_admin_screens.dart';
import '../screens/admin/announcement_management_screen.dart';
import '../screens/horoscope/horoscope_details_screen.dart';
import '../screens/horoscope/horoscope_files_screen.dart';
import '../screens/horoscope/horoscope_matching_screen.dart';
import '../screens/horoscope/member_horoscope_screen.dart';
import '../screens/horoscope/horoscope_match_screen.dart';
import '../screens/profile/personal_details_screen.dart';
import '../screens/profile/payments_screen.dart';
import '../screens/profile/complete_profile_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/profile_section_edit_screens.dart';
import '../screens/profile/photos_edit_screen.dart';
import '../screens/family/family_tree_screen.dart';
import '../screens/family/family_details_screen.dart';
import '../screens/interests/interests_center_screen.dart';
import '../screens/preferences/partner_preferences_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/support/help_support_screen.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_conditions_screen.dart';
import '../screens/report/report_profile_screen.dart';
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
    initialLocation: '/',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onAuthPage = loc == '/account-type' ||
          loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot-password' ||
          loc == '/astrologer-login' ||
          loc.startsWith('/otp');
      final onSplash = loc == '/';

      // Astrologer portal has its OWN gate (login/signup before dashboard).
      // /astrologer-register is the first-time setup screen: pre-fills name,
      // email and photo from Google auth — never asks for credentials again.
      final inAstrologerPortal =
          loc == '/astrologer-register' || loc == '/astrologer-dashboard';
      if (inAstrologerPortal) {
        final onboarded = ref.read(isAstrologerOnboardedProvider);
        if (!onboarded && loc == '/astrologer-dashboard') {
          // In demo mode the astrologer signup creates the session locally; in
          // real mode the session is hydrated after Firebase login.
          return kBypassAuth ? '/astrologer-register' : '/astrologer-login';
        }
        if (onboarded && loc == '/astrologer-register') {
          return '/astrologer-dashboard';
        }
        return null;
      }

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
        return (onAuthPage || onSplash) ? null : '/account-type';
      }

      // Authenticated → route by role / onboarding status.
      final userAsync = ref.read(currentUserProvider);
      if (userAsync.isLoading) return null; // wait for the user doc to load
      final user = userAsync.valueOrNull;
      debugPrint('[Router] redirect check: loc=$loc, uid=${user?.uid}, '
          'role=${user?.role}, isAdmin=${user?.isAdmin}, '
          'isAstrologer=${user?.isAstrologer}, '
          'isProfileComplete=${user?.isProfileComplete}');

      // ── Admin route protection ───────────────────────────────────────────
      // Only 'admin' / 'super_admin' accounts may reach any /admin route.
      final onAdmin = loc == '/admin' || loc.startsWith('/admin/');
      if (onAdmin && !(user?.isAdmin ?? false)) {
        debugPrint('[Router] ⛔ non-admin blocked from "$loc" → /home');
        return '/home';
      }

      if (user != null && user.isAstrologer && (onAuthPage || loc == '/home')) {
        debugPrint('[Router] redirect: astrologer account → /astrologer-dashboard');
        return '/astrologer-dashboard';
      }
      if (onAuthPage) {
        // Only a *pure* admin account auto-lands on the dashboard. A
        // super_admin is a normal user with extra powers, so they land on Home
        // and open the dashboard via the header Admin icon.
        if (user?.role == 'admin') return '/admin';
        // Came from the astrologer portal's Google sign-in and isn't an
        // astrologer yet → go straight to astrologer profile setup, not the
        // matrimony profile wizard.
        if (loc == '/astrologer-login' &&
            user != null &&
            !user.isAstrologer &&
            !user.isProfileComplete) {
          debugPrint('[Router] redirect: astrologer Google sign-in → /astrologer-register');
          return '/astrologer-register';
        }
        // A pure admin account is exempt from onboarding; a super_admin is a
        // NORMAL matrimony user and onboards exactly like everyone else.
        if (user != null &&
            !user.isProfileComplete &&
            !user.isAstrologer &&
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
          !user.isAstrologer &&
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
      GoRoute(
          path: '/account-type', builder: (_, __) => const AccountTypeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/astrologer-login',
          builder: (_, __) => const AstrologerLoginScreen()),
      GoRoute(
          path: '/astrologer-register',
          builder: (_, __) => const AstrologerRegisterScreen()),
      GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) => ChatScreen(
          threadId: state.pathParameters['id']!,
          extra: state.extra as Map<String, dynamic>?,
        ),
      ),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return OtpScreen(
            verificationId: extra['verificationId'] as String,
            phone: extra['phone'] as String,
            isAstrologer: extra['isAstrologer'] == true,
          );
        },
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
      // Edit an existing profile (Profile → "Edit Profile"). 3 path segments so
      // it never collides with the 2-segment '/profile/:id' view route above.
      GoRoute(
        path: '/profile/:id/edit',
        builder: (_, state) =>
            ProfileCreationScreen(editProfileId: state.pathParameters['id']),
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
      // Astrologer portal (distinct prefix so it never collides with
      // '/astrologer/:id' above).
      GoRoute(
        path: '/astrologer-dashboard',
        builder: (_, __) => const AstrologerDashboardScreen(),
      ),
      GoRoute(
        path: '/astrologer/:id',
        builder: (_, state) =>
            AstrologerProfileScreen(astrologerId: state.pathParameters['id']!),
      ),
      // ── Match-analysis pipeline ──────────────────────────────────────────
      // User: book a porutham analysis (groom/bride from accepted matches).
      GoRoute(
        path: '/book-analysis/:id',
        builder: (_, state) =>
            BookMatchAnalysisScreen(astrologerId: state.pathParameters['id']!),
      ),
      // User: "My Match Analysis" (Pending / Accepted / Completed + reports).
      GoRoute(
          path: '/my-analysis', builder: (_, __) => const MyMatchAnalysisScreen()),
      // ── Consultation booking system (In-App + Direct Visit) ──────────────
      GoRoute(
        path: '/book-consultation/:id',
        builder: (_, state) =>
            ConsultationBookingScreen(astrologerId: state.pathParameters['id']!),
      ),
      // User: track consultations, pay after acceptance, read reports.
      GoRoute(
          path: '/my-consultations',
          builder: (_, __) => const MyConsultationsScreen()),
      // Astrologer: consultation requests inbox + lifecycle actions.
      GoRoute(
          path: '/consultation-requests',
          builder: (_, __) => const AstrologerConsultationsScreen()),
      // Astrologer: earnings dashboard + transaction history.
      GoRoute(
          path: '/astrologer-earnings',
          builder: (_, __) => const AstrologerEarningsScreen()),
      // Astrologer: payout bank account / UPI + flat fees.
      GoRoute(
          path: '/astrologer-bank-details',
          builder: (_, __) => const AstrologerBankDetailsScreen()),
      // Astrologer: dedicated Match Analysis Requests module
      // (Pending / Accepted / Completed).
      GoRoute(
        path: '/match-requests',
        builder: (_, __) => const MatchRequestsScreen(),
      ),
      // Astrologer: the analysis "Status" page / workspace for a request. The
      // request id is in the path so the page ALWAYS resolves the live request
      // (the optional `extra` snapshot only speeds up the first paint). This is
      // what makes "click Status → open the correct page" reliable even after a
      // restart / deep link. Distinct prefix so it never collides with
      // '/astrologer/:id'.
      GoRoute(
        path: '/match-workspace/:id',
        builder: (_, state) => MatchWorkspaceScreen(
          requestId: state.pathParameters['id']!,
          initialRequest: state.extra is AstrologerRequestModel
              ? state.extra as AstrologerRequestModel
              : null,
        ),
      ),
      GoRoute(path: '/subscription', builder: (_, __) => const SubscriptionScreen()),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacySettingsScreen()),
      GoRoute(path: '/language', builder: (_, __) => const LanguageScreen()),
      // ── Profile section screens ──────────────────────────────────────────
      // Profile Details (PROFILE group) — photo, name & all personal info.
      GoRoute(path: '/personal-details', builder: (_, __) => const PersonalDetailsScreen()),
      // Family Details (PROFILE group) — father/mother/siblings/type/status.
      GoRoute(path: '/family-details', builder: (_, __) => const FamilyDetailsScreen()),
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
      GoRoute(path: '/payments', builder: (_, __) => const PaymentsScreen()),
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
          GoRoute(path: '/admin/reports', builder: (_, __) => const AdminReportsScreen()),
          // Astrologers page → verification management ONLY.
          GoRoute(
              path: '/admin/astrologers',
              builder: (_, __) => const AdminAstrologerVerificationView()),
          // Horoscope Requests → astrologer match-analysis request queue.
          GoRoute(
              path: '/admin/horoscope-requests',
              builder: (_, __) => const AdminHoroscopeRequestsScreen()),
          // Expired Bookings → reassign bookings whose astrologer didn't respond.
          GoRoute(
              path: '/admin/expired-bookings',
              builder: (_, __) => const AdminExpiredBookingsScreen()),
          GoRoute(path: '/admin/ratings', builder: (_, __) => const RatingManagementScreen()),
          GoRoute(path: '/admin/banners', builder: (_, __) => const BannerManagementScreen()),
          GoRoute(path: '/admin/notifications', builder: (_, __) => const AnnouncementManagementScreen()),
          GoRoute(path: '/admin/premium', builder: (_, __) => const PremiumManagementScreen()),
          GoRoute(path: '/admin/revenue-settings', builder: (_, __) => const RevenueSettingsScreen()),
          GoRoute(path: '/admin/analytics', builder: (_, __) => const AdminReportsPage()),
          GoRoute(path: '/admin/settings', builder: (_, __) => const AdminSettingsScreen()),
          GoRoute(path: '/admin/married', builder: (_, __) => const MarriedUsersScreen()),
          GoRoute(path: '/admin/deletion-requests', builder: (_, __) => const AccountDeletionRequestsScreen()),
          GoRoute(path: '/admin/support', builder: (_, __) => const SupportTicketsScreen()),
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
