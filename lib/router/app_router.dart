import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/config/dev_config.dart';
import '../core/navigation/root_navigator.dart';
import '../core/utils/member_access.dart';
import '../providers/auth_provider.dart';
import '../providers/service_providers.dart';
import 'auth_redirect.dart';
import '../models/astrologer_request_model.dart';
import '../screens/astrology/horoscope_report_service_screen.dart';
import '../screens/astrology/astrology_appointment_screen.dart';
import '../screens/astrology/appointment_confirmation_screen.dart';
import '../screens/astrology/my_appointments_screen.dart';
import '../screens/astrologer/match_workspace_screen.dart';
// Employee Portal (admin-provisioned horoscope-analysis staff; they sign in
// through the SAME common login as everyone else — there is no separate
// employee/astrologer login).
import '../screens/astrologer/portal/astrologer_shell.dart';
import '../screens/astrologer/portal/astrologer_notifications_page.dart';
import '../screens/report/report_request_detail_page.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_required_screen.dart';
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
import '../screens/admin/admin_horoscope_requests_screen.dart';
import '../screens/admin/admin_appointments_screen.dart';
import '../screens/admin/admin_activity_log_screen.dart';
import '../screens/admin/admin_approvals_screen.dart';
import '../screens/admin/admin_payments_screen.dart';
import '../screens/admin/admin_reports_page.dart';
import '../screens/admin/admin_report_management_screen.dart';
import '../screens/admin/admin_test_data_screen.dart';
import '../screens/admin/employee_commission_screen.dart';
import '../screens/admin/account_admin_screens.dart';
import '../screens/admin/announcement_management_screen.dart';
import '../screens/admin/banner_management_screen.dart';
import '../screens/horoscope/horoscope_details_screen.dart';
import '../screens/horoscope/horoscope_files_screen.dart';
import '../screens/horoscope/member_horoscope_screen.dart';
import '../screens/profile/personal_details_screen.dart';
import '../screens/profile/complete_profile_screen.dart';
import '../providers/navigation_provider.dart';
import '../screens/notifications/announcement_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/profile_section_edit_screens.dart';
import '../screens/profile/photos_edit_screen.dart';
import '../screens/interests/interests_center_screen.dart';
import '../screens/preferences/partner_preferences_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/moderation/blocked_users_screen.dart';
import '../screens/moderation/reported_users_screen.dart';
import '../screens/support/help_support_screen.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_conditions_screen.dart';
import '../screens/legal/child_safety_screen.dart';
import '../screens/legal/delete_account_screen.dart';
import '../screens/report/report_profile_screen.dart';
import '../screens/report/report_chat_screen.dart';
import '../screens/report/request_external_report_screen.dart';
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

  /// Re-runs `redirect` for the current location. `notifyListeners` is
  /// `@protected`, so external triggers (the user-document listener below) go
  /// through this.
  void refresh() => notifyListeners();

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

  // Firebase authentication and the Firestore user document land at *different*
  // times: `authStateChanges` fires the instant the credential is accepted,
  // while `redirect` needs `users/{uid}` to decide where the account belongs.
  // Without this listener the redirect that runs on sign-in always sees
  // `isLoading`, bails out with `null`, and is never re-run — leaving the user
  // wherever they were (the login screen, still spinning) unless some other
  // code path happens to navigate. Re-running `redirect` when the document
  // resolves makes the router self-correcting: sign-in alone is enough to land
  // on the right screen.
  ref.listen(currentUserProvider, (previous, next) {
    if (next.isLoading) return;
    debugPrint('[Router] user document resolved '
        '(uid=${next.valueOrNull?.uid}, hasError=${next.hasError}) '
        '— refreshing router');
    refreshStream.refresh();
  });

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      // The decision itself lives in `resolveAuthRedirect` (pure, unit-tested);
      // this callback only gathers the current auth state.
      //
      // IMPORTANT: do NOT use `ref.read(firebaseAuthStreamProvider)` for
      // `isAuthenticated`. `GoRouterRefreshStream` and the StreamProvider both
      // subscribe to the same Firebase authStateChanges stream. When signOut()
      // fires, this redirect runs (via notifyListeners) BEFORE the
      // StreamProvider has processed the null event — so it would still see the
      // old user and incorrectly return null (no redirect). `currentUser` is
      // read synchronously from Firebase and is always immediately accurate.
      final userAsync = ref.read(currentUserProvider);
      final pendingReturn = ref.read(pendingReturnRouteProvider);
      final decision = resolveAuthRedirect(
        location: state.matchedLocation,
        bypassAuth: kBypassAuth,
        isAuthenticated: ref.read(authRepositoryProvider).currentUser != null,
        // Read straight from Firebase for the same reason as isAuthenticated:
        // it is always immediately accurate, unlike a StreamProvider that may
        // not have processed the latest auth event yet.
        isGuest: ref.read(authRepositoryProvider).isGuest,
        userDocLoading: userAsync.isLoading,
        user: userAsync.valueOrNull,
        familyLoginInProgress: ref.read(familyLoginInProgressProvider),
        pendingReturnRoute: pendingReturn,
        log: (m) => debugPrint('[Router] $m'),
      );
      // A consumed return-route must not fire again on the next redirect.
      // Cleared out-of-band so the redirect callback itself stays side-effect
      // free for GoRouter's synchronous evaluation.
      if (pendingReturn != null && decision == pendingReturn) {
        Future.microtask(
            () => ref.read(pendingReturnRouteProvider.notifier).state = null);
      }
      return decision;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      // Where Guest Mode sends anything personalized (§6). `?returnTo=` carries
      // the blocked location so signing in lands the member straight back on
      // it instead of Home (§15).
      GoRoute(
          path: '/login-required',
          builder: (_, state) => LoginRequiredScreen(
              returnTo: state.uri.queryParameters['returnTo'])),
      // ── Employee Portal (admin-provisioned staff; common login only) ─────
      GoRoute(
          path: '/astrologer-dashboard',
          builder: (_, __) => const AstrologerShell()),
      GoRoute(
          path: '/astrologer-notifications',
          builder: (_, __) => const AstrologerNotificationsPage()),
      // One assigned report request in the Employee Portal — the SAME detail
      // page the admin opens (§3).
      GoRoute(
        path: '/astrologer-request/:id',
        builder: (_, state) => ReportRequestDetailPage(
          requestId: state.pathParameters['id']!,
          initial: state.extra is AstrologerRequestModel
              ? state.extra as AstrologerRequestModel
              : null,
        ),
      ),
      // Chat is member-only (§7) — gated at the route so deep links and
      // notification taps go through the same check as an in-app tap.
      GoRoute(
        path: '/chats',
        builder: (_, __) => const MemberGate(
          feature: MemberFeature.chat,
          returnTo: '/chats',
          child: ChatListScreen(),
        ),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) => MemberGate(
          feature: MemberFeature.chat,
          returnTo: state.uri.toString(),
          child: ChatScreen(
            threadId: state.pathParameters['id']!,
            extra: state.extra as Map<String, dynamic>?,
          ),
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
      // Member profiles are the core member-only surface (§6/§7): wrapping the
      // ROUTE gates every way in — a card tap, a deep link, a notification tap
      // or a restored session — in one place.
      GoRoute(
        path: '/profile/:id',
        builder: (_, state) => MemberGate(
          feature: MemberFeature.viewProfiles,
          returnTo: state.uri.toString(),
          child:
              ProfileViewScreen(profileId: state.pathParameters['id']!),
        ),
      ),
      // Open a profile by the owner's USER id (UID). Used from accepted
      // interests, where senderId / receiverId is the reliable key — never an
      // interest-document id. Distinct path prefix so it can't collide with the
      // '/profile/:id' document-id route above.
      GoRoute(
        path: '/profile-user/:uid',
        builder: (_, state) => MemberGate(
          feature: MemberFeature.viewProfiles,
          returnTo: state.uri.toString(),
          child: ProfileViewScreen(userId: state.pathParameters['uid']!),
        ),
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
      // Report a profile (from the profile view screen).
      GoRoute(
        path: '/report/:id',
        builder: (_, state) =>
            ReportProfileScreen(profileId: state.pathParameters['id']!),
      ),
      // Report a chat conversation (spec §7). `extra` carries otherUid + name.
      GoRoute(
        path: '/report-chat/:threadId',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return ReportChatScreen(
            threadId: state.pathParameters['threadId']!,
            otherUid: extra['otherUid'] as String? ?? '',
            otherName: extra['otherName'] as String? ?? 'User',
          );
        },
      ),
      // ── Horoscope Compatibility Report (in-person appointment) ───────────
      // Service details page → appointment booking → confirmation. Opened from
      // an accepted match's "Get Horoscope Compatibility Report".
      GoRoute(
        path: '/horoscope-report/:userId',
        builder: (_, state) => HoroscopeReportServiceScreen(
            otherUserId: state.pathParameters['userId']!),
      ),
      // ── Request New Horoscope Report (external, spec §4) ─────────────────
      // A compatibility report between the signed-in user and a person who is
      // NOT registered in the app. Opened from the Reports tab.
      GoRoute(
        path: '/request-external-report',
        builder: (_, __) => const RequestExternalReportScreen(),
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
      // ?tab=sent|received|accepted|rejected selects the opening tab and
      // ?highlight=<uid> scrolls to + flashes that counterpart's card — used
      // by notification deep links so the triggering profile is unmistakable.
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
          return MemberGate(
            feature: MemberFeature.sendInterest,
            returnTo: state.uri.toString(),
            child: InterestsCenterScreen(
              initialTab: idx,
              standalone: true,
              highlightUid: state.uri.queryParameters['highlight'],
            ),
          );
        },
      ),
      GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen()),
      // Direct destination of announcement notification taps — there is NO
      // generic notification-details page.
      GoRoute(
        path: '/announcement/:id',
        builder: (_, state) =>
            AnnouncementScreen(announcementId: state.pathParameters['id']!),
      ),
      // Reports deep link (push-notification taps; legacy '/my-analysis'
      // documents too). The reports list lives ONLY on the Home bottom-nav
      // tab, so select that tab and land on /home instead of 404-ing.
      GoRoute(
        path: '/reports',
        redirect: (_, __) {
          ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
          return '/home';
        },
      ),
      GoRoute(
        path: '/my-analysis',
        redirect: (_, __) {
          ref.read(homeTabIndexProvider.notifier).state = kReportsTabIndex;
          return '/home';
        },
      ),
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
          path: '/edit/lifestyle',
          builder: (_, __) => const LifestyleEditScreen()),
      GoRoute(
          path: '/edit/photos', builder: (_, __) => const PhotosEditScreen()),
      GoRoute(path: '/horoscope', builder: (_, __) => const HoroscopeDetailsScreen()),
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
      // Legacy alias: the separate "Horoscope Match Result" page was merged
      // into the ONE Horoscope Compatibility Report page, which now shows the
      // free porutham result and the paid request together.
      GoRoute(
        path: '/horoscope-match/:uid',
        redirect: (_, state) =>
            '/horoscope-report/${state.pathParameters['uid']}',
      ),
      GoRoute(path: '/partner-preferences', builder: (_, __) => const PartnerPreferencesScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      // Safety / moderation (spec §6–§7): user-facing Blocked & Reported lists.
      GoRoute(
          path: '/blocked-users',
          builder: (_, __) => const BlockedUsersScreen()),
      GoRoute(
          path: '/reported-users',
          builder: (_, __) => const ReportedUsersScreen()),
      GoRoute(path: '/help', builder: (_, __) => const HelpSupportScreen()),
      GoRoute(path: '/privacy-policy', builder: (_, __) => const PrivacyPolicyScreen()),
      GoRoute(path: '/terms', builder: (_, __) => const TermsConditionsScreen()),
      // Website pages imported into the app (§14).
      GoRoute(
          path: '/child-safety', builder: (_, __) => const ChildSafetyScreen()),
      GoRoute(
          path: '/delete-account',
          builder: (_, __) => const DeleteAccountScreen()),
      // One report request — Groom / Bride / Horoscope details + Fill Report.
      // The SAME page the employee portal opens ('/astrologer-request/:id').
      //
      // Registered OUTSIDE the admin ShellRoute deliberately: it carries its
      // own AppBar, and nesting it in the shell would stack two. Still
      // admin-gated, by the '/admin/' rule in resolveAuthRedirect.
      GoRoute(
        path: '/admin/request/:id',
        builder: (_, state) => ReportRequestDetailPage(
          requestId: state.pathParameters['id']!,
          initial: state.extra is AstrologerRequestModel
              ? state.extra as AstrologerRequestModel
              : null,
          admin: true,
        ),
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
          // "Create Profiles" — the admin fills in the SAME profile-creation
          // wizard on a member's behalf, then a final Login Credentials step
          // creates the member's login. One shared flow, no duplicate form.
          GoRoute(
              path: '/admin/create-profile',
              builder: (_, __) =>
                  const ProfileCreationScreen(adminMode: true)),
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
          // Paid transactions — every astrologer_requests booking with
          // paid == true (drawer → Payments → Transactions).
          GoRoute(
              path: '/admin/payments',
              builder: (_, __) => const AdminPaymentsScreen()),
          // Requests → horoscope REPORT request queue (Pending / Completed).
          // Astrology appointments are a separate module (§4).
          GoRoute(
              path: '/admin/horoscope-requests',
              builder: (_, __) => const AdminHoroscopeRequestsScreen()),
          // Appointment Management → all in-person astrology appointments.
          GoRoute(
              path: '/admin/appointments',
              builder: (_, __) => const AdminAppointmentsScreen()),
          GoRoute(path: '/admin/banners', builder: (_, __) => const BannerManagementScreen()),
          GoRoute(path: '/admin/notifications', builder: (_, __) => const AnnouncementManagementScreen()),
          GoRoute(
              path: '/admin/astrology-service',
              builder: (_, __) => const AstrologyServiceSettingsScreen()),
          GoRoute(path: '/admin/analytics', builder: (_, __) => const AdminReportsPage()),
          GoRoute(path: '/admin/commission', builder: (_, __) => const EmployeeCommissionScreen()),
          GoRoute(path: '/admin/married', builder: (_, __) => const MarriedUsersScreen()),
          GoRoute(path: '/admin/test-data', builder: (_, __) => const AdminTestDataScreen()),
          GoRoute(path: '/admin/reports', builder: (_, __) => const AdminReportManagementScreen()),
          // Profile approval queue — self-registered profiles wait here until
          // an admin approves/rejects them (approval workflow).
          GoRoute(
              path: '/admin/approvals',
              builder: (_, __) => const AdminApprovalsScreen()),
          // Immutable audit trail of admin actions.
          GoRoute(
              path: '/admin/activity-log',
              builder: (_, __) => const AdminActivityLogScreen()),
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
