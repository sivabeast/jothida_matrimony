import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/config/dev_config.dart';
import '../providers/auth_provider.dart';
import '../providers/demo_data_provider.dart';
import '../providers/astrologer_session_provider.dart';
import '../screens/astrologer/astrologer_onboarding_screen.dart';
import '../screens/astrologer/astrologer_dashboard_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
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
import '../screens/porutham/porutham_screen.dart';
import '../screens/admin/admin_shell.dart';
import '../screens/admin/admin_dashboard.dart';
import '../screens/admin/admin_users_screen.dart';
import '../screens/admin/admin_approvals_screen.dart';
import '../screens/admin/admin_reports_screen.dart';
import '../screens/admin/admin_poruthams_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(firebaseAuthStreamProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onAuthPage = loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot-password' ||
          loc.startsWith('/otp');
      final onSplash = loc == '/';
      final onProfileCreate = loc == '/profile/create';

      // Astrologer portal has its OWN gate (onboarding before dashboard) and is
      // exempt from the matrimony profile gate.
      final inAstrologerPortal =
          loc == '/astrologer-onboarding' || loc == '/astrologer-dashboard';
      if (inAstrologerPortal) {
        final onboarded = ref.read(isAstrologerOnboardedProvider);
        if (!onboarded && loc == '/astrologer-dashboard') {
          return '/astrologer-onboarding';
        }
        if (onboarded && loc == '/astrologer-onboarding') {
          return '/astrologer-dashboard';
        }
        return null;
      }

      // ── Demo mode (kBypassAuth): gate Home behind profile completion ──
      // No user can reach Discover/Requests/Matches/etc. until their profile
      // is created. profileCompleted == (a demo profile exists).
      if (kBypassAuth) {
        final profileCompleted = ref.read(myDemoProfileIdProvider) != null;
        if (!profileCompleted && !onProfileCreate && !onAuthPage && !onSplash) {
          return '/profile/create';
        }
        return null;
      }

      // ── Real auth path ──
      final isAuthenticated = authState.valueOrNull != null;
      if (!isAuthenticated) {
        return (onAuthPage || onSplash) ? null : '/login';
      }

      // Authenticated → enforce profileCompleted (users/{uid}.isProfileComplete).
      final userAsync = ref.read(currentUserProvider);
      if (userAsync.isLoading) return null; // wait for the profile to load
      final profileCompleted = userAsync.valueOrNull?.isProfileComplete ?? false;
      if (!profileCompleted && !onProfileCreate && !onSplash) {
        return '/profile/create';
      }
      if (profileCompleted && onAuthPage) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
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
      GoRoute(path: '/porutham', builder: (_, __) => const PoruthamsScreen()),
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
          GoRoute(path: '/admin/poruthams', builder: (_, __) => const AdminPoruthamsScreen()),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.error}')),
    ),
  );
});
