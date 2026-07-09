import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/common/app_logo.dart';
import '../../providers/auth_provider.dart';
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
      final authAsync = ref.read(firebaseAuthStreamProvider);
      final user = authAsync.valueOrNull;
      debugPrint('[Splash] firebaseAuthStreamProvider state: '
          '${authAsync.runtimeType}, user=${user?.uid}');

      if (user == null) {
        debugPrint('[Splash] No signed-in user → /login');
        // Single common login for everyone (User / Admin / Employee).
        context.go('/login');
        return;
      }

      debugPrint('[Splash] Signed in as ${user.uid} (${user.email}). '
          'Loading Firestore user doc...');
      final userModel =
          await ref.read(authRepositoryProvider).getUserModel(user.uid);
      if (!mounted) return;

      if (userModel == null) {
        debugPrint('[Splash] No Firestore user doc found → /login');
        context.go('/login');
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
                .getWeddingByMemberEmail(email);
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
      } else if (!userModel.isProfileComplete) {
        debugPrint('[Splash] Profile incomplete → /profile/create');
        context.go('/profile/create');
      } else {
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
                .getWeddingForCouple(user.uid);
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
        debugPrint('[Splash] Profile complete → /home');
        context.go('/home');
      }
    } catch (e, st) {
      // Never leave the user stuck on the splash screen. A Firestore read
      // failure (e.g. permission-denied because security rules aren't
      // deployed yet, or no network) used to throw here uncaught, leaving
      // the spinner forever with no navigation and no visible error.
      debugPrint('[Splash] _navigate() failed: $e\n$st');
      if (!mounted) return;
      context.go('/login');
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
