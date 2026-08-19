import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// A clean, single highlight pill shown on browse cards to mark a profile as
/// suitable/relevant — replacing the old Excellent/Good/Average rating badges.
///
/// It shows ONE of two labels and NEVER a score, percentage or grade:
///   • "✓ Matches your Nakshatra" — the profile's star is compatible with the
///     user's. Because that is a POSITIVE state it is always rendered in green,
///     never gold/yellow (see [nakshatraOnly] callers).
///   • "⭐ Best Match" — the profile satisfies every partner preference the
///     user has set.
///
/// Renders nothing ([SizedBox.shrink]) when the profile is neither, or while the
/// signed-in user's own profile is still loading, so callers can drop it
/// straight into a Stack/Row without null guards.
class ProfileHighlightBadge extends ConsumerWidget {
  final ProfileModel profile;

  /// Compact variant for dense cards (smaller padding/text).
  final bool compact;

  /// Optional solid background colour for the PREFERENCE ("Best Match")
  /// variant. The nakshatra variant is always green — a positive compatibility
  /// state must read as positive everywhere.
  final Color? color;

  /// When true the badge renders ONLY for a nakshatra match — the plain
  /// preference-match variant is suppressed. The Matches page uses this so a
  /// profile carries exactly one badge and never a second quality label.
  final bool nakshatraOnly;

  const ProfileHighlightBadge({
    super.key,
    required this.profile,
    this.compact = false,
    this.color,
    this.nakshatraOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    final highlight = profileHighlight(me, profile);
    if (highlight == ProfileHighlight.none) return const SizedBox.shrink();
    if (nakshatraOnly && highlight != ProfileHighlight.nakshatra) {
      return const SizedBox.shrink();
    }

    final isNakshatra = highlight == ProfileHighlight.nakshatra;
    final label = isNakshatra
        ? context.l10n.matchesYourNakshatra
        : context.l10n.matchingProfile;

    // Nakshatra compatibility is a POSITIVE signal → green chip with a check,
    // never the gold/amber pill used for the generic preference match.
    if (isNakshatra) {
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: AppColors.success.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                size: compact ? 12 : 14, color: AppColors.success),
            SizedBox(width: compact ? 4 : 5),
            Flexible(
              child: Text(
                label,
                softWrap: true,
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: compact ? 10 : 11.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ],
        ),
      );
    }

    final solid = color != null;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: solid ? color : null,
        gradient: solid
            ? null
            : const LinearGradient(
                colors: [AppColors.gold, AppColors.goldDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: (solid ? color! : AppColors.gold).withValues(alpha: 0.35),
              blurRadius: 5),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('⭐', style: TextStyle(fontSize: compact ? 10 : 12)),
          SizedBox(width: compact ? 4 : 6),
          // softWrap keeps the Tamil label fully visible if it needs a second
          // line rather than clipping it with an ellipsis.
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                color: solid ? Colors.white : AppColors.textOnGold,
                fontSize: compact ? 10 : 12.5,
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
