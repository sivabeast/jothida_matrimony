import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/nakshatra_compatibility_provider.dart';
import '../../providers/profile_provider.dart';

/// A small green "Horoscope Match" badge shown when the current user's
/// nakshatra is compatible with [targetNakshatra].
///
/// IMPORTANT: this is purely informational. It renders nothing (an empty box)
/// when the pair is not compatible, when data is missing, or while the dataset
/// is still loading — it must NEVER be used to hide or filter a profile.
class HoroscopeMatchBadge extends ConsumerWidget {
  final String? targetNakshatra;

  /// Compact variant for dense cards (smaller padding/text).
  final bool compact;

  const HoroscopeMatchBadge({
    super.key,
    required this.targetNakshatra,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myProfileProvider).valueOrNull?.horoscope.nakshatra;
    final compat = ref.watch(nakshatraCompatibilityProvider).valueOrNull;
    if (compat == null) return const SizedBox.shrink();
    if (!compat.isCompatible(mine, targetNakshatra)) {
      return const SizedBox.shrink();
    }

    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, color: Colors.white, size: compact ? 11 : 14),
          SizedBox(width: compact ? 3 : 5),
          Text(
            compact ? 'Match' : 'Horoscope Match',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 9.5 : 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
