import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../theme/app_colors.dart';

/// The gate every MEMBER-ONLY feature goes through (spec §6 / §7 / §15).
///
/// A feature in this group needs BOTH:
///   1. a real (non-guest) login, and
///   2. a completed matrimony profile.
///
/// The group is: View Profiles · Send Interest · Matches · Chat · Horoscope
/// Report Requests. Everything else — Home, banners, memberships, astrology
/// services, public content, and astrology APPOINTMENT booking (§8, which needs
/// login only) — stays reachable without a matrimony profile.
enum MemberFeature {
  viewProfiles,
  sendInterest,
  matches,
  chat,
  reportRequest,
}

extension on MemberFeature {
  /// The Tamil message shown when the visitor has no completed matrimony
  /// profile. Wording for [viewProfiles] and [reportRequest] is fixed by the
  /// spec and must not be paraphrased.
  String get profileMessage {
    switch (this) {
      case MemberFeature.viewProfiles:
        return 'மற்ற உறுப்பினர்களின் Profile-களை பார்க்க, முதலில் உங்கள் '
            'Matrimony Profile-ஐ உருவாக்குங்கள்.';
      case MemberFeature.reportRequest:
        return 'Compatibility Report Request அனுப்ப உங்கள் Matrimony Profile-ஐ '
            'முதலில் Complete செய்ய வேண்டும்.';
      case MemberFeature.sendInterest:
        return 'விருப்பம் அனுப்ப உங்கள் Matrimony Profile-ஐ முதலில் Complete '
            'செய்ய வேண்டும்.';
      case MemberFeature.matches:
        return 'உங்களுக்கான Matches பார்க்க உங்கள் Matrimony Profile-ஐ முதலில் '
            'Complete செய்ய வேண்டும்.';
      case MemberFeature.chat:
        return 'Chat செய்ய உங்கள் Matrimony Profile-ஐ முதலில் Complete '
            'செய்ய வேண்டும்.';
    }
  }
}

/// Where the member is sent to finish onboarding: the creation wizard when
/// there is no profile document at all, otherwise the section-by-section
/// Complete Profile screen.
String _completionRoute({required bool hasProfile}) =>
    hasProfile ? '/complete-profile' : '/profile/create';

/// True when [ref] currently has a signed-in, non-guest account whose matrimony
/// profile is complete.
bool hasMemberAccess(WidgetRef ref) {
  if (ref.read(isGuestProvider)) return false;
  final user = ref.read(currentUserProvider).valueOrNull;
  if (user == null) return false;
  final profile = ref.read(myProfileProvider).valueOrNull;
  return profile != null && user.isProfileComplete;
}

/// Gates [feature]. Returns true when the caller may proceed.
///
/// When it returns false it has ALREADY told the user why and offered the one
/// action that fixes it:
///   • not logged in (or browsing as a guest) → the Login Required screen,
///     which returns to where they were after a successful sign-in;
///   • logged in but no completed matrimony profile → a sheet carrying the
///     spec's Tamil message and a **Complete Profile** button.
///
/// [returnTo] is the location to come back to once the blocker is resolved;
/// pass the route the user was trying to reach so they land there instead of
/// on Home.
Future<bool> requireMemberAccess(
  BuildContext context,
  WidgetRef ref,
  MemberFeature feature, {
  String? returnTo,
}) async {
  // ── 1. Login ──────────────────────────────────────────────────────────────
  final signedIn = ref.read(authRepositoryProvider).currentUser != null &&
      !ref.read(isGuestProvider);
  if (!signedIn) {
    final target = returnTo == null ? '' : '?returnTo=${Uri.encodeComponent(returnTo)}';
    context.push('/login-required$target');
    return false;
  }

  // ── 2. Completed matrimony profile ────────────────────────────────────────
  final user = ref.read(currentUserProvider).valueOrNull;
  final profile = ref.read(myProfileProvider).valueOrNull;
  final complete = profile != null && (user?.isProfileComplete ?? false);
  if (complete) return true;

  await showCompleteProfileSheet(
    context,
    message: feature.profileMessage,
    route: _completionRoute(hasProfile: profile != null),
    returnTo: returnTo,
  );
  return false;
}

/// Wraps a MEMBER-ONLY route so EVERY way in is gated — a card tap, a deep
/// link, a push-notification tap or a restored session (spec §6/§7).
///
/// Renders [child] only when the visitor is a signed-in member with a
/// completed matrimony profile. Otherwise it renders the blocking page itself
/// (rather than redirecting), so the reason is always visible and the single
/// fix — Login, or Complete Profile — is one tap away.
class MemberGate extends ConsumerWidget {
  final MemberFeature feature;

  /// Location to come back to after signing in.
  final String returnTo;

  final Widget child;

  const MemberGate({
    super.key,
    required this.feature,
    required this.returnTo,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching (not reading) means the gate opens by itself the moment the
    // member signs in or finishes their profile.
    final guest = ref.watch(isGuestProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final profileAsync = ref.watch(myProfileProvider);

    if (guest || user == null) {
      return _BlockedPage(
        icon: Icons.lock_outline,
        message: feature.profileMessage,
        actionLabel: 'Login / Register',
        onAction: () {
          ref.read(pendingReturnRouteProvider.notifier).state = returnTo;
          context.go('/login');
        },
      );
    }

    // Wait for the profile read before deciding — otherwise a member with a
    // complete profile sees the blocker flash on every cold open.
    if (profileAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final profile = profileAsync.valueOrNull;
    if (profile == null || !user.isProfileComplete) {
      return _BlockedPage(
        icon: Icons.badge_outlined,
        message: feature.profileMessage,
        actionLabel: 'Complete Profile',
        onAction: () =>
            context.push(_completionRoute(hasProfile: profile != null)),
      );
    }

    return child;
  }
}

/// Full-screen "you can't do this yet" page used by [MemberGate].
class _BlockedPage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _BlockedPage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.26),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 44, color: Colors.white),
                ),
                const SizedBox(height: 26),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, height: 1.6, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    label: Text(actionLabel,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home_outlined, size: 19),
                  label: const Text('Back to Home'),
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "complete your matrimony profile first" bottom sheet: the Tamil
/// explanation plus a single **Complete Profile** action.
///
/// [returnTo] is appended to the onboarding route as `?returnTo=…` so the
/// wizard can bring the member straight back to the page they wanted once the
/// profile is finished.
Future<void> showCompleteProfileSheet(
  BuildContext context, {
  required String message,
  required String route,
  String? returnTo,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.badge_outlined,
                  size: 34, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, height: 1.55, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  final q = returnTo == null
                      ? ''
                      : '?returnTo=${Uri.encodeComponent(returnTo)}';
                  context.push('$route$q');
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text('Complete Profile',
                    style:
                        TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(sheetCtx),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    ),
  );
}
