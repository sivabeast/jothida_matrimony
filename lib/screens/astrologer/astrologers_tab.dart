import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_model.dart';
import '../../providers/astrologer_provider.dart';
import '../../widgets/common/network_photo.dart';

/// "Connect Astrologer" bottom-nav tab. Shows grouped astrologer sections:
/// Top Rated, Recommended and Recently Active.
class AstrologersTab extends ConsumerWidget {
  const AstrologersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topRated = ref.watch(topRatedAstrologersProvider);
    final recommended = ref.watch(recommendedAstrologersProvider);
    final recent = ref.watch(recentlyActiveAstrologersProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _intro(),
        _section(context, 'Recommended Astrologers', recommended),
        _section(context, 'Top Rated', topRated),
        _section(context, 'Recently Active', recent),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _intro() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.gold, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Talk to verified astrologers',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    SizedBox(height: 4),
                    Text('Porutham, horoscope matching & marriage consultation',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _section(BuildContext context, String title, List<Astrologer> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 232,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: list.length,
            itemBuilder: (_, i) => _AstrologerCard(astrologer: list[i]),
          ),
        ),
      ],
    );
  }
}

/// Compact directory card: reduced image with a small verified tick, then a
/// tight content block (name, availability, rating, location, experience,
/// specialization). Sized to content — no large blank areas.
class _AstrologerCard extends StatelessWidget {
  final Astrologer astrologer;
  const _AstrologerCard({required this.astrologer});

  @override
  Widget build(BuildContext context) {
    final a = astrologer;
    final availColor = a.isAvailable ? AppColors.success : AppColors.error;
    return GestureDetector(
      onTap: () => context.push('/astrologer/${a.id}'),
      child: Container(
        width: 168,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: NetworkPhoto(
                    url: a.photoUrl,
                    height: 104,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    fallbackIcon: Icons.person,
                    fallbackIconSize: 44,
                    fallbackBg: AppColors.primary.withOpacity(0.10),
                  ),
                ),
                // Small social-media style verified tick — not a badge.
                if (a.verified)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 3)
                        ],
                      ),
                      child: const Icon(Icons.verified,
                          color: AppColors.success, size: 18),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13.5)),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 9, color: availColor),
                      const SizedBox(width: 5),
                      Text(a.isAvailable ? 'Available' : 'Unavailable',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: availColor)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.star, size: 13, color: AppColors.gold),
                    const SizedBox(width: 3),
                    Text(a.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 3),
                    Text('(${a.reviewCount})',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ]),
                  _row(Icons.location_on_outlined, a.location),
                  _row(
                      Icons.work_history_outlined,
                      a.experienceYears > 0
                          ? '${a.experienceYears} yrs experience'
                          : 'Experience N/A'),
                  _row(
                      Icons.auto_awesome,
                      a.specializations.isEmpty
                          ? 'Astrologer'
                          : a.specializations.first,
                      color: AppColors.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(icon, size: 12.5, color: color ?? Colors.grey[500]),
            const SizedBox(width: 4),
            Expanded(
              child: Text(text.isEmpty ? '—' : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5, color: color ?? Colors.grey[700])),
            ),
          ],
        ),
      );
}
