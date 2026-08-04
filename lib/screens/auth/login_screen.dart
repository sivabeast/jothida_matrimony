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
import '../../core/utils/login_identifier.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/wedding_provider.dart';
import '../../widgets/auth/login_illustrations.dart';
import '../../widgets/common/app_logo.dart';
import '../../widgets/common/coming_soon.dart';
import '../../widgets/common/gradient_button.dart';

/// App entry — a single premium matrimony login screen with exactly TWO
/// sign-in methods:
///
///   1. **Continue with Google** — the large primary action. Existing Google
///      accounts keep working untouched: the same Gmail always resolves to the
///      same `users/{uid}` document and profile, never a duplicate.
///   2. **Phone Number / Email + Password** — one identifier field (usernames
///      were removed completely), a password field, "Forgot Password?" and
///      "Create Account".
///
/// "Family Member Login" (invited Wedding Workspace members) is preserved as a
/// subtle secondary action at the bottom — it is still launch-locked behind the
/// shared Coming Soon dialog, with the admin-only continue path intact.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Covers the *entire* sign-in flow — credential exchange AND the post-auth
  // routing — so the buttons stay busy until the user actually leaves this
  // screen, and a `finally` always clears it.
  bool _busy = false;

  /// Final backstop for the whole sign-in + routing round trip.
  ///
  /// Every individual step already has its own (much shorter) timeout; this
  /// exists so the spinner is bounded *structurally* rather than by trusting
  /// that every future in the chain behaves. The picker itself is user-paced,
  /// hence the generous budget.
  static const _signInBudget = Duration(minutes: 4);

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Password sign-in (mobile number OR e-mail) ──────────────────────────

  Future<void> _passwordLogin() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    debugPrint('[LoginScreen] password login tapped.');
    setState(() => _busy = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signInWithIdentifier(
              _identifierController.text.trim(), _passwordController.text)
          .timeout(_signInBudget);
      if (!mounted) return;
      final auth = ref.read(authNotifierProvider);
      if (auth.hasError) {
        _showAuthError(auth.error);
        return;
      }
      final user = auth.valueOrNull;
      if (user == null) {
        _snack(context.l10n.loginFailedCheckDetails);
        return;
      }
      await _enterMatrimony(user);
    } catch (e, st) {
      debugPrint('[LoginScreen] password login failed: $e\n$st');
      if (!mounted) return;
      if (ref.read(authRepositoryProvider).currentUser != null) {
        // Authenticated, only a post-auth step failed — never strand a
        // signed-in account on the login screen.
        context.go('/home');
      } else {
        _showAuthError(e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Records the matrimony entry mode and routes the authenticated account.
  Future<void> _enterMatrimony(UserModel user) async {
    ref.read(entryModeProvider.notifier).state = WeddingEntryMode.matrimony;
    await WeddingEntryMode.save(WeddingEntryMode.matrimony);
    if (!mounted) return;
    debugPrint('[LoginScreen] sign-in successful (uid=${user.uid}). Routing...');
    await routeAuthenticatedUser(context, ref, user, tag: 'LoginScreen');
  }

  // ── Matrimony User sign-in (Google) ─────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    if (_busy) return; // guard against double-taps
    debugPrint('[LoginScreen] Continue with Google tapped.');
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

      await _enterMatrimony(user);
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
  /// Tapping the (visibly locked) action only shows the shared Coming Soon
  /// dialog. A subtle "Admin sign-in" action lets the ADMIN proceed — since
  /// nobody is authenticated yet, the admin check itself happens right after
  /// the Google sign-in in [_signInAsFamily]; any non-admin account is signed
  /// straight back out.
  Future<void> _onFamilyLoginTapped() async {
    if (_busy) return;
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
    if (proceedAsAdmin == true && mounted) await _signInAsFamily();
  }

  /// FAMILY entry. Signs in with Google, then verifies the Gmail is invited
  /// to a Wedding Workspace:
  ///   • invited → opens the Family Workspace (the same Gmail may ALSO be a
  ///     matrimony user — the action, not the account, picks the interface);
  ///   • not invited → "You have not been invited to any Wedding Workspace
  ///     yet. Please contact the Bride or Groom." and signed out again.
  Future<void> _signInAsFamily() async {
    if (_busy) return;
    debugPrint('[LoginScreen] Family Member → Continue with Google tapped.');
    setState(() => _busy = true);
    // Holds the router redirect on /login while the invite check runs, so a
    // brand-new family Gmail is never raced into the matrimony experience.
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
        // account can't wander into the matrimony experience from here.
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showAuthError(Object? err) {
    final String message;
    if (err is AuthException) {
      message = err.message;
    } else if (err is TimeoutException) {
      message = 'Sign-in did not finish in time. Please check your internet '
          'connection and try again.';
    } else {
      message = context.l10n.googleSignInFailed;
    }
    debugPrint('[LoginScreen] sign-in error (${err.runtimeType}): $err');
    if (!(err is AuthException && err.cancelled)) _snack(message);
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  static const _serifWeight = FontWeight.w700;
  static const _accent = Color(0xFFD6336C);

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);
    final busy = _busy || authAsync.isLoading;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Soft brand wash behind the header, clipped with the shared wave.
          Positioned.fill(
            child: ClipPath(
              clipper: LoginWaveClipper(),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFE1EA), Color(0xFFFFF6F8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
                child: ConstrainedBox(
                  // Centres the card on tablets/large phones without ever
                  // stretching the form to an unreadable width.
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(l10n),
                      const SizedBox(height: 22),
                      _googleButton(busy, l10n),
                      const SizedBox(height: 18),
                      _orDivider(l10n),
                      const SizedBox(height: 18),
                      _passwordForm(busy, l10n),
                      const SizedBox(height: 20),
                      _createAccountRow(busy, l10n),
                      const SizedBox(height: 18),
                      _termsFooter(l10n),
                      const SizedBox(height: 10),
                      _familyLoginLink(busy, l10n),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    return Column(
      children: [
        // ONE brand mark: the official application launcher icon, centred and
        // sized to lead the page. The old stacked pair (in-app emblem + zodiac
        // couple illustration) competed with each other and with the title.
        const SizedBox(height: 8),
        const Center(child: AppLauncherLogo(size: 116)),
        const SizedBox(height: 26),
        Text(
          l10n.welcomeBack,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 27,
            fontWeight: _serifWeight,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 26, height: 1, color: _accent.withOpacity(0.5)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.favorite, size: 12, color: _accent),
            ),
            Container(width: 26, height: 1, color: _accent.withOpacity(0.5)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.signInToYourAccount,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 14.5, color: Color(0xFF5C4048), height: 1.35),
        ),
      ],
    );
  }

  /// Option 1 — the large primary Google action.
  Widget _googleButton(bool busy, AppLocalizations l10n) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: busy ? null : _signInWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2A2A2A),
          disabledBackgroundColor: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const _GoogleGlyph(size: 22),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                l10n.continueWithGoogle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orDivider(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(l10n.orLabel,
              style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6)),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }

  /// Option 2 — mobile number OR e-mail + password. There is no username.
  Widget _passwordForm(bool busy, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _identifierController,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            decoration: _fieldDecoration(
              label: l10n.phoneOrEmail,
              hint: l10n.phoneOrEmailHint,
              icon: Icons.person_outline,
            ),
            validator: (v) =>
                LoginIdentifier.kindOf(v ?? '') == LoginIdentifierKind.unknown
                    ? l10n.invalidLoginIdentifier
                    : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            enabled: !busy,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => busy ? null : _passwordLogin(),
            decoration: _fieldDecoration(
              label: l10n.password,
              hint: '••••••',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                    color: Colors.grey.shade600),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) => (v == null || v.isEmpty)
                ? l10n.pleaseEnterField(l10n.password)
                : null,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: busy ? null : () => context.push('/forgot-password'),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact),
              child: Text(l10n.forgotPassword,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 4),
          GradientButton(
            onPressed: busy ? null : _passwordLogin,
            isLoading: busy,
            text: l10n.login,
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      // Labels can be long in Tamil — let them wrap instead of clipping.
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: const TextStyle(fontSize: 14),
      errorMaxLines: 3,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: border(Colors.grey.shade300, 1),
      border: border(Colors.grey.shade300, 1),
      focusedBorder: border(AppColors.primary, 1.6),
      errorBorder: border(AppColors.error, 1),
      focusedErrorBorder: border(AppColors.error, 1.6),
    );
  }

  Widget _createAccountRow(bool busy, AppLocalizations l10n) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(l10n.newToJothida,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13.5)),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: busy ? null : () => context.push('/register'),
          child: Text(
            l10n.createAccount,
            style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _termsFooter(AppLocalizations l10n) {
    return Column(
      children: [
        Text(l10n.agreeToTermsPrefix,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: () => context.push('/terms'),
          child: Text(l10n.termsAndPrivacy,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _accent, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      ],
    );
  }

  /// Preserved (launch-locked) Family Member Login, kept deliberately subtle so
  /// it never competes with the two primary sign-in methods.
  Widget _familyLoginLink(bool busy, AppLocalizations l10n) {
    return Center(
      child: TextButton.icon(
        onPressed: busy ? null : _onFamilyLoginTapped,
        style: TextButton.styleFrom(foregroundColor: AppColors.goldDark),
        icon: const Icon(Icons.lock_outline, size: 15),
        label: Text(l10n.familyMemberLogin,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// The Google "G" drawn locally.
///
/// The previous implementation loaded https://www.google.com/favicon.ico, which
/// meant the primary sign-in button flashed a fallback glyph on a slow or
/// offline network. This never touches the network.
class _GoogleGlyph extends StatelessWidget {
  final double size;
  const _GoogleGlyph({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGlyphPainter()),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.22;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke,
        size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Four quadrant arcs in Google's brand colours, then the horizontal bar.
    void arc(double startDeg, double sweepDeg, Color color) {
      paint.color = color;
      canvas.drawArc(rect, startDeg * 3.1415926535 / 180,
          sweepDeg * 3.1415926535 / 180, false, paint);
    }

    arc(-25, -95, _red); // top-right → top-left
    arc(-120, -95, _yellow); // left
    arc(145, 80, _green); // bottom
    arc(-25, 70, _blue); // right

    final barPaint = Paint()..color = _blue;
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.5, size.height * 0.42, size.width * 0.42,
          size.height * 0.16),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
