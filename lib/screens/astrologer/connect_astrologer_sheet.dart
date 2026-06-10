import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_model.dart';
import '../../providers/astrologer_provider.dart';

/// Opens the "Connect Astrologer" bottom sheet listing astrologers and their
/// service pricing.
void showConnectAstrologerSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ConnectAstrologerSheet(),
  );
}

class _ConnectAstrologerSheet extends ConsumerWidget {
  const _ConnectAstrologerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(topRatedAstrologersProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Text('Connect an Astrologer',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Get an expert porutham & horoscope opinion',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: top.length,
                itemBuilder: (_, i) => AstrologerSheetCard(astrologer: top[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Astrologer card used inside the Connect sheet — shows identity, rating and
/// a couple of priced services.
class AstrologerSheetCard extends StatelessWidget {
  final Astrologer astrologer;
  const AstrologerSheetCard({super.key, required this.astrologer});

  @override
  Widget build(BuildContext context) {
    final a = astrologer;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: NetworkImage(a.photoUrl),
                  onBackgroundImageError: (_, __) {},
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(a.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          _availabilityDot(a.isAvailable),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.star, size: 15, color: AppColors.gold),
                        const SizedBox(width: 3),
                        Text('${a.rating} (${a.reviewCount})',
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 10),
                        Icon(Icons.work_history_outlined,
                            size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 3),
                        Text('${a.experienceYears} yrs',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      ]),
                      const SizedBox(height: 3),
                      Text(a.languages.join(' · '),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: -6,
              children: a.specializations
                  .map((s) => Chip(
                        label: Text(s, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppColors.primary.withOpacity(0.08),
                        side: BorderSide.none,
                      ))
                  .toList(),
            ),
            const Divider(height: 18),
            // First two priced services
            ...a.services.take(2).map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(s.name, style: const TextStyle(fontSize: 13))),
                      Text('₹${s.price}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.push('/astrologer/${a.id}'),
                    child: const Text('View Profile'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => context.push('/astrologer/${a.id}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('From ₹${a.startingPrice}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _availabilityDot(bool available) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: available ? AppColors.success : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(available ? 'Online' : 'Offline',
              style: TextStyle(
                  fontSize: 11,
                  color: available ? AppColors.success : Colors.grey)),
        ],
      );
}
