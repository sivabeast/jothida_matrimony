import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/profile_model.dart';
import '../../../providers/profile_provider.dart';
// ProfileCompletionCard available for future use:
// import '../../../widgets/home/profile_completion_card.dart';

/// Home dashboard tab — hero banner carousel, quick actions, recommended
/// matches horizontal scroll, premium upgrade banner.
class HomeDashboardTab extends ConsumerStatefulWidget {
  const HomeDashboardTab({super.key});

  @override
  ConsumerState<HomeDashboardTab> createState() => _HomeDashboardTabState();
}

class _HomeDashboardTabState extends ConsumerState<HomeDashboardTab> {
  final PageController _bannerCtrl = PageController();
  int _bannerPage = 0;
  Timer? _bannerTimer;

  // Custom hero banners provided by the brand. The full artwork (headline,
  // sub-text and CTA) is baked into each image, so the slide simply renders the
  // asset edge-to-edge. The headline/subtitle/cta below are only used by the
  // graceful fallback if an asset ever fails to load.
  static const _banners = [
    _BannerData(
      assetPath: 'assets/images/banner_1.png',
      headline: 'Perfect Match\nWritten in the Stars',
      subtitle: 'Astrology meets compatibility\nto create your perfect match.',
      cta: 'Explore Your Match →',
    ),
    _BannerData(
      assetPath: 'assets/images/banner_2.png',
      headline: 'Find Your\nLife Partner',
      subtitle: 'Where stars align,\nhearts connect.',
      cta: 'Explore Matches →',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
    Future.microtask(() {
      final gender = ref.read(matchGenderProvider);
      ref.read(discoverProvider.notifier).load(gender: gender);
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerCtrl.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_bannerPage + 1) % _banners.length;
      _bannerCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final discover = ref.watch(discoverProvider);
    final profiles = discover.profiles.take(6).toList();

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        final gender = ref.read(matchGenderProvider);
        ref.read(discoverProvider.notifier).load(gender: gender);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Hero Banner Carousel ──────────────────────────────────────────
          _buildBannerCarousel(context),
          const SizedBox(height: 16),

          // ── Quick Actions ────────────────────────────────────────────────
          _buildQuickActions(context),
          const SizedBox(height: 16),

          // ── Profile Completion / Verify Card ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildVerifyCard(context),
          ),
          const SizedBox(height: 16),

          // ── Recommended Matches ──────────────────────────────────────────
          _buildMatchesSection(context, profiles),
          const SizedBox(height: 16),

          // ── Premium Upgrade Banner ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildPremiumBanner(context),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Banner Carousel ────────────────────────────────────────────────────────

  Widget _buildBannerCarousel(BuildContext context) {
    // The banner artwork is 3:2. Derive the height from the available width
    // (screen width minus the 16px horizontal padding on each side) so the
    // complete design is shown edge-to-edge without cropping any content.
    final bannerWidth = MediaQuery.of(context).size.width - 32;
    final bannerHeight = bannerWidth * (1024 / 1536);

    return Column(
      children: [
        SizedBox(
          height: bannerHeight,
          child: PageView.builder(
            controller: _bannerCtrl,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _bannerPage = i),
            itemBuilder: (_, i) => _BannerSlide(data: _banners[i]),
          ),
        ),
        const SizedBox(height: 10),
        // Indicator dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_banners.length, (i) {
            final active = i == _bannerPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _QuickAction(
            icon: Icons.people_outline,
            label: 'Matches',
            onTap: () {
              // Matches quick-action: find parent HomeScreen and switch to tab 1.
              // Navigation is handled by the bottom nav; tapping here
              // scrolls the list to the top or reloads profiles.
              final gender = ref.read(matchGenderProvider);
              ref.read(discoverProvider.notifier).load(gender: gender);
            },
          ),
          _QuickAction(
            icon: Icons.auto_awesome_outlined,
            label: 'Horoscope\nMatch',
            onTap: () => context.push('/horoscope'),
          ),
          _QuickAction(
            icon: Icons.manage_accounts_outlined,
            label: 'Partner\nPreferences',
            onTap: () {
              debugPrint('[HomeDashboard] Quick action: Partner Preferences '
                  '→ /partner-preferences');
              context.push('/partner-preferences');
            },
          ),
          _QuickAction(
            icon: Icons.workspace_premium_outlined,
            label: 'Premium\nPlans',
            onTap: () => context.push('/subscription'),
          ),
        ],
      ),
    );
  }

  // ── Verify Card ────────────────────────────────────────────────────────────

  Widget _buildVerifyCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Stack(
              children: [
                const Center(
                  child: Icon(Icons.shield_outlined, color: AppColors.primary, size: 26),
                ),
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('!', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Verify Your Profile',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Increase trust and get more matches',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Verify Now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Recommended Matches ───────────────────────────────────────────────────

  Widget _buildMatchesSection(BuildContext context, List<ProfileModel> profiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recommended Matches',
                  style: TextStyle(
                      fontSize: 17,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () {},
                child: Row(
                  children: [
                    Text('View All',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (profiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildEmptyMatches(),
          )
        else
          SizedBox(
            height: 240,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: profiles.length,
              itemBuilder: (_, i) => _MatchCard(profile: profiles[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyMatches() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.favorite_border, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 8),
          const Text('No matches yet', style: TextStyle(fontWeight: FontWeight.w600)),
          Text('Complete your profile to see matches',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }

  // ── Premium Banner ─────────────────────────────────────────────────────────

  Widget _buildPremiumBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/subscription'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium, color: AppColors.gold, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Go Premium',
                      style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'Poppins')),
                  Text('Get more visibility and unlimited matches',
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => context.push('/subscription'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Upgrade Now',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Banner Data Model ─────────────────────────────────────────────────────────

class _BannerData {
  final String assetPath;
  final String headline;
  final String subtitle;
  final String cta;
  const _BannerData({
    required this.assetPath,
    required this.headline,
    required this.subtitle,
    required this.cta,
  });
}

// ── Banner Slide Widget ───────────────────────────────────────────────────────

class _BannerSlide extends StatelessWidget {
  final _BannerData data;
  const _BannerSlide({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Try asset image first; fall back to branded gradient container.
            Image.asset(
              data.assetPath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackBanner(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8B0000), Color(0xFF6B0000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Decorative zodiac circle (right side)
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold.withOpacity(0.3), width: 1),
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold.withOpacity(0.5), width: 1),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 120, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.headline,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 22,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data.subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    data.cta,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Gold couple silhouette placeholder (right side)
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: Icon(
                Icons.favorite,
                size: 80,
                color: AppColors.gold.withOpacity(0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick Action Button ───────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recommended Match Card ────────────────────────────────────────────────────

class _MatchCard extends StatelessWidget {
  final ProfileModel profile;
  const _MatchCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/profile/${profile.id}'),
      child: Container(
        width: 155,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: profile.photos.isNotEmpty
                        ? Image.network(
                            profile.photos.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                ),
                // Online badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Online',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${profile.name}, ${profile.age}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'Poppins'),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    profile.education.isEmpty ? 'N/A' : profile.education,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                  Text(
                    profile.occupation.isEmpty ? 'N/A' : profile.occupation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 11, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          profile.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey[500], fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.person, size: 48, color: Colors.grey),
      );
}

// Search filters were replaced by the dedicated Partner Preferences screen
// (route `/partner-preferences`).
