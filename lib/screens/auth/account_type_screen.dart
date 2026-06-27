import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

/// First screen after the splash — a premium, mobile-first onboarding that asks
/// the visitor to choose their role (Matrimony **User** or **Astrologer**).
///
/// Layout follows the brand reference: a curved maroon hero (logo + title +
/// tagline over a golden zodiac feel) flowing into a cream body with the
/// "Who are you joining as?" heading and two large, feature-rich role cards.
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideUser = Tween<Offset>(begin: const Offset(0, 0.30), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.25, 0.85, curve: Curves.easeOutCubic)));
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
      backgroundColor: const Color(0xFFFBF3E4), // warm cream body
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(context),
            const SizedBox(height: 22),
            FadeTransition(
              opacity: _fade,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: [
                    const Text(
                      'Find Your Perfect Match',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(height: 6),
                    _goldDivider(),
                    const SizedBox(height: 8),
                    Text(
                      'Continue to create your profile and discover matches',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.brown.shade400, fontSize: 14.5),
                    ),
                    const SizedBox(height: 22),
                    SlideTransition(
                      position: _slideUser,
                      child: _RoleCard(
                        accent: AppColors.primary,
                        badgeIcon: Icons.favorite,
                        heroIcon: Icons.favorite_rounded,
                        title: 'Looking for a\nLife Partner',
                        subtitle: 'Get Started',
                        features: const [
                          (Icons.person_outline, 'Create Your Profile'),
                          (Icons.favorite_border, 'Discover Matches'),
                          (Icons.auto_awesome_outlined, 'Horoscope Matching'),
                        ],
                        onTap: () => context.push('/login'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _footer(context),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Curved maroon hero ──────────────────────────────────────────────────────
  Widget _hero(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return ClipPath(
      clipper: _HeroCurveClipper(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, topPad + 28, 24, 56),
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: Column(
          children: [
            // Golden zodiac medallion (logo). Falls back to an icon if missing.
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.gold.withOpacity(0.25), blurRadius: 24),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 104,
                  height: 104,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.favorite,
                      color: AppColors.gold, size: 64),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Jothida Matrimony',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 30,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
                letterSpacing: 0.3,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find Your Perfect Match\nwith Astrological Guidance',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            _goldDivider(onMaroon: true),
          ],
        ),
      ),
    );
  }

  Widget _goldDivider({bool onMaroon = false}) {
    final c = onMaroon ? AppColors.gold.withOpacity(0.7) : AppColors.gold;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 36, height: 1.2, color: c),
        const SizedBox(width: 8),
        Icon(Icons.favorite, color: c, size: 13),
        const SizedBox(width: 8),
        Container(width: 36, height: 1.2, color: c),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final muted = TextStyle(color: Colors.brown.shade400, fontSize: 12.5);
    final link = TextStyle(
        color: AppColors.primary,
        fontSize: 12.5,
        fontWeight: FontWeight.w700);
    return Column(
      children: [
        Text('By continuing, you agree to our', style: muted),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
                onTap: () => context.push('/terms'),
                child: Text('Terms of Service', style: link)),
            Text('   •   ', style: muted),
            GestureDetector(
                onTap: () => context.push('/privacy-policy'),
                child: Text('Privacy Policy', style: link)),
          ],
        ),
      ],
    );
  }
}

/// A large, premium role-selection card: a gradient hero badge on the left,
/// title + subtitle + feature bullets on the right, and a chevron affordance.
class _RoleCard extends StatelessWidget {
  final Color accent;
  final IconData badgeIcon;
  final IconData heroIcon;
  final String title;
  final String subtitle;
  final List<(IconData, String)> features;
  final VoidCallback onTap;

  const _RoleCard({
    required this.accent,
    required this.badgeIcon,
    required this.heroIcon,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      elevation: 6,
      shadowColor: accent.withOpacity(0.18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero badge (left) — gradient circle with a small corner badge.
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [accent.withOpacity(0.85), accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: accent.withOpacity(0.35), blurRadius: 12),
                        ],
                      ),
                      child: Icon(heroIcon, color: Colors.white, size: 36),
                    ),
                    Positioned(
                      top: -4,
                      left: -4,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 4),
                          ],
                        ),
                        child: Icon(badgeIcon, color: accent, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 20,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Poppins',
                              color: accent,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            size: 16, color: accent.withOpacity(0.7)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    Divider(color: accent.withOpacity(0.15), height: 1),
                    const SizedBox(height: 10),
                    ...features.map((f) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: accent.withOpacity(0.10),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(f.$1, size: 15, color: accent),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(f.$2,
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary)),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convex bottom edge for the maroon hero, so it flows into the cream body.
class _HeroCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height - 34)
      ..quadraticBezierTo(
          size.width / 2, size.height + 16, size.width, size.height - 34)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
