import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';

/// The premium "Complete your profile to discover matching profiles" card.
///
/// Shown wherever matrimony content is withheld because the signed-in member
/// has not created their profile yet — the Home dashboard and the Matches tab.
/// It is the ONLY way profile creation starts: nothing anywhere else forces the
/// wizard on the member.
class CreateProfileCta extends StatelessWidget {
  /// Headline. Defaults to the Home wording; Matches passes its own.
  final String? title;

  /// Fills the available height (Matches full-page state) instead of hugging
  /// its content (Home, inside a scrolling list).
  final bool expanded;

  const CreateProfileCta({super.key, this.title, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF4F7), Color(0xFFFFF9EC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.16),
                  AppColors.gold.withValues(alpha: 0.22),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.favorite_rounded,
                size: 36, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          // Tamil headlines are long: they wrap between WHOLE words and are
          // never truncated or split mid-word.
          Text(
            title ?? l10n.createProfileCtaTitle,
            textAlign: TextAlign.center,
            softWrap: true,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16.5,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.createProfileCtaBody,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
                fontSize: 13, height: 1.45, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              // The ONE entry point into the profile wizard.
              onPressed: () => context.push('/profile/create'),
              icon: const Icon(Icons.person_add_alt_1, size: 20),
              label: Text(
                l10n.createProfile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );

    if (!expanded) return card;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: card,
      ),
    );
  }
}
