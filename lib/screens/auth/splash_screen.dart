import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/common/app_logo.dart';
import '../../providers/service_providers.dart';
import '../../providers/wedding_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _controller.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    try {
      // Read the CURRENT user straight from Firebase rather than from the
      // `firebaseAuthStreamProvider` snapshot. Nothing listens to that stream
      // provider before this point, so `ref.read` here would create it and get
      // back a brand-new `AsyncLoading` — i.e. `valueOrNull == null` — and send
      // an already-signed-in user to /login on every cold start. `currentUser`
      // is restored from disk during Firebase init and is immediately accurate;
      // the stream is only used as a fallback for the rare case where the
      // restore has not landed yet.
      final repo = ref.read(authRepositoryProvider);
      final user = repo.currentUser ??
          await repo.authStateChanges.first
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (!mounted) return;
      debugPrint('[Splash] resolved auth user=${user?.uid}');

      if (user == null) {
        // Spec §6 — a fresh install NEVER opens on the login page. Start a
        // GUEST (anonymous) session so Home can read the public content, then
        // land on Home. If anonymous sign-in is unavailable (provider off,
        // offline) we still go to Home: the router treats "not authenticated"
        // exactly like a guest, so the visitor browses instead of being
        // bounced to /login.
        debugPrint('[Splash] No signed-in user → starting Guest Mode → /home');
        try {
          await repo
              .signInAsGuest()
              .timeout(const Duration(seconds: 8));
        } catch (e) {
          debugPrint('[Splash] guest sign-in unavailable (non-fatal): $e');
        }
        if (!mounted) return;
        context.go('/home');
        return;
      }

      // An anonymous (Guest Mode) session has no `users/{uid}` document by
      // design — never try to read one, just open Home.
      if (repo.isGuest) {
        debugPrint('[Splash] Guest session → /home');
        context.go('/home');
        return;
      }

      debugPrint('[Splash] Signed in as ${user.uid} (${user.email}). '
          'Loading Firestore user doc...');
      // Bounded: an unreachable Firestore would otherwise leave the splash
      // spinner turning forever with no error and no navigation. On timeout we
      // fall through to the catch below, which lands on /login.
      final userModel = await repo
          .getUserModel(user.uid)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (userModel == null) {
        debugPrint('[Splash] No Firestore user doc found → /home (browse)');
        // Not a dead end: the router keeps a document-less session on the
        // guest allow-list, so they can browse and sign in when ready.
        context.go('/home');
        return;
      }

      // ── Family entry (role-based) ───────────────────────────────────────
      // A dedicated 'family' account, or a dual-role Gmail whose last chosen
      // card was "Family Member", re-opens the Family Workspace directly.
      final entryMode = await WeddingEntryMode.load();
      if (!mounted) return;
      if (userModel.isFamily ||
          (entryMode == WeddingEntryMode.family &&
              !userModel.isAstrologer &&
              userModel.role != 'admin')) {
        final email = userModel.email?.toLowerCase() ?? '';
        final invitedWedding = email.isEmpty
            ? null
            : await ref
                .read(weddingServiceProvider)
                .getWeddingByMemberEmail(email)
                .timeout(const Duration(seconds: 12));
        if (!mounted) return;
        if (invitedWedding != null || userModel.isFamily) {
          ref.read(entryModeProvider.notifier).state = WeddingEntryMode.family;
          debugPrint('[Splash] Family entry → /wedding-workspace');
          context.go('/wedding-workspace');
          return;
        }
        // Invitation revoked → drop the stale family mode, continue normally.
        await WeddingEntryMode.save(null);
        if (!mounted) return;
      }

      if (userModel.isAstrologer) {
        // Employee (horoscope-analysis staff) → Employee Portal.
        debugPrint('[Splash] Employee account → /astrologer-dashboard');
        context.go('/astrologer-dashboard');
      } else if (userModel.role == 'admin') {
        // Only a *pure* admin auto-lands on the dashboard. A super_admin is a
        // normal user (with an extra Admin icon) and goes through the normal
        // user flow below.
        debugPrint('[Splash] Pure admin account → /admin');
        context.go('/admin');
      } else {
        // Profile creation is NEVER forced on launch either: an account without
        // a matrimony profile opens Home, which shows the "Create Profile"
        // call-to-action. Only tapping that starts the wizard.
        // ── Workspace-first entry after Marriage Fixed ───────────────────
        // Once both partners confirmed Marriage Fixed, the app opens the
        // Wedding Workspace directly (a "Switch to Matrimony" button lives
        // inside the workspace menu).
        //
        // LAUNCH LOCK: the workspace is Coming Soon for non-admin users, so
        // only admins take the workspace-first shortcut — everyone else goes
        // to Home as usual instead of landing on a locked page every launch.
        try {
          if (userModel.isAdmin) {
            final wedding = await ref
                .read(weddingServiceProvider)
                .getWeddingForCouple(user.uid)
                .timeout(const Duration(seconds: 12));
            if (!mounted) return;
            if (wedding != null && wedding.isFixed) {
              ref.read(entryModeProvider.notifier).state =
                  WeddingEntryMode.matrimony;
              debugPrint('[Splash] Marriage Fixed → /wedding-workspace');
              context.go('/wedding-workspace');
              return;
            }
          }
        } catch (e) {
          debugPrint('[Splash] couple wedding lookup failed (non-fatal): $e');
        }
        if (!mounted) return;
        debugPrint('[Splash] → /home '
            '(isProfileComplete=${userModel.isProfileComplete})');
        context.go('/home');
      }
    } catch (e, st) {
      // Never leave the user stuck on the splash screen. A Firestore read
      // failure (e.g. permission-denied because security rules aren't
      // deployed yet, or no network) used to throw here uncaught, leaving
      // the spinner forever with no navigation and no visible error.
      debugPrint('[Splash] _navigate() failed: $e\n$st');
      if (!mounted) return;
      // Never dead-end on the splash OR on the login page: Home is browsable
      // for everyone (§6), and every personalized action gates itself.
      context.go('/home');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: Center(
          child: ScaleTransition(
            scale: _scaleAnim,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Official brand logo, prominently centred.
                  const AppLogo(size: 190),
                  const SizedBox(height: 18),
                  Text(
                    'Jothida Matrimony',
                    style: AppTextStyles.appName
                        .copyWith(color: AppColors.gold, fontSize: 26),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ஜோதிட மேட்ரிமோனி',
                    style: AppTextStyles.tamilBody.copyWith(
                      color: AppColors.gold.withOpacity(0.85),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 44),
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                    strokeWidth: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
