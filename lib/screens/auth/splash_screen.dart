import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';

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
        debugPrint('[Splash] No signed-in user → /account-type');
        // Signed out: ask who the account is for (User / Astrologer).
        context.go('/account-type');
        return;
      }

      debugPrint('[Splash] Signed in as ${user.uid} (${user.email}). '
          'Loading Firestore user doc...');
      final userModel =
          await ref.read(authRepositoryProvider).getUserModel(user.uid);
      if (!mounted) return;

      if (userModel == null) {
        debugPrint('[Splash] No Firestore user doc found → /account-type');
        context.go('/account-type');
      } else if (userModel.isAdmin) {
        debugPrint('[Splash] Admin user → /admin');
        context.go('/admin');
      } else if (userModel.isAstrologer) {
        debugPrint('[Splash] Astrologer user → /astrologer-dashboard');
        context.go('/astrologer-dashboard');
      } else if (!userModel.isProfileComplete) {
        debugPrint('[Splash] Profile incomplete → /profile/create');
        context.go('/profile/create');
      } else {
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
      context.go('/account-type');
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
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.gold, width: 2),
                    ),
                    child: const Icon(Icons.favorite, color: AppColors.gold, size: 64),
                  ),
                  const SizedBox(height: 24),
                  Text('Jothida Matrimony', style: AppTextStyles.appName),
                  const SizedBox(height: 8),
                  Text(
                    'ஜோதிட மேட்ரிமோனி',
                    style: AppTextStyles.tamilBody.copyWith(
                      color: AppColors.gold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 48),
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
