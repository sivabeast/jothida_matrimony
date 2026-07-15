import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// A clean, single ⭐ highlight pill shown on browse cards to mark a profile as
/// suitable/relevant — replacing the old Excellent/Good/Average rating badges.
///
/// It shows ONE of two labels and NEVER a score, percentage or grade:
///   • "⭐ Nakshatra Match" — the profile's star is compatible with the user's;
///   • "⭐ Matching Profile" — the profile satisfies the user's partner
///     preferences (age + caste priorities).
///
/// Renders nothing ([SizedBox.shrink]) when the profile is neither, or while the
/// signed-in user's own profile is still loading, so callers can drop it
/// straight into a Stack/Row without null guards.
class ProfileHighlightBadge extends ConsumerWidget {
  final ProfileModel profile;

  /// Compact variant for dense cards (smaller padding/text).
  final bool compact;

  const ProfileHighlightBadge({
    super.key,
    required this.profile,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    final highlight = profileHighlight(me, profile);
    if (highlight == ProfileHighlight.none) return const SizedBox.shrink();

    final label = highlight == ProfileHighlight.nakshatra
        ? context.l10n.nakshatraMatch
        : context.l10n.matchingProfile;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gold, AppColors.goldDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.35), blurRadius: 5),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('⭐', style: TextStyle(fontSize: compact ? 10 : 12)),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textOnGold,
              fontSize: compact ? 10 : 12.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }
}
