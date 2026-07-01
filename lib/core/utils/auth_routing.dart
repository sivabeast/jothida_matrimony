import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';

/// Shared post-sign-in routing logic, used by every auth entry point
/// (Google, Phone OTP). This is the SINGLE common login — the user's role is
/// auto-detected here and they are redirected accordingly; nobody picks a role.
///
///  • Employee (horoscope-analysis staff, registered in the `astrology_team`
///    registry) → Employee Portal.
///  • Internal astrology account → Astrology Dashboard.
///  • Pure admin → Admin panel. (A super_admin is a normal user with an extra
///    Admin icon and falls through to the user flow.)
///  • Everyone else → onboarding (if incomplete) or Home.
Future<void> routeAuthenticatedUser(
  BuildContext context,
  WidgetRef ref,
  UserModel user, {
  String tag = 'Auth',
}) async {
  debugPrint('[$tag] routeAuthenticatedUser: uid=${user.uid}, role=${user.role}, '
      'isAdmin=${user.isAdmin}, isInternalAstrology=${user.isInternalAstrology}, '
      'isProfileComplete=${user.isProfileComplete}');

  // ── Employee (horoscope-analysis staff) auto-detection ──────────────────
  // A Gmail the admin has registered in the astrology_team registry opens the
  // Employee Portal. Admins / the internal astrology account are never treated
  // as employees. This links the uid + flags the `astrologer` role on first
  // sign-in so the router gates them to the portal on every future launch.
  final email = user.email;
  final alreadyEmployee = user.isAstrologer; // returning employee
  if (!user.isAdmin && !user.isInternalAstrology) {
    if (alreadyEmployee) {
      debugPrint('[$tag] routeAuthenticatedUser: employee → /astrologer-dashboard');
      context.go('/astrologer-dashboard');
      return;
    }
    if (email != null && email.trim().isNotEmpty) {
      try {
        final team = ref.read(astrologyTeamServiceProvider);
        final member = await team.getByEmail(email);
        if (member != null && member.active) {
          await team.linkUid(
            member.id,
            uid: user.uid,
            displayName: user.displayName ?? '',
            photoUrl: user.photoUrl ?? '',
          );
          await team.promoteToAstrologerRole(user.uid);
          // Wait for the refreshed user doc (role) so the router gates correctly.
          ref.invalidate(currentUserProvider);
          await ref.read(currentUserProvider.future);
          if (!context.mounted) return;
          debugPrint('[$tag] routeAuthenticatedUser: new employee → '
              '/astrologer-dashboard');
          context.go('/astrologer-dashboard');
          return;
        }
      } catch (e) {
        debugPrint('[$tag] employee registry check failed (non-fatal): $e');
        // Fall through to normal routing.
      }
    }
  }

  if (!context.mounted) return;

  if (user.isInternalAstrology) {
    debugPrint('[$tag] routeAuthenticatedUser: internal astrology → /astrology');
    context.go('/astrology');
  } else if (user.role == 'admin') {
    // Pure admin only. A super_admin is a normal matrimony user (with an extra
    // Admin icon in the header) and falls through to the normal user flow.
    debugPrint('[$tag] routeAuthenticatedUser: admin account → /admin');
    context.go('/admin');
  } else if (!user.isProfileComplete) {
    debugPrint('[$tag] routeAuthenticatedUser: profile incomplete → '
        '/profile/create');
    context.go('/profile/create');
  } else {
    debugPrint('[$tag] routeAuthenticatedUser: profile complete → /home');
    context.go('/home');
  }
}
