import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../providers/astrologer_session_provider.dart';

/// Shared post-sign-in routing logic, used by every auth entry point
/// (Google, Phone OTP, Email/Password login, Email/Password register).
///
/// New accounts (and any account that hasn't finished the matrimony
/// profile yet) are sent to the profile-creation/onboarding flow first;
/// returning users with a completed profile go straight to their normal
/// screen (Home, Astrologer Dashboard, or Admin).
Future<void> routeAuthenticatedUser(
  BuildContext context,
  WidgetRef ref,
  UserModel user, {
  String tag = 'Auth',
}) async {
  debugPrint('[$tag] routeAuthenticatedUser: uid=${user.uid}, '
      'isAdmin=${user.isAdmin}, isAstrologer=${user.isAstrologer}, '
      'isProfileComplete=${user.isProfileComplete}');

  if (user.isAstrologer) {
    debugPrint('[$tag] routeAuthenticatedUser: astrologer account → '
        'hydrating astrologer session...');
    // Time-bound the Firestore hydration so a slow/offline read can't leave the
    // caller awaiting forever (the login button keeps its spinner until this
    // returns). On timeout/error we log and still navigate — the dashboard gate
    // will redirect to /astrologer-login if the session truly couldn't load,
    // which is recoverable, rather than freezing on an eternal spinner.
    try {
      await ref
          .read(myAstrologerAccountProvider.notifier)
          .loadFromFirestore(user.uid)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[$tag] routeAuthenticatedUser: astrologer hydration '
          'failed (continuing): $e');
    }
    if (context.mounted) {
      debugPrint('[$tag] routeAuthenticatedUser: → /astrologer-dashboard');
      context.go('/astrologer-dashboard');
    }
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
