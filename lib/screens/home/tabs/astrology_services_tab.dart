import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/astrologer_model.dart';
import '../../../providers/astrologer_provider.dart';

/// Astrology Services tab — shown as the "Astrologer" tab in the home bottom
/// nav. Provides quick actions to book appointments, chat, get horoscope,
/// check compatibility, and get gemstone suggestions.
///
/// The "Top Astrologers" section shows only the aggregate rating and count —
/// no individual review user names or comments, preserving anonymity.
class AstrologyServicesTab extends ConsumerWidget {
  const AstrologyServicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Top-rated list from the in-memory (or Firestore-backed) provider.
    final topRated = ref.watch(topRatedAstrologersProvider);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Top Banner ────────────────────────────────────────────────────
        _buildTopBanner(),
        const SizedBox(height: 20),

        // ── Quick Actions ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Our Services',
                  style: TextStyle(
                      fontSize: 17,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ServiceAction(
                    icon: Icons.calendar_month_outlined,
                    label: 'Book\nAppointment',
                    color: const Color(0xFFFFF3E0),
                    iconColor: Colors.deepOrange,
                    onTap: () => context.push('/astrologer-dashboard'),
                  ),
                  _ServiceAction(
                    icon: Icons.chat_outlined,
                    label: 'Chat with\nAstrologer',
                    color: const Color(0xFFE8F5E9),
                    iconColor: Colors.green,
                    onTap: () => context.push('/chats'),
                  ),
                  _ServiceAction(
                    icon: Icons.brightness_5_outlined,
                    label: 'Get\nHoroscope',
                    color: const Color(0xFFF3E5F5),
                    iconColor: Colors.purple,
                    onTap: () => context.push('/horoscope'),
                  ),
                  _ServiceAction(
                    icon: Icons.compare_arrows_outlined,
                    label: 'Match\nCompatibility',
                    color: const Color(0xFFFCE4EC),
                    iconColor: Colors.pinkAccent,
                    onTap: () {},
                  ),
                  _ServiceAction(
                    icon: Icons.diamond_outlined,
                    label: 'Gemstone\nSuggestion',
                    color: const Color(0xFFE3F2FD),
                    iconColor: Colors.blue,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Featured Services ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Featured Services',
                  style: TextStyle(
                      fontSize: 17,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: const [
                  _FeaturedCard(
                    icon: Icons.favorite_outline,
                    title: 'Horoscope\nMatching',
                    subtitle: 'Jathaka Porutham',
                    gradient: LinearGradient(
                        colors: [Color(0xFF800020), Color(0xFFAD1A45)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                  ),
                  _FeaturedCard(
                    icon: Icons.people_outline,
                    title: 'Astrologer\nConsultation',
                    subtitle: 'Expert guidance',
                    gradient: LinearGradient(
                        colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                  ),
                  _FeaturedCard(
                    icon: Icons.auto_graph_outlined,
                    title: 'Birth Chart\nAnalysis',
                    subtitle: 'Jathakam',
                    gradient: LinearGradient(
                        colors: [Color(0xFF01579B), Color(0xFF0288D1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                  ),
                  _FeaturedCard(
                    icon: Icons.diamond_outlined,
                    title: 'Gemstone\nRecommendation',
                    subtitle: 'Lucky stones',
                    gradient: LinearGradient(
                        colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Top Astrologers ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Top Astrologers',
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
                    Icon(Icons.arrow_forward_ios,
                        size: 12, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...topRated.take(5).map((a) => _AstrologerCard(astrologer: a)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTopBanner() {
    return Stack(
      children: [
        // Try real asset; fall back to branded gradient.
        Image.asset(
          'assets/images/astrology_banner.png',
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackBanner(),
        ),
      ],
    );
  }

  Widget _fallbackBanner() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C0B3F), Color(0xFF800020)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.gold.withOpacity(0.2), width: 1),
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.gold.withOpacity(0.35), width: 1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 160, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('✨ Jothida Sevai',
                    style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 6),
                const Text('Astrology\nServices',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        height: 1.2)),
                const SizedBox(height: 6),
                Text(
                  'Expert guidance for your\nperfect match',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75), fontSize: 12),
                ),
              ],
            ),
          ),
          Positioned(
            right: 20,
            top: 0,
            bottom: 0,
            child: Center(
              child: Icon(
                Icons.auto_awesome,
                size: 90,
                color: AppColors.gold.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Service Action Button ─────────────────────────────────────────────────────

class _ServiceAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _ServiceAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Featured Service Card ─────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final LinearGradient gradient;

  const _FeaturedCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.9), size: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      height: 1.25)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 10.5)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Astrologer Card ───────────────────────────────────────────────────────────

class _AstrologerCard extends StatelessWidget {
  final Astrologer astrologer;
  const _AstrologerCard({required this.astrologer});

  @override
  Widget build(BuildContext context) {
    final spec = astrologer.specializations.isNotEmpty
        ? astrologer.specializations.first
        : 'Vedic Astrology';

    return GestureDetector(
      onTap: () => context.push('/astrologer/${astrologer.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.07), blurRadius: 10)
          ],
        ),
        child: Row(
          children: [
            // Photo with availability indicator
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: astrologer.photoUrl.isNotEmpty
                      ? Image.network(
                          astrologer.photoUrl,
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _photoPlaceholder(),
                        )
                      : _photoPlaceholder(),
                ),
                if (astrologer.isAvailable)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(astrologer.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 2),
                  Text(spec,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.work_outline,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text('${astrologer.experienceYears} yrs exp',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 11.5)),
                    ],
                  ),
                ],
              ),
            ),
            // Aggregate rating — anonymous (no user names, no individual comments)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 16),
                    const SizedBox(width: 3),
                    Text(
                      astrologer.rating.toStringAsFixed(1),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                Text('(${astrologer.reviewCount})',
                    style:
                        TextStyle(color: Colors.grey[500], fontSize: 11)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () =>
                        context.push('/astrologer/${astrologer.id}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text('Book',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() => Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(30),
        ),
        child:
            const Icon(Icons.person, color: AppColors.primary, size: 30),
      );
}
