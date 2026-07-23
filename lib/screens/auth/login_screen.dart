import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/admin_config.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_routing.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/wedding_provider.dart';
import '../../widgets/auth/login_illustrations.dart';
import '../../widgets/common/coming_soon.dart';

/// App entry — ROLE-BASED. Instead of a classic login form, the user first
/// picks WHO they are with two large cards:
///   • Matrimony User  → looking for a life partner (matrimony experience);
///   • Family Member   → invited (by gmail) into a couple's Wedding Workspace.
///
/// Both roles sign in the SAME way: Continue with Google only (mobile-number
/// OTP login was removed). One Gmail may hold BOTH roles — the selected card
/// (not the account) decides which interface opens.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _EntryRole { matrimony, family }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// null = the two role cards; otherwise the Google sign-in step for that role.
  _EntryRole? _role;

  // Covers the *entire* Google flow — credential exchange AND the post-auth
  // routing — so the button stays busy until the user actually leaves this
  // screen, and a `finally` always clears it.
  bool _busy = false;

  /// Final backstop for the whole sign-in + routing round trip.
  ///
  /// Every individual step already has its own (much shorter) timeout; this
  /// exists so the spinner is bounded *structurally* rather than by trusting
  /// that every future in the chain behaves. The picker itself is user-paced,
  /// hence the generous budget.
  static const _signInBudget = Duration(minutes: 4);

  // ── Matrimony User sign-in ──────────────────────────────────────────────

  Future<void> _signInAsMatrimony() async {
    if (_busy) return; // guard against double-taps
    debugPrint('[LoginScreen] Matrimony User → Continue with Google tapped.');
    setState(() => _busy = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signInWithGoogle()
          .timeout(_signInBudget);
      if (!mounted) return;
      final auth = ref.read(authNotifierProvider);

      if (auth.hasError) {
        _showAuthError(auth.error);
        return;
      }

      var user = auth.valueOrNull;
      if (user == null) {
        // `GoogleSignIn.signIn()` reports "no account" for BOTH a dismissed
        // chooser and a Play-Services refusal, so a null model on its own does
        // not mean the user is unauthenticated. Ask Firebase — it is the only
        // authority on whether a session exists. This is the case that looked
        // like "authentication completes but the app stays on the login page":
        // the flow returned null and fell straight out of the method without
        // navigating and without an error.
        user = await _recoverSignedInUser();
        if (!mounted) return;
        if (user == null) {
          if (ref.read(authRepositoryProvider).currentUser != null) {
            // Signed in, but the user document could not be loaded. Still never
            // leave an authenticated account on the login screen — the router's
            // redirect settles the destination once the document arrives.
            debugPrint('[LoginScreen] authenticated but no user document → '
                '/home (router redirect will correct the destination)');
            context.go('/home');
            return;
          }
          debugPrint('[LoginScreen] no Google account AND no Firebase session '
              '→ nothing to route to. Either the chooser was dismissed, or '
              'Google refused to issue an ID token for this build (check the '
              '[GoogleSignIn] log lines above).');
          return;
        }
        debugPrint('[LoginScreen] recovered an existing Firebase session '
            '(uid=${user.uid}) — routing instead of staying on login.');
      }

      // The Matrimony card was chosen → matrimony interface on next open too.
      ref.read(entryModeProvider.notifier).state = WeddingEntryMode.matrimony;
      await WeddingEntryMode.save(WeddingEntryMode.matrimony);
      if (!mounted) return;
      debugPrint(
          '[LoginScreen] Sign-in successful (uid=${user.uid}). Routing...');
      await routeAuthenticatedUser(context, ref, user, tag: 'LoginScreen');
    } catch (e, st) {
      // Reaching here almost always means authentication SUCCEEDED and only the
      // post-auth work (entry-mode save, role lookup, navigation) blew up. The
      // one thing we must never do is leave a signed-in user sitting on the
      // login screen, so navigate anyway and let the router's redirect settle
      // on the correct destination from the user document.
      debugPrint('[LoginScreen] post-sign-in step failed: $e\n$st');
      if (!mounted) return;
      if (ref.read(authRepositoryProvider).currentUser != null) {
        debugPrint('[LoginScreen] already authenticated → /home '
            '(router redirect will correct the destination)');
        context.go('/home');
      } else {
        _showAuthError(e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Family Member sign-in ───────────────────────────────────────────────

  /// LAUNCH LOCK: Family Member Login is not part of the initial release.
  /// Tapping the (visibly locked) card only shows the shared Coming Soon
  /// dialog. A subtle "Admin sign-in" action lets the ADMIN proceed — since
  /// nobody is authenticated yet, the admin check itself happens right after
  /// the Google sign-in in [_signInAsFamily]; any non-admin account is signed
  /// straight back out.
  Future<void> _onFamilyCardTapped() async {
    final proceedAsAdmin = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock, color: AppColors.goldDark, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.featureFamilyLogin,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ComingSoonBadge(),
              const SizedBox(height: 12),
              Text(l10n.comingSoonBody,
                  style: const TextStyle(fontSize: 13.5, height: 1.4)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
              child: Text(l10n.adminSignIn,
                  style: const TextStyle(fontSize: 12)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );
    if (proceedAsAdmin == true && mounted) {
      setState(() => _role = _EntryRole.family);
    }
  }

  /// FAMILY entry. Signs in with Google, then verifies the Gmail is invited
  /// to a Wedding Workspace:
  ///   • invited → opens the Family Workspace (the same Gmail may ALSO be a
  ///     matrimony user — the card, not the account, picks the interface);
  ///   • not invited → "You have not been invited to any Wedding Workspace
  ///     yet. Please contact the Bride or Groom." and signed out again.
  Future<void> _signInAsFamily() async {
    if (_busy) return;
    debugPrint('[LoginScreen] Family Member → Continue with Google tapped.');
    setState(() => _busy = true);
    // Holds the router redirect on /login while the invite check runs, so a
    // brand-new family Gmail is never raced into matrimony onboarding.
    ref.read(familyLoginInProgressProvider.notifier).state = true;
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signInWithGoogle()
          .timeout(_signInBudget);
      if (!mounted) return;
      final auth = ref.read(authNotifierProvider);

      if (auth.hasError) {
        _showAuthError(auth.error);
        return;
      }

      final user = auth.valueOrNull;
      if (user == null) return; // picker dismissed

      // LAUNCH LOCK enforcement: Family Member Login is admin-only for now.
      // Any non-admin account that reaches this step is signed straight back
      // out and shown the shared Coming Soon dialog.
      if (!user.isAdmin && !AdminConfig.isSuperAdminEmail(user.email)) {
        debugPrint('[LoginScreen] family entry: ${user.email} is not an '
            'admin — Family Member Login is locked (Coming Soon).');
        await ref.read(authNotifierProvider.notifier).signOut();
        if (!mounted) return;
        await showComingSoonDialog(context,
            featureName: context.l10n.featureFamilyLogin);
        return;
      }

      final email = user.email?.toLowerCase() ?? '';
      final wedding = email.isEmpty
          ? null
          : await ref
              .read(weddingServiceProvider)
              .getWeddingByMemberEmail(email)
              .timeout(const Duration(seconds: 12));

      if (wedding == null) {
        // Not invited → no Family Workspace access. Sign back out so the
        // account can't wander into matrimony onboarding from this card.
        debugPrint('[LoginScreen] family entry: $email is NOT invited.');
        await ref.read(authNotifierProvider.notifier).signOut();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.l10n.notInvitedTitle),
            content: Text(ctx.l10n.notInvitedBody),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.ok),
              ),
            ],
          ),
        );
        return;
      }

      debugPrint('[LoginScreen] family entry: $email invited to wedding '
          '${wedding.id} — opening the Family Workspace.');
      final weddingService = ref.read(weddingServiceProvider);
      // Only a Gmail with NO other account type becomes a dedicated 'family'
      // account. A dual-role Gmail (also a matrimony user / admin) keeps its
      // role — the persisted entry mode opens the workspace instead.
      if (!user.isFamily &&
          !user.isAdmin &&
          !user.isAstrologer &&
          !user.isProfileComplete) {
        await weddingService
            .promoteToFamilyRole(user.uid)
            .timeout(const Duration(seconds: 12));
      }
      await weddingService
          .markMemberJoined(wedding.id, email)
          .timeout(const Duration(seconds: 12));
      ref.read(entryModeProvider.notifier).state = WeddingEntryMode.family;
      await WeddingEntryMode.save(WeddingEntryMode.family);
      ref.invalidate(currentUserProvider);
      await ref
          .read(currentUserProvider.future)
          .timeout(const Duration(seconds: 12))
          .catchError((Object e) {
        debugPrint('[LoginScreen] family user-doc refresh skipped: $e');
        return null;
      });
      if (!mounted) return;
      context.go('/wedding-workspace');
    } catch (e, st) {
      // Same rule as the matrimony path: an authenticated user is never left on
      // the login screen because a post-auth step failed. If this account turns
      // out not to be a family member after all, the router's redirect moves it
      // to the right place — being wrong for one frame beats spinning forever.
      debugPrint('[LoginScreen] family sign-in step failed: $e\n$st');
      if (!mounted) return;
      if (ref.read(authRepositoryProvider).currentUser != null) {
        context.go('/wedding-workspace');
      } else {
        _showAuthError(e);
      }
    } finally {
      ref.read(familyLoginInProgressProvider.notifier).state = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Last-resort check for an authenticated session when the sign-in call
  /// produced no [UserModel].
  ///
  /// Firebase Auth — not the Google plugin's return value — is the source of
  /// truth for "is this device signed in". Returns the user document, or null
  /// when there genuinely is no session.
  Future<UserModel?> _recoverSignedInUser() async {
    final repo = ref.read(authRepositoryProvider);
    final firebaseUser = repo.currentUser;
    if (firebaseUser == null) return null;
    debugPrint('[LoginScreen] Google returned no account, but Firebase HAS a '
        'session (uid=${firebaseUser.uid}) — loading the user document.');
    try {
      return await repo
          .createUserDocumentAfterAuth(firebaseUser, loginProvider: 'google.com')
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[LoginScreen] recovery user-document load failed: $e');
      return null;
    }
  }

  void _showAuthError(Object? err) {
    final String message;
    if (err is AuthException) {
      message = err.message;
    } else if (err is TimeoutException) {
      message = 'Google Sign-In did not finish in time. Please check your '
          'internet connection and try again.';
    } else {
      message = context.l10n.googleSignInFailed;
    }
    debugPrint('[LoginScreen] signInWithGoogle error (${err.runtimeType}): '
        '$err');
    if (!(err is AuthException && err.cancelled)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  //
  // Two distinct visual states, matching the reference design:
  //   1. Welcome screen — deep maroon/gold gradient, zodiac-ring couple
  //      emblem, two illustrated role cards, Taj Mahal skyline footer.
  //   2. Role login screen — soft pink/cream backdrop, circular couple or
  //      family illustration, "Continue with Google" pill button, feature
  //      row, and Terms & Privacy footer.

  static const _serifWeight = FontWeight.w700;

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);
    final googleBusy = _busy || authAsync.isLoading;

    return _role == null
        ? _buildWelcomeScaffold()
        : _buildRoleLoginScaffold(googleBusy);
  }

  // ── Screen 1: Welcome / role selection ──────────────────────────────────

  Widget _buildWelcomeScaffold() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: Stack(
            children: [
              const Positioned(
                  top: 60,
                  left: 28,
                  child: Icon(Icons.star, size: 8, color: Color(0x99D4AF37))),
              const Positioned(
                  top: 150,
                  right: 34,
                  child: Icon(Icons.star, size: 6, color: Color(0x66FFD700))),
              const Positioned(
                  top: 340,
                  left: 18,
                  child: Icon(Icons.star, size: 6, color: Color(0x66D4AF37))),
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 8),
                      child: Column(
                        children: [
                          const ZodiacCoupleLogo(size: 126),
                          const SizedBox(height: 18),
                          Text(
                            context.l10n.welcomeExclaim,
                            style: const TextStyle(
                                fontFamily: 'serif',
                                fontSize: 30,
                                fontWeight: _serifWeight,
                                color: AppColors.goldLight),
                          ),
                          const SizedBox(height: 6),
                          Container(
                              width: 90,
                              height: 1,
                              color: AppColors.gold.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text(
                            context.l10n.howContinue,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 26),
                          _roleCard(
                            role: _EntryRole.matrimony,
                            title: context.l10n.roleMatrimonyTitle,
                            description: context.l10n.roleMatrimonyDesc,
                            accent: const Color(0xFFD6336C),
                            illustration: const CoupleIllustrationCircle(
                                size: 76, showFloatingHearts: false),
                          ),
                          const SizedBox(height: 18),
                          _roleCard(
                            role: _EntryRole.family,
                            title: context.l10n.roleFamilyTitle,
                            description: context.l10n.roleFamilyDesc,
                            accent: AppColors.goldDark,
                            illustration: const FamilyIllustrationCircle(
                                size: 76, showFloatingHearts: false),
                            locked: true, // LAUNCH LOCK — Coming Soon
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  const TajMahalSkyline(height: 90),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleCard({
    required _EntryRole role,
    required String title,
    required String description,
    required Color accent,
    required Widget illustration,
    bool locked = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Material(
        color: AppColors.background,
        child: InkWell(
          // A locked card only shows the shared Coming Soon dialog (with the
          // admin-only continue path) — it never opens the role's login step.
          onTap: locked
              ? _onFamilyCardTapped
              : () => setState(() => _role = role),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 50),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: illustration,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(locked ? Icons.lock : Icons.favorite,
                                  size: 14, color: accent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                      fontFamily: 'serif',
                                      fontSize: 19,
                                      fontWeight: _serifWeight,
                                      color: accent),
                                ),
                              ),
                              if (locked) const ComingSoonBadge(compact: true),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                              width: 64,
                              height: 1.4,
                              color: accent.withOpacity(0.35)),
                          const SizedBox(height: 10),
                          Text(
                            description,
                            style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12.8,
                                height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: accent),
                  child: const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              CornerRibbon(color: accent),
            ],
          ),
        ),
      ),
    );
  }

  // ── Screen 2/3: Matrimony User / Family Member Google sign-in ───────────

  Widget _buildRoleLoginScaffold(bool googleBusy) {
    final isFamily = _role == _EntryRole.family;
    final accent = isFamily ? AppColors.goldDark : const Color(0xFFD6336C);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: LoginWaveClipper(),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isFamily
                        ? [const Color(0xFFFFF3D6), const Color(0xFFFFE7EC)]
                        : [const Color(0xFFFFE1EA), const Color(0xFFFFF3F6)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: googleBusy
                        ? null
                        : () => setState(() => _role = null),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withOpacity(0.12),
                      ),
                      child: Icon(Icons.arrow_back, color: accent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          isFamily
                              ? context.l10n.roleFamilyTitle
                              : context.l10n.roleMatrimonyTitle,
                          style: const TextStyle(
                              fontFamily: 'serif',
                              fontSize: 27,
                              fontWeight: _serifWeight,
                              color: AppColors.primary),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                                width: 26,
                                height: 1,
                                color: accent.withOpacity(0.5)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.favorite,
                                  size: 12, color: accent),
                            ),
                            Container(
                                width: 26,
                                height: 1,
                                color: accent.withOpacity(0.5)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            isFamily
                                ? context.l10n.signInFamilyPrompt
                                : context.l10n.signInMatrimonyPrompt,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 14.5,
                                color: Color(0xFF5C4048),
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Center(
                    child: isFamily
                        ? const FamilyIllustrationCircle(size: 190)
                        : const CoupleIllustrationCircle(size: 190),
                  ),
                  const SizedBox(height: 30),
                  OutlinedButton.icon(
                    onPressed: googleBusy
                        ? null
                        : (isFamily ? _signInAsFamily : _signInAsMatrimony),
                    icon: googleBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Image.network(
                            'https://www.google.com/favicon.ico',
                            width: 20,
                            height: 20,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.g_mobiledata, size: 24),
                          ),
                    label: Text(
                      context.l10n.continueWithGoogle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0xFF2A2A2A)),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(context.l10n.orLabel,
                            style: TextStyle(color: Colors.grey.shade500)),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: isFamily
                        ? [
                            _featureItem(Icons.verified_user,
                                context.l10n.featureSecurePrivate, accent),
                            _featureItem(Icons.email_outlined,
                                context.l10n.featureVerifiedInvite, accent),
                            _featureItem(Icons.groups_outlined,
                                context.l10n.featureFamilyWorkspace, accent),
                          ]
                        : [
                            _featureItem(Icons.verified_user,
                                context.l10n.featureSecurePrivate, accent),
                            _featureItem(Icons.badge_outlined,
                                context.l10n.featureVerifiedProfiles, accent),
                            _featureItem(Icons.favorite_border,
                                context.l10n.featurePerfectMatch, accent),
                          ],
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Column(
                      children: [
                        Text(context.l10n.agreeToTermsPrefix,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12.5)),
                        const SizedBox(height: 2),
                        Text(context.l10n.termsAndPrivacy,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (isFamily) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        context.l10n.familyInviteOnlyNote,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureItem(IconData icon, String label, Color accent) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent.withOpacity(0.4), width: 1.4),
          ),
          child: Icon(icon, color: accent, size: 22),
        ),
        const SizedBox(height: 8),
        // Fixed width so longer (e.g. Tamil) labels wrap to multiple lines
        // instead of overflowing the horizontal feature row.
        SizedBox(
          width: 96,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11.5,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
                height: 1.25),
          ),
        ),
      ],
    );
  }
}
