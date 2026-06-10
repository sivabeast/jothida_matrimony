import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_model.dart';
import '../../providers/astrologer_provider.dart';

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

class _AstrologerCard extends StatelessWidget {
  final Astrologer astrologer;
  const _AstrologerCard({required this.astrologer});

  @override
  Widget build(BuildContext context) {
    final a = astrologer;
    return GestureDetector(
      onTap: () => context.push('/astrologer/${a.id}'),
      child: Container(
        width: 168,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.network(
                    a.photoUrl,
                    height: 110,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 110,
                      color: AppColors.primary.withOpacity(0.1),
                      child: const Icon(Icons.person, size: 50, color: AppColors.primary),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: a.isAvailable ? AppColors.success : Colors.grey,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(a.isAvailable ? 'Online' : 'Offline',
                        style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.star, size: 13, color: AppColors.gold),
                    Text(' ${a.rating}', style: const TextStyle(fontSize: 12)),
                    Text('  •  ${a.experienceYears}y',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ]),
                  const SizedBox(height: 2),
                  Text(a.specializations.isNotEmpty ? a.specializations.first : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('From ₹${a.startingPrice}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontSize: 13)),
                      const Icon(Icons.arrow_forward_ios,
                          size: 12, color: AppColors.primary),
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
}
