import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/config/dev_config.dart';
import '../providers/auth_provider.dart';
import '../providers/astrologer_session_provider.dart';
import '../providers/service_providers.dart';
import '../screens/astrologer/astrologer_onboarding_screen.dart';
import '../screens/astrologer/astrologer_dashboard_screen.dart';
import '../screens/astrologer/astrologer_login_screen.dart';
import '../screens/astrologer/astrologer_register_screen.dart';
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
import '../screens/profile/profile_view_screen.dart';
import '../screens/match/match_details_screen.dart';
import '../screens/astrologer/astrologer_profile_screen.dart';
import '../screens/privacy/privacy_settings_screen.dart';
import '../screens/settings/language_screen.dart';
import '../screens/subscription/subscription_screen.dart';
import '../screens/admin/admin_shell.dart';
import '../screens/admin/admin_dashboard.dart';
import '../screens/admin/admin_users_screen.dart';
import '../screens/admin/admin_approvals_screen.dart';
import '../screens/admin/admin_reports_screen.dart';

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

      // After Google sign-in, an astrologer-to-be (role still 'user',
      // matrimony profile incomplete) lands here to fill in astrologer-only
      // details. Don't bounce them to the matrimony /profile/create wizard.
      final onAstrologerProfileSetup = loc == '/astrologer-register';

      // Astrologer portal has its OWN gate (login/signup before dashboard).
      final inAstrologerPortal =
          loc == '/astrologer-onboarding' || loc == '/astrologer-dashboard';
      if (inAstrologerPortal) {
        final onboarded = ref.read(isAstrologerOnboardedProvider);
        if (!onboarded && loc == '/astrologer-dashboard') {
          // In demo mode the astrologer signup creates the session locally; in
          // real mode the session is hydrated after Firebase login.
          return kBypassAuth ? '/astrologer-onboarding' : '/astrologer-login';
        }
        if (onboarded && loc == '/astrologer-onboarding') {
          return '/astrologer-dashboard';
        }
        return null;
      }

      // ── Demo mode (kBypassAuth): everything reachable, Home shows the
      // profile-completion card instead of force-redirecting. ──
      if (kBypassAuth) return null;

      // ── Real auth path ──
      final authState = ref.read(firebaseAuthStreamProvider);
      final isAuthenticated = authState.valueOrNull != null;
      if (!isAuthenticated) {
        return (onAuthPage || onSplash) ? null : '/account-type';
      }

      // Authenticated → route by role / onboarding status.
      final userAsync = ref.read(currentUserProvider);
      if (userAsync.isLoading) return null; // wait for the user doc to load
      final user = userAsync.valueOrNull;
      debugPrint('[Router] redirect check: loc=$loc, uid=${user?.uid}, '
          'isAdmin=${user?.isAdmin}, isAstrologer=${user?.isAstrologer}, '
          'isProfileComplete=${user?.isProfileComplete}');

      if (user != null && user.isAstrologer && (onAuthPage || loc == '/home')) {
        debugPrint('[Router] redirect: astrologer account → /astrologer-dashboard');
        return '/astrologer-dashboard';
      }
      if (onAuthPage) {
        if (user?.isAdmin == true) return '/admin';
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
        if (user != null && !user.isProfileComplete && !user.isAstrologer) {
          debugPrint('[Router] redirect: profile incomplete → /profile/create');
          return '/profile/create';
        }
        return '/home';
      }

      // Authenticated user with an incomplete profile must finish onboarding
      // before reaching any other authenticated screen (Home, chats, etc.).
      final onProfileCreate = loc == '/profile/create';
      if (user != null &&
          !user.isAdmin &&
          !user.isAstrologer &&
          !user.isProfileComplete &&
          !onProfileCreate &&
          !onAstrologerProfileSetup &&
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
          );
        },
      ),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/profile/create', builder: (_, __) => const ProfileCreationScreen()),
      GoRoute(
        path: '/profile/:id',
        builder: (_, state) => ProfileViewScreen(profileId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/match/:id',
        builder: (_, state) =>
            MatchDetailsScreen(profileId: state.pathParameters['id']!),
      ),
      // Astrologer portal (distinct prefix so it never collides with
      // '/astrologer/:id' above).
      GoRoute(
        path: '/astrologer-onboarding',
        builder: (_, __) => const AstrologerOnboardingScreen(),
      ),
      GoRoute(
        path: '/astrologer-dashboard',
        builder: (_, __) => const AstrologerDashboardScreen(),
      ),
      GoRoute(
        path: '/astrologer/:id',
        builder: (_, state) =>
            AstrologerProfileScreen(astrologerId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/subscription', builder: (_, __) => const SubscriptionScreen()),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacySettingsScreen()),
      GoRoute(path: '/language', builder: (_, __) => const LanguageScreen()),
      // Admin
      ShellRoute(
        builder: (_, __, child) => AdminShell(child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, __) => const AdminDashboard()),
          GoRoute(path: '/admin/users', builder: (_, __) => const AdminUsersScreen()),
          GoRoute(path: '/admin/approvals', builder: (_, __) => const AdminApprovalsScreen()),
          GoRoute(path: '/admin/reports', builder: (_, __) => const AdminReportsScreen()),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.error}')),
    ),
  );
});
