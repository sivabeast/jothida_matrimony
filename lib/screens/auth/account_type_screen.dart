import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// First screen after the splash: choose whether you are registering as a
/// matrimony **User** or as an **Astrologer**. Each choice leads to its own
/// login / signup flow.
class AccountTypeScreen extends StatefulWidget {
  const AccountTypeScreen({super.key});

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slideUser;
  late final Animation<Offset> _slideAstro;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideUser = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic)));
    _slideAstro = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic)));
    _controller.forward();
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
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FadeTransition(
              opacity: _fade,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Icon(Icons.favorite, color: AppColors.gold, size: 56),
                  const SizedBox(height: 12),
                  Center(
                      child:
                          Text('Jothida Matrimony', style: AppTextStyles.appName)),
                  const SizedBox(height: 40),
                  const Text(
                    'Who are you creating\nan account for?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose how you want to use the app',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 14),
                  ),
                  const SizedBox(height: 36),
                  SlideTransition(
                    position: _slideUser,
                    child: _TypeCard(
                      icon: Icons.favorite_border,
                      iconBg: AppColors.primary,
                      title: 'User',
                      subtitle:
                          'Find your perfect life partner with horoscope-matched profiles',
                      onTap: () => context.push('/login'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SlideTransition(
                    position: _slideAstro,
                    child: _TypeCard(
                      icon: Icons.auto_awesome,
                      iconBg: AppColors.goldDark,
                      title: 'Astrologer',
                      subtitle:
                          'Offer consultations, horoscope matching and grow your practice',
                      onTap: () => context.push('/astrologer-login'),
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBg.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconBg, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios,
                  size: 16, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
