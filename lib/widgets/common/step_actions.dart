import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import 'gradient_button.dart';

/// The bottom action pair every OPTIONAL profile-creation step ends with:
///
/// ```
/// [           தொடரவும்            ]   ← primary, filled
/// [             தவிர்             ]   ← secondary, full width
/// ```
///
/// Both buttons are full width and the same height, so the two optional
/// choices read as siblings rather than as a button and an afterthought. Skip
/// is deliberately the QUIETER of the two — outlined, not filled — because
/// continuing (and keeping whatever was entered) is the better default.
///
/// [onSkip] null renders Continue alone, which is what the mandatory steps and
/// the single-section editor want: there is nothing to skip to.
class StepActions extends StatelessWidget {
  /// Saves this step and moves on.
  final VoidCallback onContinue;

  /// Moves on WITHOUT saving. Null hides the Skip button entirely.
  final VoidCallback? onSkip;

  /// Overrides the primary label (defaults to the localized "Continue").
  final String? continueLabel;

  const StepActions({
    super.key,
    required this.onContinue,
    this.onSkip,
    this.continueLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        GradientButton(
            onPressed: onContinue, text: continueLabel ?? l10n.continueLabel),
        if (onSkip != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: onSkip,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                l10n.skip,
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
