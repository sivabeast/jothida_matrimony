import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/astrologer_session_provider.dart';
import 'astrologer_common.dart';

/// Reputation page — aggregate rating and a star-by-star breakdown only.
///
/// Reviewer identities are NEVER shown here (no name, phone or details) — only
/// the rating statistics.
class AstrologerReviewsTab extends ConsumerWidget {
  const AstrologerReviewsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAstrologerAccountProvider);
    if (account == null) return const AstrologerLoading();

    final breakdown = account.ratingBreakdown;
    final totalFromBreakdown =
        breakdown.values.fold<int>(0, (s, v) => s + v);
    final totalReviews =
        account.reviewCount > 0 ? account.reviewCount : totalFromBreakdown;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Aggregate score ─────────────────────────────────────────────
        AstrologerCard(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Text(account.rating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 48, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < account.rating.round()
                        ? Icons.star
                        : Icons.star_border,
                    color: AppColors.gold,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('$totalReviews Reviews',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const AstrologerSectionTitle('Rating Breakdown'),
        if (totalReviews == 0)
          const AstrologerEmptyState(
            icon: Icons.reviews_outlined,
            message: 'No reviews yet',
            hint: 'Ratings from users will appear here.',
          )
        else
          AstrologerCard(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  _breakdownRow(star, breakdown[star] ?? 0, totalReviews),
              ],
            ),
          ),
      ],
    );
  }

  Widget _breakdownRow(int star, int count, int total) {
    final fraction = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Row(
              children: [
                Text('$star', style: const TextStyle(fontSize: 13)),
                const Icon(Icons.star, size: 13, color: AppColors.gold),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 9,
                backgroundColor: Colors.grey.shade200,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.gold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text('$count',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
          ),
        ],
      ),
    );
  }
}
