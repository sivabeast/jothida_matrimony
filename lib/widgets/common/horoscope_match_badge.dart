import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/porutham_match.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// Colour for each compatibility category (matches the spec's emoji dots).
Color categoryColor(MatchCategory c) => switch (c) {
      MatchCategory.excellent => AppColors.success,
      MatchCategory.good => const Color(0xFFEAB308), // 🟡 amber
      MatchCategory.average => const Color(0xFFF97316), // 🟠 orange
      MatchCategory.poor => AppColors.error, // 🔴 red
    };

/// Profile-card badge showing the traditional 10-porutham compatibility
/// CATEGORY between the logged-in user and [target] — e.g. "🟢 Excellent Match".
///
/// There is NO percentage. It renders nothing when the horoscope data needed to
/// compute the poruthams is missing — it must NEVER hide or filter a profile.
class HoroscopeMatchBadge extends ConsumerWidget {
  final ProfileModel target;

  /// Compact variant for dense cards (smaller padding/text).
  final bool compact;

  const HoroscopeMatchBadge({
    super.key,
    required this.target,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    if (me == null) return const SizedBox.shrink();

    final result = computePorutham(me, target);
    if (result == null) return const SizedBox.shrink();

    final color = categoryColor(result.category);
    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(result.category.emoji,
              style: TextStyle(fontSize: compact ? 9 : 11)),
          SizedBox(width: compact ? 3 : 5),
          Text(
            result.category.label,
            style: TextStyle(
              color: color,
              fontSize: compact ? 9.5 : 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
