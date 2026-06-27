import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';

/// Shared post-sign-in routing logic, used by every auth entry point
/// (Google, Phone OTP).
///
/// New accounts (and any account that hasn't finished the matrimony
/// profile yet) are sent to the profile-creation/onboarding flow first;
/// returning users with a completed profile go straight to their normal
/// screen (Home or Admin). The dedicated internal astrology account skips the
/// matrimony experience entirely and lands on the Astrology Dashboard.
Future<void> routeAuthenticatedUser(
  BuildContext context,
  WidgetRef ref,
  UserModel user, {
  String tag = 'Auth',
}) async {
  debugPrint('[$tag] routeAuthenticatedUser: uid=${user.uid}, '
      'isAdmin=${user.isAdmin}, isInternalAstrology=${user.isInternalAstrology}, '
      'isProfileComplete=${user.isProfileComplete}');

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
